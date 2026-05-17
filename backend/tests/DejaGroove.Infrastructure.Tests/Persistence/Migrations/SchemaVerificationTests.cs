using Dapper;
using DejaGroove.Infrastructure.Persistence.Migrations;
using Npgsql;
using Testcontainers.PostgreSql;

namespace DejaGroove.Infrastructure.Tests.Persistence.Migrations;

/// <summary>
/// Verifies that the migrated schema enforces the domain invariants expressed
/// in the AlbumIdentity value object and the ScanStatus/operation enumerations.
/// These tests run against a real PostgreSQL 16 instance via Testcontainers.
/// </summary>
public sealed class SchemaVerificationTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
        await new MigrationRunner(_postgres.GetConnectionString()).ApplyAsync();
    }

    public Task DisposeAsync() => _postgres.DisposeAsync().AsTask();

    // ── collection_records ────────────────────────────────────────────────

    [Fact]
    public async Task CollectionRecords_RejectsRowWithNoIdentityFields()
    {
        await using var conn = OpenConnection();

        // No mbid, no discogs_release_id, title without artist — violates CHECK
        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                "INSERT INTO collection_records (user_id, title) VALUES (gen_random_uuid(), 'Orphan Album')"));
    }

    [Fact]
    public async Task CollectionRecords_AcceptsRowWithMbidOnly()
    {
        await using var conn = OpenConnection();

        var ex = await Record.ExceptionAsync(() =>
            conn.ExecuteAsync(
                "INSERT INTO collection_records (user_id, mbid) VALUES (gen_random_uuid(), 'abc-123-mbid')"));

        Assert.Null(ex);
    }

    [Fact]
    public async Task CollectionRecords_AcceptsRowWithDiscogsReleaseIdOnly()
    {
        await using var conn = OpenConnection();

        var ex = await Record.ExceptionAsync(() =>
            conn.ExecuteAsync(
                "INSERT INTO collection_records (user_id, discogs_release_id) VALUES (gen_random_uuid(), 'D-7654321')"));

        Assert.Null(ex);
    }

    [Fact]
    public async Task CollectionRecords_AcceptsRowWithTitleAndArtist()
    {
        await using var conn = OpenConnection();

        var ex = await Record.ExceptionAsync(() =>
            conn.ExecuteAsync(
                "INSERT INTO collection_records (user_id, title, artist) VALUES (gen_random_uuid(), 'Kind of Blue', 'Miles Davis')"));

        Assert.Null(ex);
    }

    [Fact]
    public async Task CollectionRecords_EnforcesUniqueActiveMbidPerUser()
    {
        await using var conn = OpenConnection();
        var userId = Guid.NewGuid();

        await conn.ExecuteAsync(
            "INSERT INTO collection_records (user_id, mbid) VALUES (@u, 'dup-mbid')",
            new { u = userId });

        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                "INSERT INTO collection_records (user_id, mbid) VALUES (@u, 'dup-mbid')",
                new { u = userId }));
    }

    [Fact]
    public async Task CollectionRecords_DefaultsVersionToOne()
    {
        await using var conn = OpenConnection();

        await conn.ExecuteAsync(
            "INSERT INTO collection_records (user_id, mbid) VALUES (gen_random_uuid(), 'version-check')");

        var version = await conn.ExecuteScalarAsync<int>(
            "SELECT version FROM collection_records WHERE mbid = 'version-check'");

        Assert.Equal(1, version);
    }

    // ── scan_events ───────────────────────────────────────────────────────

    [Fact]
    public async Task ScanEvents_RejectsUnknownResultStatus()
    {
        await using var conn = OpenConnection();

        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                @"INSERT INTO scan_events (scan_event_id, user_id, client_scan_id, result_status, confidence)
                  VALUES (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), 'InvalidStatus', 0.9)"));
    }

    [Theory]
    [InlineData("Owned")]
    [InlineData("SafeToBuy")]
    [InlineData("Ambiguous")]
    [InlineData("NoMatch")]
    public async Task ScanEvents_AcceptsAllDomainResultStatuses(string status)
    {
        await using var conn = OpenConnection();

        var ex = await Record.ExceptionAsync(() =>
            conn.ExecuteAsync(
                @"INSERT INTO scan_events (scan_event_id, user_id, client_scan_id, result_status, confidence)
                  VALUES (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(), @status, 0.8)",
                new { status }));

        Assert.Null(ex);
    }

    [Fact]
    public async Task ScanEvents_EnforcesUniqueClientScanIdPerUser()
    {
        await using var conn = OpenConnection();
        var userId = Guid.NewGuid();
        var clientScanId = Guid.NewGuid();

        await conn.ExecuteAsync(
            @"INSERT INTO scan_events (scan_event_id, user_id, client_scan_id, result_status, confidence)
              VALUES (gen_random_uuid(), @u, @c, 'NoMatch', 0.0)",
            new { u = userId, c = clientScanId });

        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                @"INSERT INTO scan_events (scan_event_id, user_id, client_scan_id, result_status, confidence)
                  VALUES (gen_random_uuid(), @u, @c, 'NoMatch', 0.0)",
                new { u = userId, c = clientScanId }));
    }

    [Fact]
    public async Task ScanEvents_AllowsSameClientScanIdForDifferentUsers()
    {
        await using var conn = OpenConnection();
        var sharedClientScanId = Guid.NewGuid();

        var ex = await Record.ExceptionAsync(async () =>
        {
            await conn.ExecuteAsync(
                @"INSERT INTO scan_events (scan_event_id, user_id, client_scan_id, result_status, confidence)
                  VALUES (gen_random_uuid(), gen_random_uuid(), @c, 'NoMatch', 0.0)",
                new { c = sharedClientScanId });
            await conn.ExecuteAsync(
                @"INSERT INTO scan_events (scan_event_id, user_id, client_scan_id, result_status, confidence)
                  VALUES (gen_random_uuid(), gen_random_uuid(), @c, 'NoMatch', 0.0)",
                new { c = sharedClientScanId });
        });

        Assert.Null(ex);
    }

    // ── scan_results_cache ────────────────────────────────────────────────

    [Fact]
    public async Task ScanResultsCache_PrimaryKeyRejectsPhashDuplicate()
    {
        await using var conn = OpenConnection();
        var userId = Guid.NewGuid();
        const long phash = unchecked((long)0xDEADBEEFCAFEBABEUL);

        await conn.ExecuteAsync(
            @"INSERT INTO scan_results_cache (user_id, phash, phash_version, result_status, confidence, expires_at)
              VALUES (@u, @p, 1, 'SafeToBuy', 0.95, now() + interval '1 hour')",
            new { u = userId, p = phash });

        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                @"INSERT INTO scan_results_cache (user_id, phash, phash_version, result_status, confidence, expires_at)
                  VALUES (@u, @p, 1, 'NoMatch', 0.1, now() + interval '1 hour')",
                new { u = userId, p = phash }));
    }

    [Fact]
    public async Task ScanResultsCache_AllowsSamePhashForDifferentPhashVersions()
    {
        await using var conn = OpenConnection();
        var userId = Guid.NewGuid();
        const long phash = unchecked((long)0xCAFEBABEDEADBEEFUL);

        var ex = await Record.ExceptionAsync(async () =>
        {
            await conn.ExecuteAsync(
                @"INSERT INTO scan_results_cache (user_id, phash, phash_version, result_status, confidence, expires_at)
                  VALUES (@u, @p, 1, 'SafeToBuy', 0.9, now() + interval '1 hour')",
                new { u = userId, p = phash });
            await conn.ExecuteAsync(
                @"INSERT INTO scan_results_cache (user_id, phash, phash_version, result_status, confidence, expires_at)
                  VALUES (@u, @p, 2, 'SafeToBuy', 0.9, now() + interval '1 hour')",
                new { u = userId, p = phash });
        });

        Assert.Null(ex);
    }

    // ── collection_audit_log ──────────────────────────────────────────────

    [Fact]
    public async Task CollectionAuditLog_RejectsUnknownOperation()
    {
        await using var conn = OpenConnection();

        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                @"INSERT INTO collection_audit_log (collection_record_id, user_id, operation)
                  VALUES (gen_random_uuid(), gen_random_uuid(), 'TRUNCATE')"));
    }

    [Theory]
    [InlineData("INSERT")]
    [InlineData("UPDATE")]
    [InlineData("DELETE")]
    public async Task CollectionAuditLog_AcceptsAllValidOperations(string operation)
    {
        await using var conn = OpenConnection();

        var ex = await Record.ExceptionAsync(() =>
            conn.ExecuteAsync(
                @"INSERT INTO collection_audit_log (collection_record_id, user_id, operation)
                  VALUES (gen_random_uuid(), gen_random_uuid(), @op)",
                new { op = operation }));

        Assert.Null(ex);
    }

    private NpgsqlConnection OpenConnection() =>
        new(_postgres.GetConnectionString());
}
