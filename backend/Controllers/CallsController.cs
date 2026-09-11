using ChatApp.Hubs;
using ChatApp.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.SignalR;
using MongoDB.Bson;

namespace ChatApp.Controllers;

public record DeclineCallRequest(string? DeviceToken);

[ApiController]
[Authorize]
[Route("api/[controller]")]
public class CallsController(
    UserService users,
    CallService calls,
    GroupCallRegistry groupCalls,
    IHubContext<ChatHubs> hub) : ControllerBase
{
    /// <summary>Riwayat panggilan masuk dan keluar milik user yang sedang login.</summary>
    [HttpGet]
    public async Task<IActionResult> Gets([FromQuery] int limit = 50, CancellationToken cancellationToken = default)
    {
        var me = await CurrentUserAsync();
        if (me is null) return Unauthorized();

        return Ok(await calls.GetForUserAsync(me.Id, limit, cancellationToken));
    }

    /// <summary>
    /// Panggilan masuk yang masih berdering untuk user ini.
    ///
    /// Dipakai halaman web ketika baru dibuka dari notifikasi panggilan: keadaan
    /// panggilan diambil dari database, bukan dari payload notifikasi yang belum
    /// tentu selamat melewati start ulang aplikasi.
    /// </summary>
    [HttpGet("ringing")]
    public async Task<IActionResult> Ringing(CancellationToken cancellationToken)
    {
        var me = await CurrentUserAsync();
        if (me is null) return Unauthorized();

        var call = await calls.GetRingingForReceiverAsync(me.Id, cancellationToken);
        if (call is null) return Ok(new { ringing = false });
        if (call.GroupCallId != null) {
            await groupCalls.Gate.WaitAsync(cancellationToken);
            try { if (!groupCalls.Rooms.ContainsKey(call.GroupCallId)) return Ok(new { ringing = false }); }
            finally { groupCalls.Gate.Release(); }
        }

        var caller = (await users.GetByIdsAsync([call.CallerId])).FirstOrDefault();
        if (caller is null) return Ok(new { ringing = false });

        return Ok(new
        {
            ringing = true,
            callId = call.Id.ToString(),
            isGroup = call.GroupCallId != null, groupCallId = call.GroupCallId,
            conversationId = call.ConversationId, conversationName = call.ConversationName, memberCount = call.MemberCount,
            callerUsername = caller.Username,
            callerName = string.IsNullOrWhiteSpace(caller.FullName) ? caller.Username : caller.FullName,
            callType = call.CallType,
            startedAt = call.StartDate
        });
    }

    /// <summary>Decline a call using the recipient's bearer session.</summary>
    [HttpPost("{id}/decline")]
    public async Task<IActionResult> Decline(
        string id,
        [FromBody] DeclineCallRequest request,
        CancellationToken cancellationToken)
    {
        if (!ObjectId.TryParse(id, out var callId))
            return BadRequest(new { message = "Id panggilan tidak valid." });

        var receiverId = await ResolveReceiverIdAsync(request, cancellationToken);
        if (receiverId is null) return Unauthorized();

        var call = await calls.GetByIdAsync(callId, cancellationToken);
        if (call is null) return NotFound();

        // Hanya penerima panggilan yang boleh menolaknya.
        if (call.ReceiverId != receiverId.Value) return Forbid();

        if (call.GroupCallId != null) {
            await groupCalls.Gate.WaitAsync(cancellationToken);
            try {
                if (groupCalls.Rooms.TryGetValue(call.GroupCallId, out var room)) {
                    var member = room.Members.FirstOrDefault(u => u.Id == receiverId.Value);
                    if (member is null) return Forbid();
                    if (room.Joined.Contains(member.Username)) return Conflict(new { message = "Call was already accepted." });
                    room.Declined.Add(member.Username);
                    await hub.Clients.Users(room.Joined.ToArray()).SendAsync("GroupParticipantDeclined", room.Id, member.Username, cancellationToken);
                    await hub.Clients.User(member.Username).SendAsync("GroupCallEnded", room.Id, member.Username, cancellationToken);
                }
                await calls.MarkRejectedByIdAsync(callId, cancellationToken);
                return NoContent();
            } finally { groupCalls.Gate.Release(); }
        }
        await calls.MarkRejectedByIdAsync(callId, cancellationToken);

        var participants = await users.GetByIdsAsync([call.CallerId, call.ReceiverId]);
        var caller = participants.FirstOrDefault(u => u.Id == call.CallerId);
        var receiver = participants.FirstOrDefault(u => u.Id == call.ReceiverId);

        if (caller is not null && receiver is not null)
        {
            await hub.Clients.User(caller.Username)
                .SendAsync("CallRejected", receiver.Username, cancellationToken);
        }

        return NoContent();
    }

    /// <summary>Resolve the signed-in recipient. FCM tokens are never login credentials.</summary>
    private async Task<ObjectId?> ResolveReceiverIdAsync(
        DeclineCallRequest request,
        CancellationToken cancellationToken)
    {
        var me = await CurrentUserAsync();
        if (me is not null) return me.Id;

        return null;
    }

    private async Task<Models.User?> CurrentUserAsync()
    {
        var username = User.Identity?.Name;
        return string.IsNullOrWhiteSpace(username)
            ? null
            : await users.GetByUsernameAsync(username);
    }
}


