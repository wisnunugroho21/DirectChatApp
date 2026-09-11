using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace ChatApp.Models;

public class CallHistory
{
    [BsonId]
    public ObjectId Id { get; set; }

    public ObjectId CallerId { get; set; }

    public ObjectId ReceiverId { get; set; }

    public string? GroupCallId { get; set; }
    public string? ConversationId { get; set; }
    public string? ConversationName { get; set; }
    public int MemberCount { get; set; } = 2;

    public string CallType { get; set; } = "Audio";

    public DateTime StartDate { get; set; }

    public DateTime? AnsweredAt { get; set; }

    public DateTime? EndDate { get; set; }

    public int? Duration { get; set; }

    public string Status { get; set; } = "Missed";
}
