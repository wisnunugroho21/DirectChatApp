namespace ChatApp.Extensions;

public class FirebaseSettings
{
    /// <summary>
    /// Path ke file service account JSON. Jangan pernah di-commit — arahkan
    /// lewat user secrets atau environment variable saat deploy.
    /// </summary>
    public string? CredentialsPath { get; set; }

    /// <summary>Isi service account JSON secara langsung, untuk deployment yang hanya menyediakan secret berupa string.</summary>
    public string? CredentialsJson { get; set; }

    /// <summary>Konfigurasi Firebase Web SDK — dipakai browser, bukan rahasia.</summary>
    public FirebaseWebSettings Web { get; set; } = new();
}

public class FirebaseWebSettings
{
    public string? ApiKey { get; set; }
    public string? AuthDomain { get; set; }
    public string? ProjectId { get; set; }
    public string? StorageBucket { get; set; }
    public string? MessagingSenderId { get; set; }
    public string? AppId { get; set; }

    /// <summary>Kunci publik VAPID dari Firebase Console → Cloud Messaging → Web Push certificates.</summary>
    public string? VapidKey { get; set; }

    public bool IsConfigured =>
        !string.IsNullOrWhiteSpace(ApiKey)
        && !string.IsNullOrWhiteSpace(ProjectId)
        && !string.IsNullOrWhiteSpace(MessagingSenderId)
        && !string.IsNullOrWhiteSpace(AppId)
        && !string.IsNullOrWhiteSpace(VapidKey);
}
