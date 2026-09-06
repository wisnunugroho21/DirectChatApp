using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace ChatApp.Models;

public class Attachment
{
    [BsonId]
    public ObjectId Id { get; set; }

    public ObjectId MessageId { get; set; }

    public string FileName { get; set; } = null!;

    public string Url { get; set; } = null!;

    public long Size { get; set; }

    public string MimeType { get; set; } = null!;

    public int? Width { get; set; }

    public int? Height { get; set; }

    public int? Duration { get; set; }
}
