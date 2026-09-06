using ChatApp.Data;
using ChatApp.Extensions;
using ChatApp.Services;
using Microsoft.AspNetCore.Authentication.BearerToken;
using Microsoft.EntityFrameworkCore;
using MongoDB.Driver;

var builder = WebApplication.CreateBuilder(args);
builder.Services.AddControllers();
builder.Services.AddProblemDetails();
builder.Services.AddSignalR();
builder.Services.AddSingleton<Microsoft.AspNetCore.SignalR.IUserIdProvider, ChatApp.Hubs.NameUserIdProvider>();
builder.Services.AddAuthentication(BearerTokenDefaults.AuthenticationScheme)
    .AddBearerToken(options => options.BearerTokenExpiration = TimeSpan.FromHours(12));
builder.Services.AddAuthorization();
builder.Services.AddCors(options => options.AddDefaultPolicy(policy => policy
    .WithOrigins(builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? [])
    .AllowAnyHeader().AllowAnyMethod().AllowCredentials()));
builder.Services.Configure<FileStorageSettings>(builder.Configuration.GetSection("FileStorage"));
builder.Services.Configure<MongoDbSettings>(builder.Configuration.GetSection("MongoDbSettings"));
var mongo = builder.Configuration.GetSection("MongoDbSettings").Get<MongoDbSettings>()
    ?? throw new InvalidOperationException("MongoDbSettings are required.");
builder.Services.AddDbContext<ChatDbContext>(options => options.UseMongoDB(mongo.ConnectionString, mongo.DatabaseName));
builder.Services.AddSingleton<IMongoClient>(_ => new MongoClient(mongo.ConnectionString));
builder.Services.AddSingleton(sp => sp.GetRequiredService<IMongoClient>().GetDatabase(mongo.DatabaseName));
using (var logs = LoggerFactory.Create(logging => logging.AddConsole()))
    builder.Services.AddFirebaseMessaging(builder.Configuration, builder.Environment.ContentRootPath, logs.CreateLogger("Firebase"));
builder.Services.InjectServices();
var app = builder.Build();
app.UseExceptionHandler();
app.UseCors();
// Browser WebSockets carry bearer credentials in the query string.
app.Use(async (context, next) =>
{
    if (context.Request.Path.StartsWithSegments("/chatHub") &&
        context.Request.Query.TryGetValue("access_token", out var token))
        context.Request.Headers.Authorization = $"Bearer {token}";
    await next();
});
app.UseAuthentication();
app.UseAuthorization();
app.MapControllers();
app.MapHub<ChatApp.Hubs.ChatHubs>("/chatHub", options => options.CloseOnAuthenticationExpiration = true);
app.MapGet("/health", () => Results.Ok(new { status = "ok" }));
app.MapGet("/api/webrtc/config", (IConfiguration config) => Results.Ok(new
{
    iceServers = config.GetSection("WebRtc:IceServers").GetChildren().Select(s => new
    {
        urls = s["Urls"], username = s["Username"] ?? "", credential = s["Credential"] ?? ""
    }).Where(s => !string.IsNullOrWhiteSpace(s.urls))
})).RequireAuthorization();
app.Run();

