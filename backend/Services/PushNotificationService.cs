using ChatApp.Models;
using FirebaseAdmin;
using FirebaseAdmin.Messaging;

namespace ChatApp.Services;

/// <summary>
/// Mengirim notifikasi Firebase Cloud Messaging ke perangkat milik penerima.
///
/// Bentuk payload dibedakan per platform karena cara menampilkannya berbeda:
///
/// - Web (service worker): data-only, tanpa properti Notification. Pesan yang
///   membawa notification akan ditampilkan otomatis oleh SDK sekaligus
///   membangunkan service worker, sehingga notifikasinya bisa dobel.
///
/// - Native (Flutter WebView di Android/iOS): notification + data. Saat aplikasi
///   di background, system tray yang menampilkannya tanpa perlu kode tambahan;
///   bagian data tetap terbawa untuk menentukan percakapan mana yang dibuka
///   ketika notifikasinya disentuh.
/// </summary>
public sealed class PushNotificationService(
    DeviceService devices,
    ILogger<PushNotificationService> logger)
{
    private const int PreviewLength = 120;

    /// <summary>Harus sama dengan channel yang dibuat aplikasi Flutter.</summary>
    public const string AndroidChannelId = "chat_messages";

    /// <summary>
    /// Umur sinyal panggilan. Dibuat sedikit lebih panjang dari durasi dering di
    /// aplikasi supaya pembatalannya masih sempat terkirim.
    /// </summary>
    public static readonly TimeSpan CallSignalTimeToLive = TimeSpan.FromSeconds(60);

    public static bool IsEnabled => FirebaseApp.DefaultInstance is not null;

    public async Task SendChatMessageAsync(
        User recipient,
        User sender,
        Models.Message message,
        IReadOnlySet<string>? excludeTokens = null,
        CancellationToken cancellationToken = default)
    {
        if (!IsEnabled) return;

        var registered = await GetTargetDevicesAsync(recipient, excludeTokens, cancellationToken);
        if (registered.Count == 0) return;

        var senderLabel = string.IsNullOrWhiteSpace(sender.FullName) ? sender.Username : sender.FullName;
        var body = message.MessageText ?? string.Empty;
        if (body.Length > PreviewLength) body = body[..PreviewLength] + "…";

        var data = new Dictionary<string, string>
        {
            ["type"] = "chat",
            ["title"] = senderLabel,
            ["body"] = body,
            ["senderUsername"] = sender.Username,
            ["conversationId"] = message.ConversationId.ToString(),
            ["messageId"] = message.Id.ToString(),
            ["sentAt"] = message.CreatedAt.ToString("O")
        };

        // Perangkat yang mendaftar tanpa platform dianggap web, sesuai perilaku lama.
        var webTokens = registered
            .Where(d => !IsNativePlatform(d.Platform))
            .Select(d => d.Token)
            .Distinct()
            .ToList();

        var nativeTokens = registered
            .Where(d => IsNativePlatform(d.Platform))
            .Select(d => d.Token)
            .Distinct()
            .ToList();

        await SendAsync(webTokens, BuildWebPayload(webTokens, data), recipient, cancellationToken);

        await SendAsync(
            nativeTokens,
            BuildNativePayload(nativeTokens, data, senderLabel, body, message),
            recipient,
            cancellationToken);
    }

    /// <summary>
    /// Memberitahukan panggilan masuk ke perangkat penerima yang sedang tidak
    /// terhubung.
    ///
    /// Berbeda dengan pesan chat, payload ini data-only untuk SEMUA platform.
    /// Notifikasi bawaan system tray tidak bisa menampilkan layar panggilan
    /// penuh, jadi aplikasinya harus dibangunkan agar bisa memunculkan UI
    /// panggilan sendiri.
    /// </summary>
    public async Task SendIncomingCallAsync(
        User recipient,
        User caller,
        CallHistory call,
        IReadOnlySet<string>? excludeTokens = null,
        CancellationToken cancellationToken = default)
    {
        var callerLabel = string.IsNullOrWhiteSpace(caller.FullName) ? caller.Username : caller.FullName;

        await SendCallSignalAsync(
            recipient,
            new Dictionary<string, string>
            {
                ["type"] = "call",
                ["callId"] = call.Id.ToString(),
                ["isGroup"] = (call.GroupCallId != null).ToString().ToLowerInvariant(),
                ["groupCallId"] = call.GroupCallId ?? "",
                ["conversationId"] = call.ConversationId ?? "",
                ["conversationName"] = call.ConversationName ?? "",
                ["memberCount"] = call.MemberCount.ToString(),
                ["callerUsername"] = caller.Username,
                ["callerName"] = callerLabel,
                ["callType"] = call.CallType,
                ["startedAt"] = call.StartDate.ToString("O"),

                // Dipakai service worker di web, yang tidak punya UI panggilan.
                ["title"] = callerLabel,
                ["body"] = string.Equals(call.CallType, "Video", StringComparison.OrdinalIgnoreCase)
                    ? "Panggilan video masuk"
                    : "Panggilan suara masuk",
                ["senderUsername"] = caller.Username
            },
            call,
            excludeTokens,
            cancellationToken);
    }

    /// <summary>
    /// Membatalkan dering di perangkat penerima ketika panggilannya sudah tidak
    /// berlaku. Tanpa ini, ponsel terus berdering sampai kehabisan waktu.
    /// </summary>
    public async Task SendCallCancelledAsync(
        User recipient,
        CallHistory call,
        IReadOnlySet<string>? excludeTokens = null,
        CancellationToken cancellationToken = default)
    {
        await SendCallSignalAsync(
            recipient,
            new Dictionary<string, string>
            {
                ["type"] = "call-cancelled",
                ["callId"] = call.Id.ToString()
            },
            call,
            excludeTokens,
            cancellationToken);
    }

    private async Task SendCallSignalAsync(
        User recipient,
        Dictionary<string, string> data,
        CallHistory call,
        IReadOnlySet<string>? excludeTokens,
        CancellationToken cancellationToken)
    {
        if (!IsEnabled) return;

        var tokens = (await GetTargetDevicesAsync(recipient, excludeTokens, cancellationToken))
            .Select(d => d.Token)
            .Distinct()
            .ToList();

        if (tokens.Count == 0) return;

#pragma warning disable CS0618 // Type or member is obsolete
        var payload = new MulticastMessage
        {
            Tokens = tokens,
            Data = data,
            // Native clients can open the Flutter call screen from an OS notification.
            Notification = data.GetValueOrDefault("type") == "call"
                ? new Notification { Title = data.GetValueOrDefault("title"), Body = data.GetValueOrDefault("body") }
                : null,
            Android = new AndroidConfig
            {
                Priority = Priority.High,

                // Panggilan hanya relevan selama masih berdering. Lewat dari itu,
                // lebih baik tidak sampai sama sekali daripada berdering untuk
                // panggilan yang sudah lama berakhir.
                TimeToLive = CallSignalTimeToLive,

                // Pembatalan menggantikan dering untuk panggilan yang sama.
                CollapseKey = call.Id.ToString()
            },
            Webpush = new WebpushConfig
            {
                Headers = new Dictionary<string, string>
                {
                    ["Urgency"] = "high",
                    ["TTL"] = ((int)CallSignalTimeToLive.TotalSeconds).ToString()
                }
            }
        };
#pragma warning restore CS0618

        await SendAsync(tokens, payload, recipient, cancellationToken);
    }

    /// <summary>
    /// Perangkat yang perlu dikirimi notifikasi: seluruh perangkat terdaftar
    /// milik penerima, dikurangi yang koneksi SignalR-nya sedang hidup.
    ///
    /// Inilah yang membuat ponsel tetap berbunyi walau browser sedang terbuka:
    /// yang dikecualikan hanya perangkat itu sendiri, bukan seluruh perangkat
    /// milik penggunanya.
    /// </summary>
    private async Task<List<UserDevice>> GetTargetDevicesAsync(
        User recipient,
        IReadOnlySet<string>? excludeTokens,
        CancellationToken cancellationToken)
    {
        var registered = await devices.GetForUserAsync(recipient.Id, cancellationToken);

        if (excludeTokens is null || excludeTokens.Count == 0) return registered;

        return registered.Where(d => !excludeTokens.Contains(d.Token)).ToList();
    }

    private static bool IsNativePlatform(string? platform) =>
        string.Equals(platform, "android", StringComparison.OrdinalIgnoreCase)
        || string.Equals(platform, "ios", StringComparison.OrdinalIgnoreCase);

    // MulticastMessage.Tokens ditandai usang demi properti Fids yang baru, tapi
    // keduanya bukan hal yang sama: Fids terkirim sebagai field "fid", sedangkan
    // registration token (dari getToken() maupun FirebaseMessaging Flutter) harus
    // masuk ke field "token" — yaitu properti Tokens ini.
#pragma warning disable CS0618 // Type or member is obsolete

    private static MulticastMessage BuildWebPayload(
        List<string> tokens,
        Dictionary<string, string> data) => new()
        {
            Tokens = tokens,
            Data = data,
            Webpush = new WebpushConfig
            {
                Headers = new Dictionary<string, string>
                {
                    // Pesan chat tidak berguna lagi kalau baru sampai berjam-jam kemudian.
                    ["Urgency"] = "high",
                    ["TTL"] = "1800"
                }

                // Sengaja tanpa FcmOptions.Link: field itu hanya dipakai kalau SDK
                // yang menampilkan notifikasi (payload ini data-only), nilainya wajib
                // URL https absolut sehingga selalu gagal saat dev di http://localhost,
                // dan perpindahan halamannya sudah ditangani handler notificationclick
                // di firebase-messaging-sw.js.
            }
        };

    private static MulticastMessage BuildNativePayload(
        List<string> tokens,
        Dictionary<string, string> data,
        string title,
        string body,
        Models.Message message) => new()
        {
            Tokens = tokens,
            Data = data,
            Notification = new Notification
            {
                Title = title,
                Body = body
            },
            Android = new AndroidConfig
            {
                // Prioritas tinggi supaya tetap sampai saat perangkat sedang doze.
                Priority = Priority.High,
                TimeToLive = TimeSpan.FromMinutes(30),

                // Notifikasi dari percakapan yang sama saling menimpa, bukan menumpuk.
                CollapseKey = message.ConversationId.ToString(),
                Notification = new AndroidNotification
                {
                    ChannelId = AndroidChannelId,
                    Tag = message.ConversationId.ToString(),
                    Sound = "default"
                }
            },
            Apns = new ApnsConfig
            {
                Aps = new Aps
                {
                    Sound = "default",
                    ThreadId = message.ConversationId.ToString()
                }
            }
        };

#pragma warning restore CS0618

    private async Task SendAsync(
        List<string> tokens,
        MulticastMessage payload,
        User recipient,
        CancellationToken cancellationToken)
    {
        if (tokens.Count == 0) return;

        try
        {
            var response = await FirebaseMessaging.DefaultInstance.SendEachForMulticastAsync(
                payload, cancellationToken);

            if (response.FailureCount > 0)
            {
                await PruneInvalidTokensAsync(tokens, response, cancellationToken);
            }

            logger.LogDebug(
                "Push ke {Recipient}: {Success} berhasil, {Failure} gagal.",
                recipient.Username, response.SuccessCount, response.FailureCount);
        }
        catch (Exception ex)
        {
            // Notifikasi bersifat pelengkap — pesannya sendiri sudah tersimpan dan
            // sudah dikirim lewat SignalR, jadi kegagalan di sini tidak boleh
            // menggagalkan pengiriman pesan. Sengaja menangkap Exception, bukan
            // hanya FirebaseMessagingException: kredensial yang tidak valid gagal
            // saat penukaran token OAuth, jauh sebelum lapisan FCM.
            logger.LogWarning(ex, "Gagal mengirim push ke {Recipient}.", recipient.Username);
        }
    }

    /// <summary>Token yang sudah tidak valid dihapus supaya tidak terus dicoba pada pesan berikutnya.</summary>
    private async Task PruneInvalidTokensAsync(
        List<string> tokens,
        BatchResponse response,
        CancellationToken cancellationToken)
    {
        var stale = new List<string>();

        for (var i = 0; i < response.Responses.Count && i < tokens.Count; i++)
        {
            var result = response.Responses[i];
            if (result.IsSuccess) continue;

            var code = result.Exception?.MessagingErrorCode;
            if (code is MessagingErrorCode.Unregistered or MessagingErrorCode.InvalidArgument)
            {
                stale.Add(tokens[i]);
            }
        }

        if (stale.Count == 0) return;

        await devices.RemoveManyAsync(stale, cancellationToken);
        logger.LogInformation("{Count} token FCM kedaluwarsa dihapus.", stale.Count);
    }
}

