using ChatApp.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace ChatApp.Controllers;

[ApiController]
[Authorize]
[Route("api/[controller]")]
public class UsersController(UserService user) : ControllerBase
{
    /// <summary>
    /// Kontak yang bisa diajak chat. Hanya field yang dibutuhkan UI yang dikirim —
    /// dokumen User utuh berisi kredensial dan tidak boleh keluar dari server.
    /// </summary>
    [HttpGet]
    public async Task<IActionResult> Gets()
    {
        var username = User.Identity?.Name;
        if (string.IsNullOrWhiteSpace(username)) return Unauthorized();

        var contacts = await user.GetContactsAsync(username);

        return Ok(contacts.Select(u => new
        {
            id = u.Id.ToString(),
            username = u.Username,
            fullName = u.FullName,
            nickname = u.Nickname,
            photoUrl = u.PhotoUrl,
            status = u.Status,
            lastOnline = u.LastOnline
        }));
    }
}
