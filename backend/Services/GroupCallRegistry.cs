using ChatApp.Models;
using MongoDB.Bson;

namespace ChatApp.Services;

// Active WebRTC rooms live with the signaling server, like ConnectionTracker.
// Call history remains in MongoDB. Deploy a single signaling instance.
public sealed class GroupCallRegistry
{
    public SemaphoreSlim Gate { get; } = new(1, 1);
    public Dictionary<string, GroupCallRoom> Rooms { get; } = [];
}

public sealed class GroupCallRoom
{
    public string Id { get; } = ObjectId.GenerateNewId().ToString();
    public required string ConversationId { get; init; }
    public required string Name { get; init; }
    public required string Host { get; init; }
    public required string CallType { get; init; }
    public required List<User> Members { get; init; }
    public HashSet<string> Joined { get; } = [];
    public HashSet<string> Declined { get; } = [];
    public Dictionary<string, ObjectId> History { get; } = [];
    public DateTime StartedAt { get; } = DateTime.UtcNow;
}
