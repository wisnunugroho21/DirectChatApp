using ChatApp.Data;
using ChatApp.Models;
using Microsoft.EntityFrameworkCore;
using MongoDB.Bson;

namespace ChatApp.Services;

public sealed class ConversationService(ChatDbContext db, ChatTypeCatalog types)
{
    public const int MaxGroupMembers = 50;

    public async Task<Conversation> CreateGroupAsync(ObjectId creator, string name,
        IReadOnlyCollection<ObjectId> members, CancellationToken cancellationToken = default)
    {
        var ids = members.Append(creator).Distinct().ToList();
        if (string.IsNullOrWhiteSpace(name) || name.Trim().Length > 80 || ids.Count < 3 || ids.Count > MaxGroupMembers)
            throw new ArgumentException("Enter a group name (up to 80 characters) and select 2 to 49 people.");
        var conversation = new Conversation {
            Id = ObjectId.GenerateNewId(), Name = name.Trim(), CreatedBy = creator,
            TypeId = types.ConversationTypeId(ChatTypeCatalog.GroupConversation)
        };
        db.Conversations.Add(conversation);
        db.ConversationMembers.AddRange(ids.Select(id => new ConversationMember {
            Id = ObjectId.GenerateNewId(), ConversationId = conversation.Id, UserId = id,
            Role = id == creator ? "Admin" : "Member", JoinDate = DateTime.UtcNow
        }));
        await db.SaveChangesAsync(cancellationToken);
        return conversation;
    }

    public Task<Conversation?> GetAsync(ObjectId id, CancellationToken ct = default) =>
        db.Conversations.FirstOrDefaultAsync(c => c.Id == id, ct);

    public async Task<List<User>> MembersAsync(ObjectId id, CancellationToken ct = default)
    {
        var ids = await db.ConversationMembers.Where(m => m.ConversationId == id)
            .Select(m => m.UserId).ToListAsync(ct);
        return await db.Users.Where(u => ids.Contains(u.Id)).ToListAsync(ct);
    }

    /// <summary>
    /// Kunci deterministik untuk percakapan 1-1: id user diurutkan dulu supaya
    /// pasangan yang sama selalu menghasilkan kunci yang sama dari sisi mana pun.
    /// </summary>
    public static string DirectKeyFor(ObjectId a, ObjectId b)
    {
        var (first, second) = a.CompareTo(b) <= 0 ? (a, b) : (b, a);
        return $"{first}:{second}";
    }

    /// <summary>
    /// Mengambil percakapan langsung antara dua user, membuatnya bila belum ada.
    ///
    /// Keunikannya dijaga index unik pada DirectKey: kalau dua sisi mengirim
    /// pesan pertama bersamaan, salah satu penyisipan ditolak server dan sisi
    /// yang kalah membaca ulang percakapan yang sudah terbentuk.
    /// </summary>
    public async Task<Conversation> GetOrCreateDirectAsync(
        ObjectId userId,
        ObjectId peerId,
        CancellationToken cancellationToken = default)
    {
        if (userId == peerId)
            throw new InvalidOperationException("Tidak bisa membuat percakapan dengan diri sendiri.");

        var key = DirectKeyFor(userId, peerId);

        var conversation = await db.Conversations
            .FirstOrDefaultAsync(c => c.DirectKey == key, cancellationToken);

        if (conversation is null)
        {
            conversation = new Conversation
            {
                Id = ObjectId.GenerateNewId(),
                DirectKey = key,
                TypeId = types.ConversationTypeId(ChatTypeCatalog.DirectConversation),
                CreatedBy = userId,
                CreatedAt = DateTime.UtcNow
            };

            db.Conversations.Add(conversation);

            if (!await db.TrySaveChangesAsync(cancellationToken))
            {
                conversation = await db.Conversations.FirstAsync(c => c.DirectKey == key, cancellationToken);
            }
        }

        await EnsureMemberAsync(conversation.Id, userId, cancellationToken);
        await EnsureMemberAsync(conversation.Id, peerId, cancellationToken);

        return conversation;
    }

    /// <summary>
    /// Menambahkan user ke percakapan bila belum menjadi anggota. Penyisipan
    /// ganda ditolak index unik (ConversationId, UserId).
    /// </summary>
    public async Task EnsureMemberAsync(
        ObjectId conversationId,
        ObjectId userId,
        CancellationToken cancellationToken = default)
    {
        var exists = await db.ConversationMembers
            .AnyAsync(m => m.ConversationId == conversationId && m.UserId == userId, cancellationToken);

        if (exists) return;

        db.ConversationMembers.Add(new ConversationMember
        {
            Id = ObjectId.GenerateNewId(),
            ConversationId = conversationId,
            UserId = userId,
            Role = "Member",
            JoinDate = DateTime.UtcNow
        });

        await db.TrySaveChangesAsync(cancellationToken);
    }

    public async Task<bool> IsMemberAsync(
        ObjectId conversationId,
        ObjectId userId,
        CancellationToken cancellationToken = default)
    {
        return await db.ConversationMembers
            .AnyAsync(m => m.ConversationId == conversationId && m.UserId == userId, cancellationToken);
    }

    /// <summary>
    /// Daftar percakapan untuk sidebar: lawan bicara, pesan terakhir, dan jumlah
    /// pesan belum dibaca.
    /// </summary>
    public async Task<List<ConversationSummaryDto>> GetForUserAsync(
        ObjectId userId,
        CancellationToken cancellationToken = default)
    {
        var memberships = await db.ConversationMembers
            .Where(m => m.UserId == userId)
            .ToListAsync(cancellationToken);

        if (memberships.Count == 0) return [];

        var conversationIds = memberships.Select(m => m.ConversationId).ToList();

        var peerMembers = await db.ConversationMembers
            .Where(m => conversationIds.Contains(m.ConversationId) && m.UserId != userId)
            .ToListAsync(cancellationToken);

        var peerIds = peerMembers.Select(m => m.UserId).Distinct().ToList();

        var peerById = await db.Users
            .Where(u => peerIds.Contains(u.Id))
            .ToDictionaryAsync(u => u.Id, cancellationToken);

        var records = await db.Conversations.Where(c => conversationIds.Contains(c.Id))
            .ToDictionaryAsync(c => c.Id, cancellationToken);
        var summaries = new List<ConversationSummaryDto>();

        foreach (var membership in memberships)
        {
            var peerMember = peerMembers.FirstOrDefault(m => m.ConversationId == membership.ConversationId);
            if (!records.TryGetValue(membership.ConversationId, out var record)) continue;
            var isGroup = record.TypeId == types.ConversationTypeId(ChatTypeCatalog.GroupConversation);
            var peer = peerMember is null ? null : peerById.GetValueOrDefault(peerMember.UserId);
            if (!isGroup && peer is null) continue;

            var conversationId = membership.ConversationId;

            // Satu query per percakapan, keduanya memakai index
            // (ConversationId, CreatedAt) sehingga hanya menyentuh sedikit dokumen.
            // Agregasi $group yang menggabungkan semuanya jadi satu perjalanan
            // tidak tersedia lewat EF.
            var last = await db.Messages
                .Where(m => m.ConversationId == conversationId && m.DeletedAt == null)
                .OrderByDescending(m => m.CreatedAt)
                .FirstOrDefaultAsync(cancellationToken);

            var since = membership.LastReadAt ?? DateTime.UnixEpoch;

            var unread = await db.Messages
                .CountAsync(m => m.ConversationId == conversationId
                    && m.SenderId != userId
                    && m.CreatedAt > since
                    && m.DeletedAt == null, cancellationToken);

            summaries.Add(new ConversationSummaryDto(
                conversationId.ToString(),
                isGroup ? "" : peer!.Username,
                isGroup ? record.Name ?? "Untitled group" : peer!.FullName,
                isGroup ? record.PhotoUrl : peer!.PhotoUrl,
                isGroup ? "" : peer!.Status,
                last?.MessageText,
                last?.CreatedAt,
                last is not null && last.SenderId == userId,
                unread, isGroup ? "Group" : "Direct", record.Name,
                peerMembers.Count(m => m.ConversationId == conversationId) + 1));
        }

        return summaries
            .OrderByDescending(s => s.LastMessageAt ?? DateTime.MinValue)
            .ToList();
    }

    /// <summary>
    /// Mengeluarkan user dari percakapan. Kalau tidak ada anggota tersisa,
    /// percakapan beserta pesan dan lampirannya ikut dihapus.
    /// </summary>
    public async Task LeaveAsync(
        ObjectId conversationId,
        ObjectId userId,
        CancellationToken cancellationToken = default)
    {
        await db.ConversationMembers
            .Where(m => m.ConversationId == conversationId && m.UserId == userId)
            .ExecuteDeleteAsync(cancellationToken);

        var remaining = await db.ConversationMembers
            .AnyAsync(m => m.ConversationId == conversationId, cancellationToken);

        if (remaining) return;

        var messageIds = await db.Messages
            .Where(m => m.ConversationId == conversationId)
            .Select(m => m.Id)
            .ToListAsync(cancellationToken);

        if (messageIds.Count > 0)
        {
            await db.MessageReads.Where(r => messageIds.Contains(r.MessageId)).ExecuteDeleteAsync(cancellationToken);
            await db.Attachments.Where(a => messageIds.Contains(a.MessageId)).ExecuteDeleteAsync(cancellationToken);
        }

        await db.Messages.Where(m => m.ConversationId == conversationId).ExecuteDeleteAsync(cancellationToken);
        await db.Conversations.Where(c => c.Id == conversationId).ExecuteDeleteAsync(cancellationToken);
    }
}
