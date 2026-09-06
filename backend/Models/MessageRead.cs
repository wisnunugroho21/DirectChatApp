using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace ChatApp.Models;

public class MessageRead
{
    [BsonId]
    public ObjectId Id { get; set; }

    public ObjectId MessageId { get; set; }

    public ObjectId UserId { get; set; }

    public DateTime ReadAt { get; set; } = DateTime.UtcNow;
}
