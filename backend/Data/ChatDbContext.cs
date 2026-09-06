using ChatApp.Models;
using Microsoft.EntityFrameworkCore;
using MongoDB.EntityFrameworkCore.Extensions;

namespace ChatApp.Data;

/// <summary>
/// Akses data lewat EF Core dengan provider MongoDB.
///
/// Database dan seluruh dokumennya tetap sama seperti sebelumnya, jadi pemetaan
/// di bawah harus menghasilkan bentuk dokumen yang persis: koleksi Users memakai
/// nama field camelCase (warisan atribut BsonElement), sedangkan koleksi lain
/// memakai nama properti apa adanya.
///
/// Beberapa operasi masih memakai driver MongoDB secara langsung karena tidak
/// punya padanan di EF: upsert atomik, bulk write, agregasi, dan pembuatan index.
/// Keduanya menulis ke dokumen yang sama, karena itu pemetaan ini tidak boleh
/// menyimpang.
/// </summary>
public class ChatDbContext : DbContext
{
    public ChatDbContext(DbContextOptions<ChatDbContext> options) : base(options)
    {
        // Provider EF membungkus SaveChanges yang menyentuh lebih dari satu
        // dokumen ke dalam transaksi, sedangkan MongoDB standalone tidak
        // mendukung transaksi (butuh replica set).
        //
        // Dimatikan supaya perilakunya persis seperti sebelum memakai EF: setiap
        // tulisan berdiri sendiri. Kalau nanti dijalankan di replica set dan
        // atomisitas lintas dokumen memang diinginkan, hapus baris ini.
        Database.AutoTransactionBehavior = AutoTransactionBehavior.Never;
    }

    public DbSet<User> Users => Set<User>();
    public DbSet<Conversation> Conversations => Set<Conversation>();
    public DbSet<ConversationType> ConversationTypes => Set<ConversationType>();
    public DbSet<ConversationMember> ConversationMembers => Set<ConversationMember>();
    public DbSet<Message> Messages => Set<Message>();
    public DbSet<MessageType> MessageTypes => Set<MessageType>();
    public DbSet<MessageRead> MessageReads => Set<MessageRead>();
    public DbSet<Attachment> Attachments => Set<Attachment>();
    public DbSet<CallHistory> CallHistories => Set<CallHistory>();
    public DbSet<UserDevice> UserDevices => Set<UserDevice>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<User>(entity =>
        {
            entity.ToCollection("Users");

            // Dokumen User yang sudah ada memakai camelCase. Dipetakan eksplisit
            // supaya tidak bergantung pada apakah provider ikut membaca
            // atribut BsonElement.
            entity.Property(e => e.EmployeeId).HasElementName("employeeId");
            entity.Property(e => e.Username).HasElementName("username");
            entity.Property(e => e.Email).HasElementName("email");
            entity.Property(e => e.Password).HasElementName("password");
            entity.Property(e => e.Nickname).HasElementName("nickname");
            entity.Property(e => e.FullName).HasElementName("fullName");
            entity.Property(e => e.PhotoUrl).HasElementName("photoUrl");
            entity.Property(e => e.Status).HasElementName("status");
            entity.Property(e => e.LastOnline).HasElementName("lastOnline");
            entity.Property(e => e.CreatedAt).HasElementName("createdAt");
            entity.Property(e => e.UpdatedAt).HasElementName("updatedAt");
        });

        modelBuilder.Entity<Conversation>().ToCollection("Conversations");
        modelBuilder.Entity<ConversationType>().ToCollection("ConversationTypes");
        modelBuilder.Entity<ConversationMember>().ToCollection("ConversationMembers");
        modelBuilder.Entity<Message>().ToCollection("Messages");
        modelBuilder.Entity<MessageType>().ToCollection("MessageTypes");
        modelBuilder.Entity<MessageRead>().ToCollection("MessageReads");
        modelBuilder.Entity<Attachment>().ToCollection("Attachments");
        modelBuilder.Entity<CallHistory>().ToCollection("CallHistories");
        modelBuilder.Entity<UserDevice>().ToCollection("UserDevices");

        base.OnModelCreating(modelBuilder);
    }
}
