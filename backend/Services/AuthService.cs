using ChatApp.Data;
using ChatApp.Models;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace ChatApp.Services;

public class AuthService(ChatDbContext db, IConfiguration configuration)
{
    private const string Prefix = "identity:";
    private readonly PasswordHasher<User> hasher = new();
    public Task<bool> CheckIfExist(string email, string username) =>
        db.Users.AnyAsync(u => u.Email == email.Trim() || u.Username == username.Trim());
    public async Task CreateUser(User user)
    {
        user.Password = Prefix + hasher.HashPassword(user, user.Password);
        db.Users.Add(user);
        await db.SaveChangesAsync();
    }
    public async Task<User?> LoginCheck(string username, string password)
    {
        var key = username.Trim();
        var email = key.ToLowerInvariant();
        var user = await db.Users.FirstOrDefaultAsync(u => u.Username == key || u.Email == email);
        if (user is null) return null;
        if (user.Password.StartsWith(Prefix))
        {
            var result = hasher.VerifyHashedPassword(user, user.Password[Prefix.Length..], password);
            if (result == PasswordVerificationResult.Failed) return null;
            if (result == PasswordVerificationResult.Success) return user;
        }
        else if (!configuration.GetValue<bool>("Auth:AllowLegacyPlaintextPasswords") || user.Password != password)
            return null;
        user.Password = Prefix + hasher.HashPassword(user, password);
        await db.SaveChangesAsync();
        return user;
    }
}

