using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace ChatApp.Models;

public class ConversationType
{
    [BsonId]
    public ObjectId Id { get; set; }

    public string Name { get; set; } = null!;
}
