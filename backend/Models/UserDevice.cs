using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace ChatApp.Models;

/// <summary>
/// Satu dokumen per perangkat/browser yang terdaftar untuk Firebase Cloud
/// Messaging. Token bersifat unik global, jadi kalau perangkat yang sama dipakai
/// akun lain, kepemilikannya berpindah — bukan menambah baris baru.
/// </summary>
public class UserDevice
{
    [BsonId]
    public ObjectId Id { get; set; }

    public ObjectId UserId { get; set; }

    public string Token { get; set; } = null!;

    public string? Platform { get; set; }

    public string? UserAgent { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime LastSeenAt { get; set; } = DateTime.UtcNow;
}
