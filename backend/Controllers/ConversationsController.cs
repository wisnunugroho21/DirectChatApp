using ChatApp.Models;
using ChatApp.Hubs;
using Microsoft.AspNetCore.SignalR;
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
    AttachmentService attachments,
    IHubContext<ChatHubs> hub) : ControllerBase
{
    public record CreateGroupRequest(string? Name, List<string>? Usernames);

    [HttpPost("groups")]
    public async Task<IActionResult> CreateGroup(CreateGroupRequest request, CancellationToken ct)
    {
        var me = await CurrentUserAsync();
        if (me is null) return Unauthorized();
        var names = (request.Usernames ?? []).Where(n => !string.IsNullOrWhiteSpace(n))
            .Select(n => n.Trim()).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        if (names.Count < 2 || names.Count >= ConversationService.MaxGroupMembers ||
            string.IsNullOrWhiteSpace(request.Name) || request.Name.Trim().Length > 80)
            return BadRequest(new { message = "Enter a group name (up to 80 characters) and select 2 to 49 people." });
        var members = new List<User>();
        foreach (var name in names)
        {
            var user = await users.GetByUsernameAsync(name);
            if (user is null || user.Id == me.Id)
                return BadRequest(new { message = "Select other registered users." });
            members.Add(user);
        }
        var group = await conversations.CreateGroupAsync(me.Id, request.Name, members.Select(u => u.Id).ToList(), ct);
        var summary = new ConversationSummaryDto(group.Id.ToString(), "", group.Name!, null, "", null,
            null, false, 0, "Group", group.Name, members.Count + 1);
        await hub.Clients.Users(members.Select(u => u.Username).Append(me.Username).ToList())
            .SendAsync("ConversationCreated", summary, ct);
        return Ok(summary);
    }

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
