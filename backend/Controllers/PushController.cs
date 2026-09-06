using ChatApp.Extensions;
using ChatApp.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;

namespace ChatApp.Controllers;

public record DeviceTokenRequest(string Token, string? Platform);

[ApiController]
[Authorize]
[Route("api/[controller]")]
public class PushController(
    UserService users,
    DeviceService devices,
    IOptions<FirebaseSettings> settings) : ControllerBase
{
    /// <summary>
    /// Konfigurasi Firebase Web SDK untuk browser. Nilai-nilai ini memang bersifat
    /// publik; kredensial service account tidak pernah ikut ke sini.
    /// </summary>
    [HttpGet("config")]
    public IActionResult GetConfig()
    {
        var web = settings.Value.Web;

        if (!web.IsConfigured || !PushNotificationService.IsEnabled)
        {
            return Ok(new { enabled = false });
        }

        return Ok(new
        {
            enabled = true,
            apiKey = web.ApiKey,
            authDomain = web.AuthDomain,
            projectId = web.ProjectId,
            storageBucket = web.StorageBucket,
            messagingSenderId = web.MessagingSenderId,
            appId = web.AppId,
            vapidKey = web.VapidKey
        });
    }

    /// <summary>Mendaftarkan token FCM perangkat ini untuk user yang sedang login.</summary>
    [HttpPost("devices")]
    public async Task<IActionResult> Register(
        [FromBody] DeviceTokenRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Token))
            return BadRequest(new { message = "Token wajib diisi." });

        var username = User.Identity?.Name;
        if (string.IsNullOrWhiteSpace(username)) return Unauthorized();

        var me = await users.GetByUsernameAsync(username);
        if (me is null) return Unauthorized();

        await devices.RegisterAsync(
            me.Id,
            request.Token.Trim(),
            NormalizePlatform(request.Platform),
            Request.Headers.UserAgent.ToString(),
            cancellationToken);

        return NoContent();
    }

    /// <summary>
    /// Bentuk payload push ditentukan oleh nilai ini, jadi hanya platform yang
    /// dikenal yang diterima; sisanya diperlakukan sebagai web.
    /// </summary>
    private static string NormalizePlatform(string? platform) =>
        platform?.Trim().ToLowerInvariant() switch
        {
            "android" => "android",
            "ios" => "ios",
            _ => "web"
        };

    /// <summary>Melepas token, dipakai saat logout atau izin notifikasi dicabut.</summary>
    [HttpDelete("devices")]
    public async Task<IActionResult> Unregister(
        [FromBody] DeviceTokenRequest request,
        CancellationToken cancellationToken)
    {
        if (string.IsNullOrWhiteSpace(request.Token))
            return BadRequest(new { message = "Token wajib diisi." });

        var username = User.Identity?.Name;
        if (string.IsNullOrWhiteSpace(username)) return Unauthorized();
        var me = await users.GetByUsernameAsync(username);
        var device = await devices.GetByTokenAsync(request.Token.Trim(), cancellationToken);
        if (me is null) return Unauthorized();
        if (device is not null && device.UserId != me.Id) return Forbid();
        await devices.RemoveAsync(request.Token.Trim(), cancellationToken);
        return NoContent();
    }
}

