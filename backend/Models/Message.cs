using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace ChatApp.Models;

public class Message
{
    [BsonId]
    public ObjectId Id { get; set; }

    public ObjectId ConversationId { get; set; }

    public ObjectId SenderId { get; set; }

    public ObjectId MessageTypeId { get; set; }

    public string? MessageText { get; set; }

    public ObjectId? ReplyToMessageId { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime? EditedAt { get; set; }

    public DateTime? DeletedAt { get; set; }
}
