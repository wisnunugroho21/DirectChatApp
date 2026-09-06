using MongoDB.Bson;
using MongoDB.Bson.Serialization.Attributes;

namespace ChatApp.Models;

public class Conversation
{
    [BsonId]
    public ObjectId Id { get; set; }

    public ObjectId TypeId { get; set; }

    // Kunci unik untuk chat 1-1 ("<idKecil>:<idBesar>"), dipakai supaya percakapan
    // langsung tidak pernah terduplikasi walau dibuat bersamaan dari dua sisi.
    // Null untuk grup.
    //
    // Dulu ditandai [BsonIgnoreIfNull] supaya field-nya hilang dari dokumen dan
    // terlewat oleh index sparse. Provider EF Core menolak atribut itu, jadi
    // pengecualian null sekarang ditegakkan index parsial di MongoDbInitializer
    // — hasilnya sama, dan tidak lagi bergantung pada ada/tidaknya field.
    public string? DirectKey { get; set; }

    public string? Name { get; set; }

    public string? PhotoUrl { get; set; }

    public ObjectId CreatedBy { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime? UpdatedAt { get; set; }
}
