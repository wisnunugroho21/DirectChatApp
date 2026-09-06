using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace ChatApp.Models;

public class User
{
    [BsonId]
    public ObjectId Id { get; set; }

    [BsonElement("employeeId")]
    public int? EmployeeId { get; set; }

    [BsonElement("username")]
    public string Username { get; set; } = null!;

    [BsonElement("email")]
    public string Email { get; set; } = null!;

    [BsonElement("password")]
    public string Password { get; set; } = null!;

    [BsonElement("nickname")]
    public string? Nickname { get; set; }

    [BsonElement("fullName")]
    public string FullName { get; set; } = null!;

    [BsonElement("photoUrl")]
    public string? PhotoUrl { get; set; }

    [BsonElement("status")]
    public string Status { get; set; } = "Offline";

    [BsonElement("lastOnline")]
    public DateTime? LastOnline { get; set; }

    [BsonElement("createdAt")]
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    [BsonElement("updatedAt")]
    public DateTime? UpdatedAt { get; set; }
}
