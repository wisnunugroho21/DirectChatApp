using System.Collections.Concurrent;

namespace ChatApp.Services;

/// <summary>
/// Mencatat koneksi SignalR aktif per user, beserta perangkat mana yang memakai
/// koneksi itu.
///
/// Dipakai untuk dua hal: menentukan status kehadiran yang benar saat user
/// membuka beberapa tab, dan memutuskan perangkat mana yang perlu dikirimi
/// notifikasi. Perangkat yang koneksinya sedang hidup sudah menerima pesannya
/// lewat SignalR, jadi justru tidak boleh ikut didorong lewat FCM.
///
/// Catatan: penyimpanannya in-memory, jadi hanya akurat untuk satu instance.
/// Kalau nanti di-scale out, pindahkan ke Redis (SignalR backplane) supaya
/// keputusan push tidak salah.
/// </summary>
public sealed class ConnectionTracker
{
    private sealed class ConnectionInfo
    {
        /// <summary>Token FCM perangkat pemilik koneksi ini, bila sudah ditautkan.</summary>
        public string? DeviceToken;
    }

    private static readonly IReadOnlySet<string> NoTokens = new HashSet<string>();

    private readonly ConcurrentDictionary<string, ConcurrentDictionary<string, ConnectionInfo>> _connections =
        new(StringComparer.OrdinalIgnoreCase);

    /// <summary>Mendaftarkan koneksi. Mengembalikan true kalau ini koneksi pertama user tersebut.</summary>
    public bool Add(string username, string connectionId)
    {
        var connections = _connections.GetOrAdd(username, _ => new ConcurrentDictionary<string, ConnectionInfo>());
        connections[connectionId] = new ConnectionInfo();
        return connections.Count == 1;
    }

    /// <summary>Melepas koneksi. Mengembalikan true kalau user sudah tidak punya koneksi tersisa.</summary>
    public bool Remove(string username, string connectionId)
    {
        if (!_connections.TryGetValue(username, out var connections)) return true;

        connections.TryRemove(connectionId, out _);

        if (!connections.IsEmpty) return false;

        // Hapus entri kosong, tapi jangan sampai membuang koneksi baru yang
        // menyelip tepat setelah pengecekan di atas.
        _connections.TryRemove(new KeyValuePair<string, ConcurrentDictionary<string, ConnectionInfo>>(username, connections));
        return true;
    }

    /// <summary>
    /// Menautkan token FCM ke sebuah koneksi. Dipanggil klien setelah tokennya
    /// tersedia, dan diulang setiap kali koneksinya terbentuk lagi karena
    /// connectionId-nya berganti.
    /// </summary>
    public void BindDevice(string username, string connectionId, string deviceToken)
    {
        if (_connections.TryGetValue(username, out var connections)
            && connections.TryGetValue(connectionId, out var info))
        {
            info.DeviceToken = deviceToken;
        }
    }

    /// <summary>
    /// Token perangkat yang koneksinya sedang hidup. Perangkat ini sudah
    /// menerima pesannya lewat SignalR, jadi harus dikecualikan dari push.
    /// </summary>
    public IReadOnlySet<string> GetActiveDeviceTokens(string username)
    {
        if (!_connections.TryGetValue(username, out var connections)) return NoTokens;

        var tokens = new HashSet<string>(StringComparer.Ordinal);

        foreach (var info in connections.Values)
        {
            var token = info.DeviceToken;
            if (!string.IsNullOrWhiteSpace(token)) tokens.Add(token);
        }

        return tokens;
    }
}
