using Microsoft.AspNetCore.SignalR;

namespace ChatApp.Hubs;

public sealed class NameUserIdProvider : IUserIdProvider
{
    public string? GetUserId(HubConnectionContext connection)
        => connection.User?.Identity?.Name;
}
