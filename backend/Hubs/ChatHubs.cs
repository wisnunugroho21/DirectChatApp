using ChatApp.Models;
using ChatApp.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.SignalR;

namespace ChatApp.Hubs;

[Authorize]
public class ChatHubs(
    UserService users,
    ConversationService conversations,
    MessageService messages,
    CallService calls,
    ConnectionTracker connections,
    PushNotificationService push,
    ILogger<ChatHubs> logger) : Hub
{
    // ============================================================
    // PRESENCE
    // ============================================================
    public override async Task OnConnectedAsync()
    {
        var username = Context.UserIdentifier;

        // Status baru berubah pada koneksi pertama dan koneksi terakhir, supaya
        // membuka atau menutup satu tab tidak menggeser status tab lainnya.
        if (!string.IsNullOrWhiteSpace(username) && connections.Add(username, Context.ConnectionId))
        {
            await users.SetPresenceAsync(username, "Online");
            await Clients.Others.SendAsync("PresenceChanged", username, "Online");
        }

        await base.OnConnectedAsync();
    }

    public override async Task OnDisconnectedAsync(Exception? exception)
    {
        var username = Context.UserIdentifier;

        if (!string.IsNullOrWhiteSpace(username) && connections.Remove(username, Context.ConnectionId))
        {
            await users.SetPresenceAsync(username, "Offline");
            await Clients.Others.SendAsync("PresenceChanged", username, "Offline");
        }

        await base.OnDisconnectedAsync(exception);
    }

    // ============================================================
    // CHAT
    // ============================================================
    /// <summary>
    /// Menyimpan pesan ke MongoDB lalu meneruskannya ke penerima. Nilai baliknya
    /// dipakai pengirim untuk merender bubble dengan id dan waktu dari server.
    /// </summary>
    public async Task<MessageDto> SendMessage(string userId, string message)
    {
        var senderName = Context.UserIdentifier ?? Context.User?.Identity?.Name;
        if (string.IsNullOrWhiteSpace(senderName) || string.IsNullOrWhiteSpace(userId) || string.IsNullOrWhiteSpace(message))
            throw new HubException("Pengirim, penerima, dan pesan wajib diisi.");

        var (sender, receiver) = await ResolvePairAsync(senderName, userId);

        var conversation = await conversations.GetOrCreateDirectAsync(sender.Id, receiver.Id);

        var saved = await messages.SaveAsync(
            conversation.Id,
            sender.Id,
            message.Trim());

        await Clients.User(receiver.Username)
            .SendAsync("ReceiveMessage", messages.ToDto(saved, sender.Username, receiver.Id));

        // SignalR menangani perangkat yang koneksinya sedang hidup; sisanya
        // dikabari lewat Firebase Cloud Messaging. Pengecualiannya per perangkat,
        // bukan per pengguna, supaya ponsel yang aplikasinya tertutup tetap
        // berbunyi walau browser di komputer sedang terbuka.
        await push.SendChatMessageAsync(
            receiver,
            sender,
            saved,
            connections.GetActiveDeviceTokens(receiver.Username));

        return messages.ToDto(saved, sender.Username, sender.Id);
    }

    /// <summary>
    /// Menautkan token FCM perangkat ini ke koneksi yang sedang dipakai.
    ///
    /// Klien memanggilnya setiap kali koneksinya terbentuk, karena connectionId
    /// berganti setiap reconnect. Selama belum ditautkan, perangkat ini masih
    /// dianggap tidak terhubung dan bisa ikut menerima notifikasi.
    /// </summary>
    public Task UnbindDevice()
    {
        var username = Context.UserIdentifier;
        if (!string.IsNullOrWhiteSpace(username))
            connections.BindDevice(username, Context.ConnectionId, "");
        return Task.CompletedTask;
    }

    public Task BindDevice(string deviceToken)
    {
        var username = Context.UserIdentifier;

        if (!string.IsNullOrWhiteSpace(username) && !string.IsNullOrWhiteSpace(deviceToken))
        {
            connections.BindDevice(username, Context.ConnectionId, deviceToken.Trim());
        }

        return Task.CompletedTask;
    }

    /// <summary>Menandai percakapan dengan lawan bicara tertentu sudah dibaca.</summary>
    public async Task MarkRead(string userId)
    {
        var readerName = Context.UserIdentifier;
        if (string.IsNullOrWhiteSpace(readerName) || string.IsNullOrWhiteSpace(userId)) return;

        var (reader, peer) = await ResolvePairAsync(readerName, userId);

        var conversation = await conversations.GetOrCreateDirectAsync(reader.Id, peer.Id);
        await messages.MarkReadAsync(conversation.Id, reader.Id);

        await Clients.User(peer.Username).SendAsync("MessagesRead", reader.Username);
    }

    // ============================================================
    // CALL SIGNALING
    // ============================================================
    public async Task CallUser(string targetUserId, string callType = "Audio")
    {
        var caller = Context.UserIdentifier;
        if (string.IsNullOrWhiteSpace(caller) || string.IsNullOrWhiteSpace(targetUserId))
            throw new HubException("Pemanggil dan tujuan panggilan wajib diisi.");

        // Jalur cepat lebih dulu: penerima yang sedang membuka aplikasi harus
        // langsung berdering, tanpa menunggu database.
        await ResolvePairAsync(caller, targetUserId);
        callType = callType == "Video" ? "Video" : "Audio";
        await Clients.User(targetUserId).SendAsync("IncomingCall", caller, callType);

        try
        {
            var callerUser = await users.GetByUsernameAsync(caller);
            var receiverUser = await users.GetByUsernameAsync(targetUserId);

            if (callerUser is null || receiverUser is null || callerUser.Id == receiverUser.Id) return;

            var call = await calls.StartAsync(callerUser.Id, receiverUser.Id, callType);

            // Perangkat yang tidak sedang terhubung tidak menerima sinyal
            // SignalR-nya, jadi deringnya dikirim lewat FCM.
            await push.SendIncomingCallAsync(
                receiverUser,
                callerUser,
                call,
                connections.GetActiveDeviceTokens(receiverUser.Username));
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Gagal mencatat/mengabarkan panggilan {Caller} -> {Receiver}.", caller, targetUserId);
        }
    }

    public async Task AcceptCall(string callerUser)
    {
        var receiver = Context.UserIdentifier;
        if (string.IsNullOrWhiteSpace(receiver) || string.IsNullOrWhiteSpace(callerUser)) return;

        await RecordCallAsync(callerUser, receiver, async (a, b) =>
            await calls.MarkAnsweredAsync(a.Id, b.Id));

        await Clients.User(callerUser).SendAsync("CallAccepted", receiver);
    }

    public async Task RejectCall(string targetUser)
    {
        var receiver = Context.UserIdentifier;
        if (string.IsNullOrWhiteSpace(receiver) || string.IsNullOrWhiteSpace(targetUser)) return;

        await RecordCallAsync(targetUser, receiver, async (a, b) =>
            await calls.MarkRejectedAsync(a.Id, b.Id));

        await Clients.User(targetUser).SendAsync("CallRejected", receiver);
    }

    public async Task EndCall(string targetUser)
    {
        var caller = Context.UserIdentifier;
        if (string.IsNullOrWhiteSpace(caller) || string.IsNullOrWhiteSpace(targetUser)) return;

        await Clients.User(targetUser).SendAsync("CallEnded", caller);

        try
        {
            var callerUser = await users.GetByUsernameAsync(caller);
            var targetUserRecord = await users.GetByUsernameAsync(targetUser);

            if (callerUser is null || targetUserRecord is null || callerUser.Id == targetUserRecord.Id) return;

            var ended = await calls.MarkEndedAsync(callerUser.Id, targetUserRecord.Id);

            // Perangkat yang berdering lewat notifikasi tidak tahu kalau penelepon
            // sudah membatalkan; deringnya harus dihentikan.
            if (ended is not null)
            {
                await push.SendCallCancelledAsync(
                    targetUserRecord,
                    ended,
                    connections.GetActiveDeviceTokens(targetUserRecord.Username));
            }
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Gagal menutup panggilan {Caller} -> {Receiver}.", caller, targetUser);
        }
    }

    public async Task SendOffer(string targetUserId, string offer)
    {
        await Clients.User(targetUserId)
            .SendAsync("ReceiveOffer", Context.UserIdentifier, offer);
    }

    public async Task SendAnswer(string targetUserId, string answer)
    {
        await Clients.User(targetUserId)
            .SendAsync("ReceiveAnswer", Context.UserIdentifier, answer);
    }

    public async Task SendIceCandidate(string targetUserId, string candidate)
    {
        await Clients.User(targetUserId)
            .SendAsync("ReceiveIceCandidate", candidate, Context.UserIdentifier);
    }

    // ============================================================
    // HELPERS
    // ============================================================
    private async Task<(User Sender, User Receiver)> ResolvePairAsync(string senderName, string receiverName)
    {
        var sender = await users.GetByUsernameAsync(senderName)
            ?? throw new HubException("Akun pengirim tidak ditemukan.");

        var receiver = await users.GetByUsernameAsync(receiverName)
            ?? throw new HubException($"Pengguna '{receiverName}' tidak ditemukan.");

        if (sender.Id == receiver.Id)
            throw new HubException("Tidak bisa mengirim pesan ke diri sendiri.");

        return (sender, receiver);
    }

    /// <summary>
    /// Pencatatan riwayat panggilan tidak boleh menggagalkan signaling — kalau
    /// database bermasalah, panggilannya tetap harus bisa jalan.
    /// </summary>
    private async Task RecordCallAsync(string callerName, string receiverName, Func<User, User, Task> record)
    {
        try
        {
            var caller = await users.GetByUsernameAsync(callerName);
            var receiver = await users.GetByUsernameAsync(receiverName);

            if (caller is null || receiver is null || caller.Id == receiver.Id) return;

            await record(caller, receiver);
        }
        catch (Exception ex)
        {
            logger.LogWarning(ex, "Gagal mencatat riwayat panggilan {Caller} -> {Receiver}.", callerName, receiverName);
        }
    }
}


