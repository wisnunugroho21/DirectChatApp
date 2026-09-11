using ChatApp.Data;
using ChatApp.Hubs;
using ChatApp.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using Microsoft.EntityFrameworkCore;
using MongoDB.Bson;

namespace ChatApp.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public class AttachmentsController(
    ChatDbContext db,
    UserService users,
    ConversationService conversations,
    MessageService messages,
    AttachmentService attachments,
    ConnectionTracker connections,
    PushNotificationService push,
    IHubContext<ChatHubs> hub) : ControllerBase
{
    /// <summary>
    /// Mengunduh lampiran. Hanya anggota percakapan yang boleh mengaksesnya —
    /// karena itu berkasnya tidak disimpan di wwwroot.
    /// </summary>
    [HttpGet("{id}")]
    public async Task<IActionResult> Download(string id, CancellationToken cancellationToken)
    {
        if (!ObjectId.TryParse(id, out var attachmentId))
            return BadRequest(new { message = "Id lampiran tidak valid." });

        var me = await CurrentUserAsync();
        if (me is null) return Unauthorized();

        var attachment = await attachments.GetByIdAsync(attachmentId, cancellationToken);
        if (attachment is null) return NotFound();

        var message = await db.Messages
            .FirstOrDefaultAsync(m => m.Id == attachment.MessageId, cancellationToken);

        if (message is null) return NotFound();

        if (!await conversations.IsMemberAsync(message.ConversationId, me.Id, cancellationToken))
            return Forbid();

        var content = attachments.OpenRead(attachment);
        if (content is null) return NotFound();

        // Berkas yang dibuka inline dijalankan pada origin aplikasi, jadi hanya
        // tipe gambar yang aman yang ditampilkan langsung; sisanya dipaksa
        // terunduh. nosniff mencegah browser menebak tipe lain dari isinya.
        Response.Headers.XContentTypeOptions = "nosniff";

        var inline = AttachmentService.IsInlineSafe(attachment.MimeType);

        return File(content, attachment.MimeType, inline ? null : attachment.FileName);
    }

    /// <summary>Mengunggah berkas sebagai pesan baru dalam sebuah percakapan.</summary>
    [HttpPost("conversations/{conversationId}")]
    [RequestSizeLimit(26 * 1024 * 1024)]
    public async Task<IActionResult> Upload(
        string conversationId,
        IFormFile? file,
        CancellationToken cancellationToken)
    {
        if (!ObjectId.TryParse(conversationId, out var conversation))
            return BadRequest(new { message = "Id percakapan tidak valid." });

        if (file is null || file.Length == 0)
            return BadRequest(new { message = "Berkas wajib dipilih." });

        if (file.Length > attachments.MaxFileSizeBytes)
            return BadRequest(new { message = $"Ukuran berkas melebihi {attachments.MaxFileSizeBytes / (1024 * 1024)} MB." });

        var me = await CurrentUserAsync();
        if (me is null) return Unauthorized();

        if (!await conversations.IsMemberAsync(conversation, me.Id, cancellationToken))
            return Forbid();

        await using var content = file.OpenReadStream();

        var (message, attachment) = await attachments.SaveAsync(
            conversation,
            me.Id,
            content,
            file.FileName,
            file.ContentType,
            cancellationToken);

        // Penerima dikabari lewat jalur yang sama dengan pesan teks, supaya
        // lampiran muncul seketika dan tetap memicu notifikasi bila offline.
        var members = await conversations.MembersAsync(conversation, cancellationToken);

        foreach (var peer in members.Where(u => u.Id != me.Id))
        {
            await hub.Clients.User(peer.Username).SendAsync(
                "ReceiveMessage",
                messages.ToDto(message, me.Username, peer.Id, attachment),
                cancellationToken);

            await push.SendChatMessageAsync(
                peer,
                me,
                message,
                connections.GetActiveDeviceTokens(peer.Username),
                cancellationToken);
        }

        return Ok(messages.ToDto(message, me.Username, me.Id, attachment));
    }

    private async Task<Models.User?> CurrentUserAsync()
    {
        var username = User.Identity?.Name;
        return string.IsNullOrWhiteSpace(username)
            ? null
            : await users.GetByUsernameAsync(username);
    }
}
