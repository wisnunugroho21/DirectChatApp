namespace ChatApp.Extensions;

public class FileStorageSettings
{
    /// <summary>
    /// Folder penyimpanan lampiran. Path relatif dihitung dari folder aplikasi.
    ///
    /// Sengaja di luar wwwroot: isi percakapan bersifat privat, sementara apa pun
    /// di wwwroot bisa diunduh siapa saja yang menebak URL-nya. Unduhan dilayani
    /// endpoint yang memeriksa keanggotaan percakapan.
    /// </summary>
    public string RootPath { get; set; } = "storage/attachments";

    /// <summary>Ukuran maksimum satu berkas, dalam megabyte.</summary>
    public int MaxFileSizeMb { get; set; } = 25;

    public long MaxFileSizeBytes => MaxFileSizeMb * 1024L * 1024L;

    /// <summary>
    /// Tipe yang boleh ditampilkan langsung di browser. Selain ini dipaksa
    /// terunduh, karena berkas seperti HTML atau SVG yang dibuka inline bisa
    /// menjalankan skrip pada origin aplikasi.
    /// </summary>
    public static readonly string[] InlineSafeMimeTypes =
    [
        "image/png",
        "image/jpeg",
        "image/gif",
        "image/webp"
    ];
}
