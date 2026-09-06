using ChatApp.Data;
using ChatApp.Models;
using Microsoft.EntityFrameworkCore;
using MongoDB.Bson;

namespace ChatApp.Services;

public sealed class MessageService(ChatDbContext db, ChatTypeCatalog types)
{
    public const int DefaultHistoryLimit = 50;
    public const int MaxHistoryLimit = 200;

    public async Task<Message> SaveAsync(
        ObjectId conversationId,
        ObjectId senderId,
        string text,
        string typeName = ChatTypeCatalog.TextMessage,
        ObjectId? replyToMessageId = null,
        CancellationToken cancellationToken = default)
    {
        var message = new Message
        {
            Id = ObjectId.GenerateNewId(),
            ConversationId = conversationId,
            SenderId = senderId,
            MessageTypeId = types.MessageTypeId(typeName),
            MessageText = text,
            ReplyToMessageId = replyToMessageId,
            CreatedAt = DateTime.UtcNow
        };

        db.Messages.Add(message);

        var conversation = await db.Conversations
            .FirstOrDefaultAsync(c => c.Id == conversationId, cancellationToken);

        if (conversation is not null) conversation.UpdatedAt = message.CreatedAt;

        await db.SaveChangesAsync(cancellationToken);

        return message;
    }

    /// <summary>
    /// Riwayat pesan terbaru lebih dulu di database, dikembalikan urut lama ke baru
    /// supaya bisa langsung dirender. <paramref name="before"/> untuk memuat
    /// halaman yang lebih lama.
    /// </summary>
    public async Task<List<Message>> GetHistoryAsync(
        ObjectId conversationId,
        int limit = DefaultHistoryLimit,
        DateTime? before = null,
        CancellationToken cancellationToken = default)
    {
        limit = Math.Clamp(limit, 1, MaxHistoryLimit);

        var query = db.Messages
            .Where(m => m.ConversationId == conversationId && m.DeletedAt == null);

        if (before.HasValue)
        {
            var cutoff = before.Value;
            query = query.Where(m => m.CreatedAt < cutoff);
        }

        var page = await query
            .OrderByDescending(m => m.CreatedAt)
            .Take(limit)
            .ToListAsync(cancellationToken);

        page.Reverse();
        return page;
    }

    public MessageDto ToDto(
        Message message,
        string senderUsername,
        ObjectId viewerId,
        Attachment? attachment = null) =>
        new(message.Id.ToString(),
            message.ConversationId.ToString(),
            senderUsername,
            message.MessageText,
            types.MessageTypeName(message.MessageTypeId),
            message.CreatedAt,
            message.SenderId == viewerId,
            attachment is null
                ? null
                : new AttachmentDto(
                    attachment.Id.ToString(),
                    attachment.FileName,
                    attachment.MimeType,
                    attachment.Size,
                    $"/api/attachments/{attachment.Id}"));

    /// <summary>
    /// Menandai seluruh pesan lawan bicara sebagai sudah dibaca: menggeser penanda
    /// di keanggotaan percakapan sekaligus mencatat tanda terima per pesan.
    /// </summary>
    public async Task MarkReadAsync(
        ObjectId conversationId,
        ObjectId userId,
        CancellationToken cancellationToken = default)
    {
        var membership = await db.ConversationMembers
            .FirstOrDefaultAsync(m => m.ConversationId == conversationId && m.UserId == userId, cancellationToken);

        if (membership is null) return;

        var since = membership.LastReadAt ?? DateTime.UnixEpoch;

        var unread = await db.Messages
            .Where(m => m.ConversationId == conversationId
                && m.SenderId != userId
                && m.CreatedAt > since
                && m.DeletedAt == null)
            .OrderBy(m => m.CreatedAt)
            .ToListAsync(cancellationToken);

        if (unread.Count == 0) return;

        var unreadIds = unread.Select(m => m.Id).ToList();

        // Tanda terima yang sudah ada dilewati; sisanya disisipkan sekaligus.
        // Kalau permintaan lain menandai baca bersamaan, index unik
        // (MessageId, UserId) yang menolaknya dan penyimpanan ini dianggap
        // selesai — hasil akhirnya sama.
        var alreadyRead = await db.MessageReads
            .Where(r => r.UserId == userId && unreadIds.Contains(r.MessageId))
            .Select(r => r.MessageId)
            .ToListAsync(cancellationToken);

        var missing = unread.Where(m => !alreadyRead.Contains(m.Id)).ToList();

        if (missing.Count > 0)
        {
            var now = DateTime.UtcNow;

            db.MessageReads.AddRange(missing.Select(message => new MessageRead
            {
                Id = ObjectId.GenerateNewId(),
                MessageId = message.Id,
                UserId = userId,
                ReadAt = now
            }));

            await db.TrySaveChangesAsync(cancellationToken);
        }

        // Disimpan terpisah dari tanda terima: tanpa transaksi, kegagalan di atas
        // tidak boleh ikut membatalkan penanda baca ini.
        var last = unread[^1];
        membership.LastReadMessageId = last.Id;
        membership.LastReadAt = last.CreatedAt;

        await db.SaveChangesAsync(cancellationToken);
    }
}
