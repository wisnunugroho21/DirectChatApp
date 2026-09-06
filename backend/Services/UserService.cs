using ChatApp.Data;
using ChatApp.Models;
using Microsoft.EntityFrameworkCore;
using MongoDB.Bson;

namespace ChatApp.Services;

public class UserService(ChatDbContext db)
{
    /// <summary>Daftar kontak untuk panel "New chat" — tanpa diri sendiri.</summary>
    public async Task<List<User>> GetContactsAsync(string username)
    {
        return await db.Users
            .Where(u => u.Username != username)
            .OrderBy(u => u.Username)
            .ToListAsync();
    }

    public async Task<User?> GetByUsernameAsync(string username)
    {
        var trimmed = username.Trim();
        return await db.Users.FirstOrDefaultAsync(u => u.Username == trimmed);
    }

    public async Task<List<User>> GetByIdsAsync(IEnumerable<ObjectId> ids)
    {
        var idList = ids.Distinct().ToList();
        if (idList.Count == 0) return [];

        return await db.Users.Where(u => idList.Contains(u.Id)).ToListAsync();
    }

    public async Task CreateUser(User user)
    {
        db.Users.Add(user);
        await db.SaveChangesAsync();
    }

    /// <summary>Menyimpan status kehadiran user ke database.</summary>
    public async Task SetPresenceAsync(string username, string status)
    {
        var user = await db.Users.FirstOrDefaultAsync(u => u.Username == username);
        if (user is null) return;

        user.Status = status;
        user.LastOnline = DateTime.UtcNow;
        user.UpdatedAt = DateTime.UtcNow;

        await db.SaveChangesAsync();
    }
}
