using ChatApp.Data;
using ChatApp.Models;
using Microsoft.EntityFrameworkCore;
using MongoDB.Bson;

namespace ChatApp.Services;

public sealed class DeviceService(ChatDbContext db)
{
    /// <summary>
    /// Menyimpan token FCM sebuah perangkat. Kuncinya token, bukan user, supaya
    /// perangkat bersama otomatis berpindah ke akun yang sedang login.
    ///
    /// Kalau dua tab mendaftarkan token yang sama bersamaan, index unik pada
    /// Token menolak penyisipan kedua; sisi yang kalah cukup memperbarui baris
    /// yang sudah dibuat.
    /// </summary>
    public async Task RegisterAsync(
        ObjectId userId,
        string token,
        string? platform,
        string? userAgent,
        CancellationToken cancellationToken = default)
    {
        var now = DateTime.UtcNow;

        var device = await db.UserDevices.FirstOrDefaultAsync(d => d.Token == token, cancellationToken);

        if (device is null)
        {
            db.UserDevices.Add(new UserDevice
            {
                Id = ObjectId.GenerateNewId(),
                UserId = userId,
                Token = token,
                Platform = platform,
                UserAgent = userAgent,
                CreatedAt = now,
                LastSeenAt = now
            });

            if (await db.TrySaveChangesAsync(cancellationToken)) return;

            // Kalah balapan: lanjut memperbarui baris milik penulis yang menang.
            device = await db.UserDevices.FirstAsync(d => d.Token == token, cancellationToken);
        }

        device.UserId = userId;
        device.Platform = platform;
        device.UserAgent = userAgent;
        device.LastSeenAt = now;

        await db.SaveChangesAsync(cancellationToken);
    }

    public async Task<List<UserDevice>> GetForUserAsync(
        ObjectId userId,
        CancellationToken cancellationToken = default)
    {
        return await db.UserDevices
            .Where(d => d.UserId == userId)
            .ToListAsync(cancellationToken);
    }

    /// <summary>
    /// Mencari perangkat dari token FCM-nya. Dipakai jalur yang tidak punya
    /// cookie sesi, misalnya penolakan panggilan dari aplikasi Flutter.
    /// </summary>
    public async Task<UserDevice?> GetByTokenAsync(
        string token,
        CancellationToken cancellationToken = default)
    {
        return await db.UserDevices.FirstOrDefaultAsync(d => d.Token == token, cancellationToken);
    }

    public async Task RemoveAsync(string token, CancellationToken cancellationToken = default)
    {
        await db.UserDevices.Where(d => d.Token == token).ExecuteDeleteAsync(cancellationToken);
    }

    /// <summary>Membuang token yang ditolak FCM (aplikasi dihapus, izin dicabut, token kedaluwarsa).</summary>
    public async Task RemoveManyAsync(
        IEnumerable<string> tokens,
        CancellationToken cancellationToken = default)
    {
        var list = tokens.Distinct().ToList();
        if (list.Count == 0) return;

        await db.UserDevices.Where(d => list.Contains(d.Token)).ExecuteDeleteAsync(cancellationToken);
    }
}
