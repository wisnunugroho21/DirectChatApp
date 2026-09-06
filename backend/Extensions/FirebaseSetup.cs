using FirebaseAdmin;
using Google.Apis.Auth.OAuth2;

namespace ChatApp.Extensions;

public static class FirebaseSetup
{
    /// <summary>
    /// Menginisialisasi Firebase Admin SDK bila kredensialnya tersedia.
    /// Kalau tidak ada, aplikasi tetap jalan normal — hanya push notification
    /// yang nonaktif, sementara chat lewat SignalR tidak terpengaruh.
    /// </summary>
    public static IServiceCollection AddFirebaseMessaging(
        this IServiceCollection services,
        IConfiguration configuration,
        string contentRootPath,
        ILogger logger)
    {
        services.Configure<FirebaseSettings>(configuration.GetSection("Firebase"));

        if (FirebaseApp.DefaultInstance is not null) return services;

        var settings = configuration.GetSection("Firebase").Get<FirebaseSettings>() ?? new FirebaseSettings();

        WarnOnSuspiciousWebSettings(settings, logger);

        try
        {
            var credential = ResolveCredential(settings, contentRootPath, logger);

            if (credential is null)
            {
                // ResolveCredential sudah mencatat sebab spesifiknya bila
                // konfigurasinya ada tapi salah.
                logger.LogWarning(
                    "Kredensial Firebase tidak tersedia. Push notification dinonaktifkan; "
                    + "atur Firebase:CredentialsPath, Firebase:CredentialsJson, atau GOOGLE_APPLICATION_CREDENTIALS.");
                return services;
            }

            FirebaseApp.Create(new AppOptions
            {
                Credential = credential,
                ProjectId = settings.Web.ProjectId
            });

            logger.LogInformation("Firebase Admin SDK aktif untuk project {ProjectId}.", settings.Web.ProjectId);

            // Kedua platform dilayani server yang sama tapi disetel terpisah:
            // native hanya butuh service account, sedangkan browser juga
            // butuh konfigurasi Web SDK lengkap beserta VapidKey. Tanpa
            // ringkasan ini, satu sisi bisa mati diam-diam.
            logger.LogInformation(
                "Push siap — perangkat native (Flutter): ya; browser (web push): {Web}.",
                settings.Web.IsConfigured ? "ya" : "tidak, lengkapi Firebase:Web");
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Inisialisasi Firebase gagal. Push notification dinonaktifkan.");
        }

        return services;
    }

    private static GoogleCredential? ResolveCredential(
        FirebaseSettings settings,
        string contentRootPath,
        ILogger logger)
    {
        var json = settings.CredentialsJson?.Trim();

        if (!string.IsNullOrWhiteSpace(json))
        {
            // Kekeliruan yang paling gampang terjadi: CredentialsJson diisi nama
            // file, padahal yang diminta isi filenya. Tanpa pengecekan ini,
            // errornya muncul sebagai kegagalan parsing JSON yang membingungkan.
            if (!json.StartsWith('{'))
            {
                logger.LogError(
                    "Firebase:CredentialsJson harus berisi ISI file service account JSON (diawali '{{'), "
                    + "bukan nama atau path file. Nilai sekarang diawali \"{Preview}\". "
                    + "Untuk menunjuk ke sebuah file, kosongkan CredentialsJson dan pakai Firebase:CredentialsPath.",
                    json[..Math.Min(20, json.Length)]);
                return null;
            }

            return CredentialFactory
                .FromJson<ServiceAccountCredential>(json)
                .ToGoogleCredential();
        }

        var path = settings.CredentialsPath?.Trim();

        if (!string.IsNullOrWhiteSpace(path))
        {
            // Path relatif dihitung dari folder aplikasi, bukan working directory,
            // supaya hasilnya sama baik dijalankan lewat dotnet run, IIS, maupun service.
            var fullPath = Path.IsPathRooted(path) ? path : Path.Combine(contentRootPath, path);

            if (File.Exists(fullPath))
            {
                return CredentialFactory
                    .FromFile<ServiceAccountCredential>(fullPath)
                    .ToGoogleCredential();
            }

            logger.LogError(
                "Firebase:CredentialsPath menunjuk ke \"{Path}\", tetapi file itu tidak ada.",
                fullPath);
            return null;
        }

        // Terakhir, serahkan ke Application Default Credentials. Cara ini juga
        // mencakup GOOGLE_APPLICATION_CREDENTIALS, kredensial gcloud, dan
        // metadata server saat berjalan di infrastruktur Google.
        try
        {
            return GoogleCredential.GetApplicationDefault();
        }
        catch (Exception)
        {
            return null;
        }
    }

    /// <summary>
    /// Konfigurasi web yang keliru tidak menggagalkan startup, tapi bikin
    /// getToken() di browser gagal tanpa petunjuk jelas — jadi diperingatkan di sini.
    /// </summary>
    private static void WarnOnSuspiciousWebSettings(FirebaseSettings settings, ILogger logger)
    {
        var vapidKey = settings.Web.VapidKey?.Trim();
        if (string.IsNullOrWhiteSpace(vapidKey)) return;

        // Kunci VAPID publik adalah titik kurva P-256 dalam base64url: 87-88
        // karakter dan selalu diawali "B".
        if (vapidKey.Length < 80 || !vapidKey.StartsWith('B'))
        {
            logger.LogWarning(
                "Firebase:Web:VapidKey tampak bukan kunci VAPID (\"{Preview}…\", {Length} karakter). "
                + "Kunci yang benar ± 87 karakter diawali \"B\", diambil dari Firebase Console → "
                + "Cloud Messaging → Web Push certificates. Nilai berformat \"G-XXXX\" adalah measurementId "
                + "Google Analytics dan akan membuat pendaftaran notifikasi di browser gagal.",
                vapidKey[..Math.Min(8, vapidKey.Length)],
                vapidKey.Length);
        }
    }
}
