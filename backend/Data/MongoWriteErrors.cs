using Microsoft.EntityFrameworkCore;
using MongoDB.Driver;

namespace ChatApp.Data;

/// <summary>
/// EF Core tidak punya operasi upsert, jadi pola yang dipakai adalah
/// "cari — kalau belum ada, sisipkan" lalu menangani benturan yang mungkin
/// terjadi di antara keduanya.
///
/// Yang menjaga keunikan tetap index unik di MongoDB, bukan pengecekan di
/// aplikasi: ketika dua permintaan menyisipkan baris yang sama secara
/// bersamaan, satu berhasil dan satu lagi ditolak server dengan galat duplicate
/// key. Kelas ini mengenali galat itu supaya pemanggil bisa membaca ulang baris
/// yang sudah dibuat pihak lain.
/// </summary>
public static class MongoWriteErrors
{
    /// <summary>Kode galat duplicate key dari MongoDB.</summary>
    private const int DuplicateKeyCode = 11000;

    public static bool IsDuplicateKey(Exception exception)
    {
        for (var current = exception; current is not null; current = current.InnerException)
        {
            switch (current)
            {
                case MongoWriteException write
                    when write.WriteError?.Category == ServerErrorCategory.DuplicateKey
                        || write.WriteError?.Code == DuplicateKeyCode:
                    return true;

                case MongoBulkWriteException bulk
                    when bulk.WriteErrors.Any(e =>
                        e.Category == ServerErrorCategory.DuplicateKey || e.Code == DuplicateKeyCode):
                    return true;

                case MongoCommandException command when command.Code == DuplicateKeyCode:
                    return true;
            }
        }

        return false;
    }

    /// <summary>
    /// Menyimpan perubahan, dan menelan galat duplicate key.
    /// </summary>
    /// <returns>true bila tersimpan, false bila kalah balapan dengan penulis lain.</returns>
    public static async Task<bool> TrySaveChangesAsync(
        this DbContext context,
        CancellationToken cancellationToken = default)
    {
        try
        {
            await context.SaveChangesAsync(cancellationToken);
            return true;
        }
        catch (Exception ex) when (IsDuplicateKey(ex))
        {
            // Baris yang sama sudah dibuat permintaan lain. Entri yang gagal
            // dilepas dari change tracker supaya SaveChanges berikutnya tidak
            // mencoba menulisnya lagi.
            foreach (var entry in context.ChangeTracker.Entries()
                         .Where(e => e.State == EntityState.Added)
                         .ToList())
            {
                entry.State = EntityState.Detached;
            }

            return false;
        }
    }
}
