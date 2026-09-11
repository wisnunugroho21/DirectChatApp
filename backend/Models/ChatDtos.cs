namespace ChatApp.Models;

// ObjectId tidak nyaman diserialisasi ke JSON, jadi semua id dikirim ke browser
// sebagai string lewat DTO di bawah ini.

public record MessageDto(
    string Id,
    string ConversationId,
    string Sender,
    string? Text,
    string Type,
    DateTime CreatedAt,
    bool Mine,
    AttachmentDto? Attachment = null);

public record AttachmentDto(
    string Id,
    string FileName,
    string MimeType,
    long Size,
    /// <summary>Alamat unduhan; isinya diperiksa keanggotaan percakapan.</summary>
    string Url);

public record ConversationSummaryDto(
    string Id,
    string PeerUsername,
    string PeerFullName,
    string? PeerPhotoUrl,
    string PeerStatus,
    string? LastMessage,
    DateTime? LastMessageAt,
    bool LastMessageMine,
    int Unread,
    string Type = "Direct",
    string? Name = null,
    int MemberCount = 2);

public record CallHistoryDto(
    string Id,
    string PeerUsername,
    string CallType,
    string Status,
    bool Outgoing,
    DateTime StartDate,
    DateTime? EndDate,
    int? Duration,
    bool IsGroup = false,
    string? ConversationId = null,
    string? ConversationName = null,
    int MemberCount = 2);
