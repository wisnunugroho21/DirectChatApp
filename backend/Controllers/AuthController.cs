using System.ComponentModel.DataAnnotations;
using System.Security.Claims;
using ChatApp.Models;
using ChatApp.Services;
using Microsoft.AspNetCore.Authentication.BearerToken;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using MongoDB.Bson;

namespace ChatApp.Controllers;

public record LoginRequest([Required] string Username, [Required] string Password);
public record RegisterRequest(
    [Required, StringLength(80)] string Username,
    [Required, EmailAddress] string Email,
    [Required, MinLength(6)] string Password,
    [Required] string ConfirmPassword,
    [Required, StringLength(160)] string FullName,
    string? Nickname, int? EmployeeId);

[ApiController, Route("api/auth")]
public class AuthController(AuthService auth, UserService users) : ControllerBase
{
    [HttpPost("login")]
    public async Task<IActionResult> Login(LoginRequest request)
    {
        var user = await auth.LoginCheck(request.Username, request.Password);
        if (user is null) return Unauthorized(new { message = "Invalid username or password." });
        var identity = new ClaimsIdentity(new[]
        {
            new Claim(ClaimTypes.NameIdentifier, user.Username),
            new Claim(ClaimTypes.Name, user.Username)
        }, BearerTokenDefaults.AuthenticationScheme);
        return SignIn(new ClaimsPrincipal(identity), BearerTokenDefaults.AuthenticationScheme);
    }

    [HttpPost("register")]
    public async Task<IActionResult> Register(RegisterRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Username) || string.IsNullOrWhiteSpace(request.FullName) ||
            string.IsNullOrWhiteSpace(request.Password) || request.Password != request.ConfirmPassword)
            return BadRequest(new { message = "Complete all fields and use matching passwords." });
        if (await auth.CheckIfExist(request.Email.ToLowerInvariant(), request.Username))
            return Conflict(new { message = "Email or username already registered." });
        var user = new User
        {
            Id = ObjectId.GenerateNewId(), Username = request.Username.Trim(),
            Email = request.Email.Trim().ToLowerInvariant(), Password = request.Password,
            FullName = request.FullName.Trim(), Nickname = request.Nickname?.Trim(), EmployeeId = request.EmployeeId
        };
        try { await auth.CreateUser(user); }
        catch (Exception ex) when (ChatApp.Data.MongoWriteErrors.IsDuplicateKey(ex))
        { return Conflict(new { message = "Email or username already registered." }); }
        return StatusCode(201, new { user.Username });
    }

    [Authorize, HttpGet("me")]
    public async Task<IActionResult> Me()
    {
        var user = await users.GetByUsernameAsync(User.Identity!.Name!);
        return user is null ? Unauthorized() : Ok(new { user.Username, user.FullName, user.Email, user.Nickname, user.PhotoUrl });
    }
}

