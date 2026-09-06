using ChatApp.Data;
using ChatApp.Models;
using Microsoft.EntityFrameworkCore;
using MongoDB.Bson;
using MongoDB.Driver;
using MongoDB.EntityFrameworkCore.Extensions;

namespace ChatApp.Services;

/// <summary>
/// Menyiapkan database saat aplikasi start: seed koleksi referensi
/// (ConversationTypes/MessageTypes) dan membuat index yang dibutuhkan.
/// Semua operasinya idempotent, jadi aman dijalankan setiap kali start.
///
/// Seed memakai EF seperti sisa aplikasi. Pembuatan index tidak bisa: provider
/// EF Core untuk MongoDB tidak mengenal migration maupun HasIndex, jadi bagian
/// itu memakai driver. Nama koleksinya dibaca dari model EF supaya index selalu
/// menempel pada koleksi yang sama dengan yang dipakai DbContext.
/// </summary>
public sealed class MongoDbInitializer(
    IServiceScopeFactory scopeFactory,
    IMongoDatabase database,
    ChatTypeCatalog catalog,
    ILogger<MongoDbInitializer> logger) : IHostedService
{
    public async Task StartAsync(CancellationToken cancellationToken)
    {
        using var scope = scopeFactory.CreateScope();
        var db = scope.ServiceProvider.GetRequiredService<ChatDbContext>();

        await SeedTypesAsync(db, cancellationToken);
        await EnsureIndexesAsync(db, cancellationToken);
    }

    public Task StopAsync(CancellationToken cancellationToken) => Task.CompletedTask;

    private async Task SeedTypesAsync(ChatDbContext db, CancellationToken cancellationToken)
    {
        foreach (var name in ChatTypeCatalog.ConversationTypeNames)
        {
            var type = await db.ConversationTypes.FirstOrDefaultAsync(t => t.Name == name, cancellationToken);

            if (type is null)
            {
                type = new ConversationType { Id = ObjectId.GenerateNewId(), Name = name };
                db.ConversationTypes.Add(type);

                if (!await db.TrySaveChangesAsync(cancellationToken))
                {
                    type = await db.ConversationTypes.FirstAsync(t => t.Name == name, cancellationToken);
                }
            }

            catalog.SetConversationType(name, type.Id);
        }

        foreach (var name in ChatTypeCatalog.MessageTypeNames)
        {
            var type = await db.MessageTypes.FirstOrDefaultAsync(t => t.Name == name, cancellationToken);

            if (type is null)
            {
                type = new MessageType { Id = ObjectId.GenerateNewId(), Name = name };
                db.MessageTypes.Add(type);

                if (!await db.TrySaveChangesAsync(cancellationToken))
                {
                    type = await db.MessageTypes.FirstAsync(t => t.Name == name, cancellationToken);
                }
            }

            catalog.SetMessageType(name, type.Id);
        }
    }

    /// <summary>Koleksi milik sebuah entitas, sesuai pemetaan di ChatDbContext.</summary>
    private IMongoCollection<T> CollectionFor<T>(ChatDbContext db) where T : class
    {
        var name = db.Model.FindEntityType(typeof(T))?.GetCollectionName()
            ?? throw new InvalidOperationException($"Entitas {typeof(T).Name} tidak terpetakan ke koleksi mana pun.");

        return database.GetCollection<T>(name);
    }

    private async Task EnsureIndexesAsync(ChatDbContext db, CancellationToken cancellationToken)
    {
        var users = CollectionFor<User>(db);
        var conversations = CollectionFor<Conversation>(db);
        var members = CollectionFor<ConversationMember>(db);
        var messages = CollectionFor<Message>(db);
        var messageReads = CollectionFor<MessageRead>(db);
        var attachments = CollectionFor<Attachment>(db);
        var devices = CollectionFor<UserDevice>(db);
        var calls = CollectionFor<CallHistory>(db);

        // Index unik dibuat terpisah: kalau data lama punya duplikat, satu index
        // yang gagal tidak boleh menggagalkan startup aplikasi.
        await CreateAsync(users, new CreateIndexModel<User>(
            Builders<User>.IndexKeys.Ascending(u => u.Username),
            new CreateIndexOptions { Name = "ux_users_username", Unique = true }), cancellationToken);

        await CreateAsync(users, new CreateIndexModel<User>(
            Builders<User>.IndexKeys.Ascending(u => u.Email),
            new CreateIndexOptions { Name = "ux_users_email", Unique = true }), cancellationToken);

        // Index ini pernah dibuat sebagai sparse. Definisinya berubah menjadi
        // parsial, dan MongoDB menolak membuat ulang index bernama sama dengan
        // opsi berbeda, jadi yang lama dibuang dulu.
        await DropIndexIfExistsAsync(conversations, "ux_conversations_directKey", cancellationToken);

        await CreateAsync(conversations, new CreateIndexModel<Conversation>(
            Builders<Conversation>.IndexKeys.Ascending(c => c.DirectKey),
            new CreateIndexOptions<Conversation>
            {
                Name = "ux_conversations_directKey",
                Unique = true,

                // Hanya dokumen yang DirectKey-nya benar-benar berisi string yang
                // diindeks. Percakapan grup (DirectKey null) tidak saling bentrok,
                // baik field-nya ada bernilai null maupun tidak ada sama sekali.
                PartialFilterExpression = Builders<Conversation>.Filter.Type(c => c.DirectKey, BsonType.String)
            }),
            cancellationToken);

        await CreateAsync(members, new CreateIndexModel<ConversationMember>(
            Builders<ConversationMember>.IndexKeys
                .Ascending(m => m.ConversationId)
                .Ascending(m => m.UserId),
            new CreateIndexOptions { Name = "ux_members_conversation_user", Unique = true }), cancellationToken);

        await CreateAsync(members, new CreateIndexModel<ConversationMember>(
            Builders<ConversationMember>.IndexKeys.Ascending(m => m.UserId),
            new CreateIndexOptions { Name = "ix_members_user" }), cancellationToken);

        await CreateAsync(messages, new CreateIndexModel<Message>(
            Builders<Message>.IndexKeys
                .Ascending(m => m.ConversationId)
                .Descending(m => m.CreatedAt),
            new CreateIndexOptions { Name = "ix_messages_conversation_createdAt" }), cancellationToken);

        await CreateAsync(messageReads, new CreateIndexModel<MessageRead>(
            Builders<MessageRead>.IndexKeys
                .Ascending(r => r.MessageId)
                .Ascending(r => r.UserId),
            new CreateIndexOptions { Name = "ux_messageReads_message_user", Unique = true }), cancellationToken);

        await CreateAsync(attachments, new CreateIndexModel<Attachment>(
            Builders<Attachment>.IndexKeys.Ascending(a => a.MessageId),
            new CreateIndexOptions { Name = "ix_attachments_message" }), cancellationToken);

        await CreateAsync(devices, new CreateIndexModel<UserDevice>(
            Builders<UserDevice>.IndexKeys.Ascending(d => d.Token),
            new CreateIndexOptions { Name = "ux_userDevices_token", Unique = true }), cancellationToken);

        await CreateAsync(devices, new CreateIndexModel<UserDevice>(
            Builders<UserDevice>.IndexKeys.Ascending(d => d.UserId),
            new CreateIndexOptions { Name = "ix_userDevices_user" }), cancellationToken);

        await CreateAsync(calls, new CreateIndexModel<CallHistory>(
            Builders<CallHistory>.IndexKeys
                .Ascending(c => c.CallerId)
                .Descending(c => c.StartDate),
            new CreateIndexOptions { Name = "ix_calls_caller_startDate" }), cancellationToken);

        await CreateAsync(calls, new CreateIndexModel<CallHistory>(
            Builders<CallHistory>.IndexKeys
                .Ascending(c => c.ReceiverId)
                .Descending(c => c.StartDate),
            new CreateIndexOptions { Name = "ix_calls_receiver_startDate" }), cancellationToken);
    }

    private async Task DropIndexIfExistsAsync<T>(
        IMongoCollection<T> collection,
        string indexName,
        CancellationToken cancellationToken)
    {
        try
        {
            using var cursor = await collection.Indexes.ListAsync(cancellationToken);
            var existing = await cursor.ToListAsync(cancellationToken);

            var current = existing.FirstOrDefault(i => i["name"] == indexName);
            if (current is null) return;

            // Sudah parsial: tidak perlu dibuat ulang.
            if (current.Contains("partialFilterExpression")) return;

            await collection.Indexes.DropOneAsync(indexName, cancellationToken);

            logger.LogInformation(
                "Index {IndexName} lama dibuang untuk dibuat ulang dengan definisi baru.", indexName);
        }
        catch (MongoCommandException ex)
        {
            logger.LogWarning(ex, "Index {IndexName} tidak dapat diperiksa/dibuang.", indexName);
        }
    }

    private async Task CreateAsync<T>(
        IMongoCollection<T> collection,
        CreateIndexModel<T> index,
        CancellationToken cancellationToken)
    {
        try
        {
            await collection.Indexes.CreateOneAsync(index, cancellationToken: cancellationToken);
        }
        catch (MongoCommandException ex)
        {
            logger.LogWarning(
                ex,
                "Index {IndexName} pada {Collection} gagal dibuat. Periksa data duplikat.",
                index.Options?.Name,
                collection.CollectionNamespace.CollectionName);
        }
    }
}
