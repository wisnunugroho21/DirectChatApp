namespace ChatApp.Services;

public static class ServiceInjectionModule
{
    public static IServiceCollection InjectServices(this IServiceCollection services)
    {
        services.AddScoped<AuthService, AuthService>();
        services.AddScoped<MessageService, MessageService>();
        services.AddScoped<UserService, UserService>();
        services.AddScoped<ConversationService, ConversationService>();
        services.AddScoped<CallService, CallService>();
        services.AddScoped<DeviceService, DeviceService>();
        services.AddScoped<AttachmentService, AttachmentService>();
        services.AddScoped<PushNotificationService, PushNotificationService>();

        // Katalog tipe diisi sekali saat startup lalu hanya dibaca.
        services.AddSingleton<ChatTypeCatalog>();

        // Daftar koneksi aktif harus dibagi ke seluruh hub, jadi singleton.
        services.AddSingleton<ConnectionTracker>();
        services.AddSingleton<GroupCallRegistry>();
        services.AddHostedService<MongoDbInitializer>();

        return services;
    }
}
