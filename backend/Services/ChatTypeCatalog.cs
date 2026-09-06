using MongoDB.Bson;
using System.Collections.Concurrent;

namespace ChatApp.Services;

/// <summary>
/// Cache untuk koleksi referensi ConversationTypes/MessageTypes yang di-seed saat
/// startup, supaya jalur panas (kirim pesan) tidak perlu query lookup berulang.
/// </summary>
public sealed class ChatTypeCatalog
{
    public const string DirectConversation = "Direct";
    public const string GroupConversation = "Group";

    public const string TextMessage = "Text";
    public const string ImageMessage = "Image";
    public const string FileMessage = "File";
    public const string AudioMessage = "Audio";
    public const string VideoMessage = "Video";
    public const string SystemMessage = "System";

    public static readonly string[] ConversationTypeNames =
    [
        DirectConversation,
        GroupConversation
    ];

    public static readonly string[] MessageTypeNames =
    [
        TextMessage,
        ImageMessage,
        FileMessage,
        AudioMessage,
        VideoMessage,
        SystemMessage
    ];

    private readonly ConcurrentDictionary<string, ObjectId> _conversationTypes =
        new(StringComparer.OrdinalIgnoreCase);

    private readonly ConcurrentDictionary<string, ObjectId> _messageTypes =
        new(StringComparer.OrdinalIgnoreCase);

    public void SetConversationType(string name, ObjectId id) => _conversationTypes[name] = id;

    public void SetMessageType(string name, ObjectId id) => _messageTypes[name] = id;

    public ObjectId ConversationTypeId(string name) =>
        _conversationTypes.TryGetValue(name, out var id)
            ? id
            : throw new InvalidOperationException($"ConversationType '{name}' belum tersedia di database.");

    public ObjectId MessageTypeId(string name) =>
        _messageTypes.TryGetValue(name, out var id)
            ? id
            : throw new InvalidOperationException($"MessageType '{name}' belum tersedia di database.");

    public string MessageTypeName(ObjectId id)
    {
        foreach (var pair in _messageTypes)
        {
            if (pair.Value == id) return pair.Key;
        }

        return TextMessage;
    }
}
