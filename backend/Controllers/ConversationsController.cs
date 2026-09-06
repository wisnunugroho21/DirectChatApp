using ChatApp.Models;
using ChatApp.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MongoDB.Bson;

namespace ChatApp.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public class ConversationsController(
    UserService users,
    ConversationService conversations,
    MessageService messages,
    AttachmentService attachments) : ControllerBase
{
    /// <summary>Daftar percakapan milik user yang sedang login.</summary>
    [HttpGet]
    public async Task<IActionResult> Gets(CancellationToken cancellationToken)
    {
        var me = await CurrentUserAsync();
        if (me is null) return Unauthorized();

        return Ok(await conversations.GetForUserAsync(me.Id, cancellationToken));
    }

    /// <summary>Membuka (atau membuat) percakapan langsung dengan seorang user.</summary>
    [HttpPost("direct/{username}")]
    public async Task<IActionResult> OpenDirect(string username, CancellationToken cancellationToken)
    {
        var me = await CurrentUserAsync();
        if (me is null) return Unauthorized();

        var peer = await users.GetByUsernameAsync(username);
        if (peer is null) return NotFound(new { message = $"Pengguna '{username}' tidak ditemukan." });

        if (peer.Id == me.Id)
            return BadRequest(new { message = "Tidak bisa membuat percakapan dengan diri sendiri." });

        var conversation = await conversations.GetOrCreateDirectAsync(me.Id, peer.Id, cancellationToken);

        return Ok(new ConversationSummaryDto(
            conversation.Id.ToString(),
            peer.Username,
            peer.FullName,
            peer.PhotoUrl,
            peer.Status,
            null,
            null,
            false,
            0));
    }

    /// <summary>Riwayat pesan sebuah percakapan, urut lama ke baru.</summary>
    [HttpGet("{id}/messages")]
    public async Task<IActionResult> GetMessages(
        string id,
        [FromQuery] int limit = MessageService.DefaultHistoryLimit,
        [FromQuery] DateTime? before = null,
        CancellationToken cancellationToken = default)
    {
        if (!ObjectId.TryParse(id, out var conversationId))
            return BadRequest(new { message = "Id percakapan tidak valid." });

        var me = await CurrentUserAsync();
        if (me is null) return Unauthorized();

        if (!await conversations.IsMemberAsync(conversationId, me.Id, cancellationToken))
            return Forbid();

        var history = await messages.GetHistoryAsync(conversationId, limit, before, cancellationToken);

        var senderNames = await users.GetByIdsAsync(history.Select(m => m.SenderId));
        var nameById = senderNames.ToDictionary(u => u.Id, u => u.Username);

        // Lampiran seluruh halaman diambil sekali, bukan per pesan.
        var attachmentByMessage = await attachments.GetForMessagesAsync(
            history.Select(m => m.Id).ToList(), cancellationToken);

        var dtos = history
            .Select(m => messages.ToDto(
                m,
                nameById.TryGetValue(m.SenderId, out var name) ? name : "(unknown)",
                me.Id,
                attachmentByMessage.GetValueOrDefault(m.Id)))
            .ToList();

        return Ok(dtos);
    }

    [HttpPost("{id}/read")]
    public async Task<IActionResult> MarkRead(string id, CancellationToken cancellationToken)
    {
        if (!ObjectId.TryParse(id, out var conversationId))
            return BadRequest(new { message = "Id percakapan tidak valid." });

        var me = await CurrentUserAsync();
        if (me is null) return Unauthorized();

        if (!await conversations.IsMemberAsync(conversationId, me.Id, cancellationToken))
            return Forbid();

        await messages.MarkReadAsync(conversationId, me.Id, cancellationToken);
        return NoContent();
    }

    /// <summary>Keluar dari percakapan (menghapusnya dari daftar milik user ini).</summary>
    [HttpDelete("{id}")]
    public async Task<IActionResult> Delete(string id, CancellationToken cancellationToken)
    {
        if (!ObjectId.TryParse(id, out var conversationId))
            return BadRequest(new { message = "Id percakapan tidak valid." });

        var me = await CurrentUserAsync();
        if (me is null) return Unauthorized();

        if (!await conversations.IsMemberAsync(conversationId, me.Id, cancellationToken))
            return Forbid();

        await conversations.LeaveAsync(conversationId, me.Id, cancellationToken);
        return NoContent();
    }

    private async Task<User?> CurrentUserAsync()
    {
        var username = User.Identity?.Name;
        return string.IsNullOrWhiteSpace(username)
            ? null
            : await users.GetByUsernameAsync(username);
    }
}
