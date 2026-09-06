using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace ChatApp.Models;

public class ConversationMember
{
    [BsonId]
    public ObjectId Id { get; set; }

    public ObjectId ConversationId { get; set; }

    public ObjectId UserId { get; set; }

    public string Role { get; set; } = "Member";

    public DateTime JoinDate { get; set; } = DateTime.UtcNow;

    public ObjectId? LastReadMessageId { get; set; }

    // Disimpan berdampingan dengan LastReadMessageId supaya hitung unread cukup
    // satu query rentang tanggal, tanpa perlu membaca dokumen pesannya dulu.
    public DateTime? LastReadAt { get; set; }
}
