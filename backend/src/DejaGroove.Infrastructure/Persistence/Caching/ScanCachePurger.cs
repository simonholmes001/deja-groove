using Dapper;
using DejaGroove.Application.Ports;
using Npgsql;

namespace DejaGroove.Infrastructure.Persistence.Caching;

/// <summary>
/// Time-based eviction of expired pHash cache rows (issue #79). Runs on the
/// admin/owner connection rather than the RLS-scoped app role: purging is a
/// cross-user maintenance job and must not be filtered by
/// <c>app.current_user_id</c>. Backed by the ix_scan_results_cache_expires_at
/// index (V003) so the sweep stays cheap on the Burstable instance.
/// </summary>
public sealed class ScanCachePurger(string adminConnectionString) : IScanCacheMaintenance
{
    private readonly string _connectionString =
        !string.IsNullOrWhiteSpace(adminConnectionString)
            ? adminConnectionString
            : throw new ArgumentException("Admin connection string is required.", nameof(adminConnectionString));

    public async Task<int> PurgeExpiredAsync(CancellationToken ct = default)
    {
        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(ct);
        return await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM scan_results_cache WHERE expires_at <= now()",
            cancellationToken: ct));
    }
}
