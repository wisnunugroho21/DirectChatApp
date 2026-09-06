using ChatApp.Data;
using ChatApp.Extensions;
using ChatApp.Models;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Options;
using MongoDB.Bson;

namespace ChatApp.Services;

/// <summary>
/// Menyimpan berkas lampiran ke disk dan mencatat metadatanya sebagai pesan.
///
/// Berkasnya disimpan dengan nama hasil generate, bukan nama dari klien: nama
/// asli hanya dipakai untuk ditampilkan. Ini yang mencegah nama seperti
/// "../../appsettings.json" menulis ke luar folder penyimpanan.
/// </summary>
public sealed class AttachmentService(
    ChatDbContext db,
    MessageService messages,
    IOptions<FileStorageSettings> options,
    IHostEnvironment environment,
    ILogger<AttachmentService> logger)
{
    private readonly FileStorageSettings _settings = options.Value;

    public long MaxFileSizeBytes => _settings.MaxFileSizeBytes;

    /// <summary>
    /// Menyimpan berkas, lalu membuat pesan beserta baris lampirannya.
    /// </summary>
    public async Task<(Message Message, Attachment Attachment)> SaveAsync(
        ObjectId conversationId,
        ObjectId senderId,
        Stream content,
        string fileName,
        string? contentType,
        CancellationToken cancellationToken = default)
    {
        var attachmentId = ObjectId.GenerateNewId();
        var safeName = SanitizeFileName(fileName);
        var mimeType = NormalizeMimeType(contentType);

        var relativePath = Path.Combine(conversationId.ToString(), attachmentId + Path.GetExtension(safeName));
        var fullPath = Path.Combine(RootDirectory(), relativePath);

        Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);

        long size;

        await using (var file = File.Create(fullPath))
        {
            await content.CopyToAsync(file, cancellationToken);
            size = file.Length;
        }

        try
        {
            var message = await messages.SaveAsync(
                conversationId,
                senderId,
                safeName,
                MessageTypeFor(mimeType),
                cancellationToken: cancellationToken);

            var attachment = new Attachment
            {
                Id = attachmentId,
                MessageId = message.Id,
                FileName = safeName,
                // Yang disimpan adalah path relatif, bukan URL absolut: alamat
                // server bisa berubah (devtunnel, produksi), path-nya tidak.
                Url = relativePath.Replace('\\', '/'),
                Size = size,
                MimeType = mimeType
            };

            db.Attachments.Add(attachment);
            await db.SaveChangesAsync(cancellationToken);

            return (message, attachment);
        }
        catch
        {
            // Jangan tinggalkan berkas yatim kalau pencatatannya gagal.
            TryDelete(fullPath);
            throw;
        }
    }

    public async Task<Attachment?> GetForMessageAsync(
        ObjectId messageId,
        CancellationToken cancellationToken = default)
    {
        return await db.Attachments.FirstOrDefaultAsync(a => a.MessageId == messageId, cancellationToken);
    }

    /// <summary>Lampiran milik sekumpulan pesan, untuk merender riwayat sekaligus.</summary>
    public async Task<Dictionary<ObjectId, Attachment>> GetForMessagesAsync(
        IReadOnlyCollection<ObjectId> messageIds,
        CancellationToken cancellationToken = default)
    {
        if (messageIds.Count == 0) return [];

        var list = messageIds.ToList();

        var attachments = await db.Attachments
            .Where(a => list.Contains(a.MessageId))
            .ToListAsync(cancellationToken);

        // Satu pesan hanya punya satu lampiran; kalau ada duplikat, yang pertama dipakai.
        var map = new Dictionary<ObjectId, Attachment>();
        foreach (var attachment in attachments) map.TryAdd(attachment.MessageId, attachment);

        return map;
    }

    public async Task<Attachment?> GetByIdAsync(
        ObjectId attachmentId,
        CancellationToken cancellationToken = default)
    {
        return await db.Attachments.FirstOrDefaultAsync(a => a.Id == attachmentId, cancellationToken);
    }

    /// <summary>Membuka isi berkas untuk diunduh, atau null bila berkasnya sudah tidak ada.</summary>
    public Stream? OpenRead(Attachment attachment)
    {
        var fullPath = Path.Combine(RootDirectory(), attachment.Url.Replace('/', Path.DirectorySeparatorChar));

        // Pastikan hasil penggabungan tetap di dalam folder penyimpanan.
        var root = Path.GetFullPath(RootDirectory());
        var resolved = Path.GetFullPath(fullPath);

        if (!resolved.StartsWith(root, StringComparison.Ordinal))
        {
            logger.LogWarning("Lampiran {AttachmentId} menunjuk ke luar folder penyimpanan.", attachment.Id);
            return null;
        }

        return File.Exists(resolved) ? File.OpenRead(resolved) : null;
    }

    public static bool IsInlineSafe(string mimeType) =>
        FileStorageSettings.InlineSafeMimeTypes.Contains(mimeType, StringComparer.OrdinalIgnoreCase);

    private string RootDirectory() =>
        Path.IsPathRooted(_settings.RootPath)
            ? _settings.RootPath
            : Path.Combine(environment.ContentRootPath, _settings.RootPath);

    /// <summary>Menentukan tipe pesan dari MIME, supaya klien tahu cara menampilkannya.</summary>
    private static string MessageTypeFor(string mimeType)
    {
        if (mimeType.StartsWith("image/", StringComparison.OrdinalIgnoreCase)) return ChatTypeCatalog.ImageMessage;
        if (mimeType.StartsWith("video/", StringComparison.OrdinalIgnoreCase)) return ChatTypeCatalog.VideoMessage;
        if (mimeType.StartsWith("audio/", StringComparison.OrdinalIgnoreCase)) return ChatTypeCatalog.AudioMessage;

        return ChatTypeCatalog.FileMessage;
    }

    private static string NormalizeMimeType(string? contentType)
    {
        if (string.IsNullOrWhiteSpace(contentType)) return "application/octet-stream";

        // Buang parameter seperti "; charset=utf-8".
        var separator = contentType.IndexOf(';');
        var value = (separator >= 0 ? contentType[..separator] : contentType).Trim();

        return value.Length == 0 ? "application/octet-stream" : value;
    }

    /// <summary>
    /// Menyisakan nama berkas saja, tanpa komponen direktori, untuk ditampilkan.
    /// </summary>
    private static string SanitizeFileName(string fileName)
    {
        var name = Path.GetFileName(fileName.Replace('\\', '/'));

        foreach (var invalid in Path.GetInvalidFileNameChars())
        {
            name = name.Replace(invalid, '_');
        }

        name = name.Trim();
        if (name.Length == 0) name = "berkas";

        return name.Length > 120 ? name[^120..] : name;
    }

    private void TryDelete(string path)
    {
        try
        {
            if (File.Exists(path)) File.Delete(path);
        }
        catch (IOException ex)
        {
            logger.LogWarning(ex, "Berkas lampiran {Path} gagal dibersihkan.", path);
        }
    }
}
