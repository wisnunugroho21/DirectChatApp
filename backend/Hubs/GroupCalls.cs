using ChatApp.Services;
using Microsoft.AspNetCore.SignalR;
using MongoDB.Bson;

namespace ChatApp.Hubs;

public partial class ChatHubs
{
    public async Task<object> StartGroupCall(string conversationId, string callType = "Audio")
    {
        var me = await users.GetByUsernameAsync(Context.UserIdentifier ?? "") ?? throw new HubException("Sign in first.");
        if (!ObjectId.TryParse(conversationId, out var id) || !await conversations.IsMemberAsync(id, me.Id))
            throw new HubException("Conversation is not available.");
        var conversation = await conversations.GetAsync(id);
        var members = await conversations.MembersAsync(id);
        if (conversation is null || conversation.DirectKey != null || members.Count < 2 || members.Count > 8)
            throw new HubException("Group calls support 2 to 8 current members.");
        await groupCalls.Gate.WaitAsync();
        try {
            if (groupCalls.Rooms.Values.Any(r => r.ConversationId == conversationId || r.Joined.Contains(me.Username)))
                throw new HubException("A group call is already active.");
            var room = new GroupCallRoom { ConversationId = conversationId, Name = conversation.Name ?? "Group call",
                Host = me.Username, CallType = callType == "Video" ? "Video" : "Audio", Members = members };
            room.Joined.Add(me.Username);
            groupCalls.Rooms.Add(room.Id, room);
            try {
                foreach (var member in members.Where(u => u.Id != me.Id)) {
                    var history = await calls.StartAsync(me.Id, member.Id, room.CallType,
                        groupCallId: room.Id, conversationId: conversationId, conversationName: room.Name, memberCount: members.Count);
                    room.History[member.Username] = history.Id;
                    await Clients.User(member.Username).SendAsync("IncomingGroupCall", me.Username, me.FullName,
                        room.Id, conversationId, room.Name, room.CallType, members.Count);
                    await push.SendIncomingCallAsync(member, me, history, connections.GetActiveDeviceTokens(member.Username));
                }
                await Clients.Caller.SendAsync("GroupCallReady", room.Id, conversationId, room.Name,
                    room.CallType, members.Count, me.Username);
                return new { groupCallId = room.Id, hostUsername = me.Username, memberCount = members.Count };
            } catch { await CloseGroupRoom(room, me.Username); throw; }
        } finally { groupCalls.Gate.Release(); }
    }

    private async Task<GroupCallRoom> AuthorizedRoom(string id, bool joined = false)
    {
        var username = Context.UserIdentifier ?? "";
        if (!groupCalls.Rooms.TryGetValue(id, out var room) ||
            !room.Members.Any(u => u.Username == username) ||
            (joined && !room.Joined.Contains(username))) throw new HubException("Call is no longer available.");
        var me = room.Members.First(u => u.Username == username);
        if (!await conversations.IsMemberAsync(ObjectId.Parse(room.ConversationId), me.Id))
            throw new HubException("You are no longer a member of this group.");
        return room;
    }

    public async Task<bool> AcceptGroupCall(string id)
    {
        await groupCalls.Gate.WaitAsync();
        try {
            var room = await AuthorizedRoom(id);
            var me = Context.UserIdentifier!;
            if (room.Declined.Contains(me) || DateTime.UtcNow - room.StartedAt > CallService.RingingWindow)
                throw new HubException("This invitation has expired.");
            if (room.Joined.Contains(me)) return true;
            if (groupCalls.Rooms.Values.Any(r => r.Id != id && r.Joined.Contains(me)))
                throw new HubException("You are already in another group call.");
            var existing = room.Joined.ToArray();
            room.Joined.Add(me);
            if (room.History.TryGetValue(me, out var history)) await calls.UpdateGroupHistoryAsync(history, true);
            await Clients.User(me).SendAsync("GroupCallHandled", id, Context.ConnectionId);
            await Clients.Caller.SendAsync("GroupCallAccepted", id, existing, room.ConversationId,
                room.Name, room.CallType, room.Members.Count);
            await Clients.Users(existing).SendAsync("GroupParticipantJoined", id, me);
            return true;
        } finally { groupCalls.Gate.Release(); }
    }

    public Task RejectGroupCall(string id) => ExitGroupCall(id, true);
    public Task LeaveGroupCall(string id) => ExitGroupCall(id, false);
    private async Task ExitGroupCall(string id, bool rejected)
    {
        await groupCalls.Gate.WaitAsync();
        try {
            if (!groupCalls.Rooms.ContainsKey(id)) return;
            var room = groupCalls.Rooms[id];
            if (!room.Members.Any(u => u.Username == Context.UserIdentifier)) throw new HubException("Call is not available.");
            await RemoveGroupMember(room, Context.UserIdentifier!, rejected);
        } finally { groupCalls.Gate.Release(); }
    }
    private async Task RemoveGroupMember(GroupCallRoom room, string username, bool rejected)
    {
        if (username == room.Host) { await CloseGroupRoom(room, username); return; }
        room.Joined.Remove(username);
        room.Declined.Add(username);
        if (room.History.TryGetValue(username, out var history)) await calls.UpdateGroupHistoryAsync(history, false, rejected);
        await Clients.Users(room.Joined.ToArray()).SendAsync(rejected ? "GroupParticipantDeclined" : "GroupParticipantLeft", room.Id, username);
        // Dismiss any invitation still visible on this user's other devices.
        await Clients.User(username).SendAsync("GroupCallEnded", room.Id, username);
    }
    private async Task CloseGroupRoom(GroupCallRoom room, string username)
    {
        groupCalls.Rooms.Remove(room.Id);
        await Clients.Users(room.Members.Select(u => u.Username).ToArray()).SendAsync("GroupCallEnded", room.Id, username);
        foreach (var (member, id) in room.History) {
            await calls.UpdateGroupHistoryAsync(id, false);
            var history = await calls.GetByIdAsync(id);
            if (history != null) await push.SendCallCancelledAsync(room.Members.First(u => u.Username == member), history,
                connections.GetActiveDeviceTokens(member));
        }
    }
    private async Task LeaveDisconnectedGroups(string username)
    {
        await groupCalls.Gate.WaitAsync();
        try {
            foreach (var room in groupCalls.Rooms.Values.Where(r => r.Joined.Contains(username)).ToList())
                await RemoveGroupMember(room, username, false);
        } finally { groupCalls.Gate.Release(); }
    }
    public Task SendGroupOffer(string id, string target, string offer) => RelayGroup(id, target, "ReceiveGroupOffer", offer);
    public Task SendGroupAnswer(string id, string target, string answer) => RelayGroup(id, target, "ReceiveGroupAnswer", answer);
    public Task SendGroupIceCandidate(string id, string target, string candidate) => RelayGroup(id, target, "ReceiveGroupIceCandidate", candidate);
    private async Task RelayGroup(string id, string target, string eventName, string payload)
    {
        if (payload.Length > 131072) throw new HubException("Signal too large.");
        await groupCalls.Gate.WaitAsync();
        try {
            var room = await AuthorizedRoom(id, true);
            var recipient = room.Members.FirstOrDefault(u => u.Username == target);
            if (!room.Joined.Contains(target) || recipient == null ||
                !await conversations.IsMemberAsync(ObjectId.Parse(room.ConversationId), recipient.Id))
                throw new HubException("Participant is not in this call.");
            await Clients.User(target).SendAsync(eventName, Context.UserIdentifier, id, payload);
        } finally { groupCalls.Gate.Release(); }
    }
    public async Task SendGroupCameraState(string id, bool enabled)
    {
        await groupCalls.Gate.WaitAsync();
        try {
            var room = await AuthorizedRoom(id, true);
            await Clients.Users(room.Joined.ToArray()).SendAsync("GroupCameraStateChanged", id, Context.UserIdentifier, enabled);
        } finally { groupCalls.Gate.Release(); }
    }
}
