using ChatApp.Data;
using ChatApp.Models;
using Microsoft.EntityFrameworkCore;
using MongoDB.Bson;

namespace ChatApp.Services;

public sealed class CallService(ChatDbContext db)
{
    public const string Ringing = "Ringing";
    public const string Answered = "Answered";
    public const string Completed = "Completed";
    public const string Missed = "Missed";
    public const string Rejected = "Rejected";

    /// <summary>
    /// Batas usia panggilan yang masih dianggap berdering. Lebih pendek dari umur
    /// sinyal FCM supaya panggilan basi tidak ikut dimunculkan lagi.
    /// </summary>
    public static readonly TimeSpan RingingWindow = TimeSpan.FromSeconds(45);

    public async Task<CallHistory> StartAsync(
        ObjectId callerId,
        ObjectId receiverId,
        string callType = "Audio",
        CancellationToken cancellationToken = default,
        string? groupCallId = null, string? conversationId = null, string? conversationName = null, int memberCount = 2)
    {
        var call = new CallHistory
        {
            Id = ObjectId.GenerateNewId(),
            GroupCallId = groupCallId, ConversationId = conversationId, ConversationName = conversationName, MemberCount = memberCount,
            CallerId = callerId,
            ReceiverId = receiverId,
            CallType = callType,
            StartDate = DateTime.UtcNow,
            Status = Ringing
        };

        db.CallHistories.Add(call);
        await db.SaveChangesAsync(cancellationToken);

        return call;
    }

    public async Task UpdateGroupHistoryAsync(ObjectId id, bool answered, bool rejected = false)
    {
        var call = await GetByIdAsync(id);
        if (call is null || call.EndDate != null) return;
        if (answered) { call.Status = Answered; call.AnsweredAt = DateTime.UtcNow; }
        else {
            call.EndDate = DateTime.UtcNow;
            call.Duration = call.AnsweredAt.HasValue ? (int)(call.EndDate.Value - call.AnsweredAt.Value).TotalSeconds : 0;
            call.Status = rejected ? Rejected : call.AnsweredAt.HasValue ? Completed : Missed;
        }
        await db.SaveChangesAsync();
    }

    public async Task MarkAnsweredAsync(
        ObjectId userA,
        ObjectId userB,
        CancellationToken cancellationToken = default)
    {
        var call = await FindActiveAsync(userA, userB, cancellationToken);
        if (call is null) return;

        call.Status = Answered;
        call.AnsweredAt = DateTime.UtcNow;

        await db.SaveChangesAsync(cancellationToken);
    }

    public async Task MarkRejectedAsync(
        ObjectId userA,
        ObjectId userB,
        CancellationToken cancellationToken = default)
    {
        var call = await FindActiveAsync(userA, userB, cancellationToken);
        if (call is null) return;

        call.Status = Rejected;
        call.EndDate = DateTime.UtcNow;
        call.Duration = 0;

        await db.SaveChangesAsync(cancellationToken);
    }

    /// <summary>
    /// Menutup panggilan yang sedang berjalan. Panggilan yang tidak pernah
    /// diangkat dicatat sebagai Missed, sisanya Completed beserta durasinya.
    /// </summary>
    /// <returns>Panggilan yang ditutup, atau null bila tidak ada yang aktif.</returns>
    public async Task<CallHistory?> MarkEndedAsync(
        ObjectId userA,
        ObjectId userB,
        CancellationToken cancellationToken = default)
    {
        var call = await FindActiveAsync(userA, userB, cancellationToken);
        if (call is null) return null;

        var endedAt = DateTime.UtcNow;

        call.Duration = call.AnsweredAt.HasValue
            ? (int)Math.Max(0, (endedAt - call.AnsweredAt.Value).TotalSeconds)
            : 0;
        call.Status = call.AnsweredAt.HasValue ? Completed : Missed;
        call.EndDate = endedAt;

        await db.SaveChangesAsync(cancellationToken);

        return call;
    }

    private async Task<CallHistory?> FindActiveAsync(
        ObjectId userA,
        ObjectId userB,
        CancellationToken cancellationToken)
    {
        return await db.CallHistories
            .Where(c => c.GroupCallId == null && c.EndDate == null
                && ((c.CallerId == userA && c.ReceiverId == userB)
                    || (c.CallerId == userB && c.ReceiverId == userA)))
            .OrderByDescending(c => c.StartDate)
            .FirstOrDefaultAsync(cancellationToken);
    }

    /// <summary>
    /// Panggilan masuk yang masih berdering untuk seorang penerima.
    ///
    /// Dipakai halaman web saat baru dibuka dari notifikasi: payload FCM tidak
    /// selalu selamat melewati proses start ulang aplikasi, jadi keadaan
    /// panggilannya diambil ulang dari database.
    /// </summary>
    public async Task<CallHistory?> GetRingingForReceiverAsync(
        ObjectId receiverId,
        CancellationToken cancellationToken = default)
    {
        var oldest = DateTime.UtcNow - RingingWindow;

        return await db.CallHistories
            .Where(c => c.ReceiverId == receiverId
                && c.Status == Ringing
                && c.EndDate == null
                && c.StartDate > oldest)
            .OrderByDescending(c => c.StartDate)
            .FirstOrDefaultAsync(cancellationToken);
    }

    public async Task<CallHistory?> GetByIdAsync(
        ObjectId callId,
        CancellationToken cancellationToken = default)
    {
        return await db.CallHistories.FirstOrDefaultAsync(c => c.Id == callId, cancellationToken);
    }

    /// <summary>Menolak panggilan tertentu, dipakai jalur REST saat SignalR belum tersambung.</summary>
    public async Task MarkRejectedByIdAsync(
        ObjectId callId,
        CancellationToken cancellationToken = default)
    {
        var call = await db.CallHistories
            .FirstOrDefaultAsync(c => c.Id == callId && c.EndDate == null, cancellationToken);

        if (call is null) return;

        call.Status = Rejected;
        call.EndDate = DateTime.UtcNow;
        call.Duration = 0;

        await db.SaveChangesAsync(cancellationToken);
    }

    public async Task<List<CallHistoryDto>> GetForUserAsync(
        ObjectId userId,
        int limit = 50,
        CancellationToken cancellationToken = default)
    {
        var calls = await db.CallHistories
            .AsNoTracking()
            .Where(c => c.CallerId == userId || c.ReceiverId == userId)
            .OrderByDescending(c => c.StartDate)
            .Take(Math.Clamp(limit, 1, 200))
            .ToListAsync(cancellationToken);

        if (calls.Count == 0) return [];

        var peerIds = calls
            .Select(c => c.CallerId == userId ? c.ReceiverId : c.CallerId)
            .Distinct()
            .ToList();

        var peerById = await db.Users
            .AsNoTracking()
            .Where(u => peerIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, u => u.Username, cancellationToken);

        // A host has one stored invitation per recipient, displayed as one group call.
        return calls.GroupBy(c => c.GroupCallId ?? c.Id.ToString())
            .Select(g => g.OrderByDescending(c => c.Status == Answered || c.Status == Completed)
                .ThenByDescending(c => c.Duration ?? 0).First())
            .Select(call =>
        {
            var outgoing = call.CallerId == userId;
            var peerId = outgoing ? call.ReceiverId : call.CallerId;

            return new CallHistoryDto(
                call.Id.ToString(),
                peerById.TryGetValue(peerId, out var username) ? username : "(unknown)",
                call.CallType,
                call.Status,
                outgoing,
                call.StartDate,
                call.EndDate,
                call.Duration, call.GroupCallId != null, call.ConversationId, call.ConversationName, call.MemberCount);
        }).ToList();
    }
}
