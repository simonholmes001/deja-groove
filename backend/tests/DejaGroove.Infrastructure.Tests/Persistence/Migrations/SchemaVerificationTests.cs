using Dapper;
using DejaGroove.Infrastructure.Persistence.Migrations;
using Microsoft.Extensions.Logging.Abstractions;
using Npgsql;
using Testcontainers.PostgreSql;

namespace DejaGroove.Infrastructure.Tests.Persistence.Migrations;

/// <summary>
/// Verifies that the migrated schema enforces the domain invariants expressed
/// in AlbumIdentity, ScanStatus, and the audit operation enumeration.
/// Runs against a real PostgreSQL 16 instance via Testcontainers.
/// </summary>
[Trait("Category", "Integration")]
public sealed class SchemaVerificationTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
        await new MigrationRunner(
            _postgres.GetConnectionString(),
            NullLogger<MigrationRunner>.Instance).ApplyAsync();
    }

    public Task DisposeAsync() => _postgres.DisposeAsync().AsTask();

    // ── collection_records ────────────────────────────────────────────────

    [Fact]
    public async Task CollectionRecords_RejectsRowWithNoIdentityFields()
    {
        await using var conn = CreateConnection();

        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                "INSERT INTO collection_records (user_id, title) VALUES (gen_random_uuid(), 'Orphan Album')"));
    }

    [Fact]
    public async Task CollectionRecords_AcceptsRowWithMbidOnly()
    {
        await using var conn = CreateConnection();

        var ex = await Record.ExceptionAsync(() =>
            conn.ExecuteAsync(
                "INSERT INTO collection_records (user_id, mbid) VALUES (gen_random_uuid(), 'abc-123-mbid')"));

        Assert.Null(ex);
    }

    [Fact]
    public async Task CollectionRecords_AcceptsRowWithDiscogsReleaseIdOnly()
    {
        await using var conn = CreateConnection();

        var ex = await Record.ExceptionAsync(() =>
            conn.ExecuteAsync(
                "INSERT INTO collection_records (user_id, discogs_release_id) VALUES (gen_random_uuid(), 'D-7654321')"));

        Assert.Null(ex);
    }

    [Fact]
    public async Task CollectionRecords_AcceptsRowWithTitleAndArtist()
    {
        await using var conn = CreateConnection();

        var ex = await Record.ExceptionAsync(() =>
            conn.ExecuteAsync(
                "INSERT INTO collection_records (user_id, title, artist) VALUES (gen_random_uuid(), 'Kind of Blue', 'Miles Davis')"));

        Assert.Null(ex);
    }

    [Fact]
    public async Task CollectionRecords_EnforcesUniqueActiveMbidPerUser()
    {
        await using var conn = CreateConnection();
        var userId = Guid.NewGuid();

        await conn.ExecuteAsync(
            "INSERT INTO collection_records (user_id, mbid) VALUES (@u, 'dup-mbid-test')",
            new { u = userId });

        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                "INSERT INTO collection_records (user_id, mbid) VALUES (@u, 'dup-mbid-test')",
                new { u = userId }));
    }

    [Fact]
    public async Task CollectionRecords_AllowsSameMbidAfterSoftDelete()
    {
        // The partial unique index excludes soft-deleted rows, so re-buying a
        // deleted record must be permitted.
        await using var conn = CreateConnection();
        var userId = Guid.NewGuid();

        await conn.ExecuteAsync(
            "INSERT INTO collection_records (user_id, mbid) VALUES (@u, 'soft-del-mbid')",
            new { u = userId });

        await conn.ExecuteAsync(
            "UPDATE collection_records SET deleted_at = now() WHERE user_id = @u AND mbid = 'soft-del-mbid'",
            new { u = userId });

        var ex = await Record.ExceptionAsync(() =>
            conn.ExecuteAsync(
                "INSERT INTO collection_records (user_id, mbid) VALUES (@u, 'soft-del-mbid')",
                new { u = userId }));

        Assert.Null(ex);
    }

    [Fact]
    public async Task CollectionRecords_DefaultsVersionToOne()
    {
        await using var conn = CreateConnection();

        await conn.ExecuteAsync(
            "INSERT INTO collection_records (user_id, mbid) VALUES (gen_random_uuid(), 'version-default-check')");

        var version = await conn.ExecuteScalarAsync<int>(
            "SELECT version FROM collection_records WHERE mbid = 'version-default-check'");

        Assert.Equal(1, version);
    }

    [Fact]
    public async Task CollectionRecords_RejectsYearBelowPlausibleMinimum()
    {
        await using var conn = CreateConnection();

        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                "INSERT INTO collection_records (user_id, mbid, year) VALUES (gen_random_uuid(), 'bad-year', 1700)"));
    }

    [Fact]
    public async Task CollectionRecords_RejectsYearAboveFarFutureSentinel()
    {
        await using var conn = CreateConnection();

        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                "INSERT INTO collection_records (user_id, mbid, year) VALUES (gen_random_uuid(), 'future-year', 2101)"));
    }

    // ── scan_events ───────────────────────────────────────────────────────

    [Fact]
    public async Task ScanEvents_RejectsUnknownResultStatus()
    {
        await using var conn = CreateConnection();

        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                @"INSERT INTO scan_events (user_id, client_scan_id, result_status, confidence)
                  VALUES (gen_random_uuid(), gen_random_uuid(), 'InvalidStatus', 0.9)"));
    }

    [Theory]
    [InlineData("Owned")]
    [InlineData("SafeToBuy")]
    [InlineData("Ambiguous")]
    [InlineData("NoMatch")]
    public async Task ScanEvents_AcceptsAllDomainResultStatuses(string status)
    {
        await using var conn = CreateConnection();

        var ex = await Record.ExceptionAsync(() =>
            conn.ExecuteAsync(
                @"INSERT INTO scan_events (user_id, client_scan_id, result_status, confidence)
                  VALUES (gen_random_uuid(), gen_random_uuid(), @status, 0.8)",
                new { status }));

        Assert.Null(ex);
    }

    [Fact]
    public async Task ScanEvents_EnforcesUniqueClientScanIdPerUser()
    {
        await using var conn = CreateConnection();
        var userId = Guid.NewGuid();
        var clientScanId = Guid.NewGuid();

        await conn.ExecuteAsync(
            @"INSERT INTO scan_events (user_id, client_scan_id, result_status, confidence)
              VALUES (@u, @c, 'NoMatch', 0.0)",
            new { u = userId, c = clientScanId });

        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                @"INSERT INTO scan_events (user_id, client_scan_id, result_status, confidence)
                  VALUES (@u, @c, 'NoMatch', 0.0)",
                new { u = userId, c = clientScanId }));
    }

    [Fact]
    public async Task ScanEvents_AllowsSameClientScanIdForDifferentUsers()
    {
        await using var conn = CreateConnection();
        var sharedClientScanId = Guid.NewGuid();

        var ex = await Record.ExceptionAsync(async () =>
        {
            await conn.ExecuteAsync(
                @"INSERT INTO scan_events (user_id, client_scan_id, result_status, confidence)
                  VALUES (gen_random_uuid(), @c, 'NoMatch', 0.0)",
                new { c = sharedClientScanId });
            await conn.ExecuteAsync(
                @"INSERT INTO scan_events (user_id, client_scan_id, result_status, confidence)
                  VALUES (gen_random_uuid(), @c, 'NoMatch', 0.0)",
                new { c = sharedClientScanId });
        });

        Assert.Null(ex);
    }

    [Fact]
    public async Task ScanEvents_RejectsYearBelowPlausibleMinimum()
    {
        await using var conn = CreateConnection();

        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                @"INSERT INTO scan_events (user_id, client_scan_id, result_status, confidence, year)
                  VALUES (gen_random_uuid(), gen_random_uuid(), 'NoMatch', 0.0, 1200)"));
    }

    [Fact]
    public async Task ScanEvents_RejectsYearAboveFarFutureSentinel()
    {
        await using var conn = CreateConnection();

        await Assert.ThrowsAsync<PostgresException>(() =>
            conn.ExecuteAsync(
                @"INSERT INTO scan_events (user_id, client_scan_id, result_status, confidence, year)
                  VALUES (gen_random_uuid(), gen_random_uuid(), 'NoMatch', 0.0, 2101)"));
    }

    // ── scan_results_cache ────────────────────────────────────────────────

    [Fact]
    public async Task ScanResultsCache_PrimaryKeyRejectsPhashDuplicate()
    {
        await using var conn = CreateConnection();
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
        await using var conn = CreateConnection();
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

    [Fact]
    public async Task ScanResultsCache_ExpiresAtIndexExists()
    {
        await using var conn = CreateConnection();

        var indexExists = await conn.ExecuteScalarAsync<bool>(
            @"SELECT EXISTS(
                SELECT 1 FROM pg_indexes
                WHERE tablename = 'scan_results_cache'
                AND indexname = 'ix_scan_results_cache_expires_at')");

        Assert.True(indexExists);
    }

    // ── collection_audit_log ──────────────────────────────────────────────

    [Fact]
    public async Task CollectionAuditLog_RejectsUnknownOperation()
    {
        await using var conn = CreateConnection();

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
        await using var conn = CreateConnection();

        var ex = await Record.ExceptionAsync(() =>
            conn.ExecuteAsync(
                @"INSERT INTO collection_audit_log (collection_record_id, user_id, operation)
                  VALUES (gen_random_uuid(), gen_random_uuid(), @op)",
                new { op = operation }));

        Assert.Null(ex);
    }

    // ── Row-Level Security ────────────────────────────────────────────────

    [Theory]
    [InlineData("collection_records")]
    [InlineData("scan_events")]
    [InlineData("scan_results_cache")]
    [InlineData("collection_audit_log")]
    [InlineData("scan_request_status")]
    [InlineData("scan_ambiguities")]
    [InlineData("scan_ambiguity_candidates")]
    [InlineData("scan_resolutions")]
    [InlineData("scan_resolution_audit_log")]
    public async Task AllApplicationTables_HaveRowLevelSecurityEnabled(string tableName)
    {
        await using var conn = CreateConnection();

        var rlsEnabled = await conn.ExecuteScalarAsync<bool>(
            "SELECT rowsecurity FROM pg_tables WHERE tablename = @name AND schemaname = 'public'",
            new { name = tableName });

        Assert.True(rlsEnabled, $"RLS not enabled on {tableName}");
    }

    [Theory]
    [InlineData("collection_records",   "rls_collection_records")]
    [InlineData("scan_events",          "rls_scan_events")]
    [InlineData("scan_results_cache",   "rls_scan_results_cache")]
    [InlineData("collection_audit_log", "rls_collection_audit_log")]
    [InlineData("scan_request_status", "rls_scan_request_status")]
    [InlineData("scan_ambiguities", "rls_scan_ambiguities")]
    [InlineData("scan_ambiguity_candidates", "rls_scan_ambiguity_candidates")]
    [InlineData("scan_resolutions", "rls_scan_resolutions")]
    [InlineData("scan_resolution_audit_log", "rls_scan_resolution_audit_log")]
    public async Task AllApplicationTables_HaveRlsPolicy(string tableName, string policyName)
    {
        await using var conn = CreateConnection();

        var policyExists = await conn.ExecuteScalarAsync<bool>(
            @"SELECT EXISTS(
                SELECT 1 FROM pg_policies
                WHERE tablename = @table AND policyname = @policy AND schemaname = 'public')",
            new { table = tableName, policy = policyName });

        Assert.True(policyExists, $"RLS policy '{policyName}' not found on {tableName}");
    }

    // ── GDPR purge function ───────────────────────────────────────────────

    [Fact]
    public async Task PurgeUserFunction_Exists()
    {
        await using var conn = CreateConnection();

        var exists = await conn.ExecuteScalarAsync<bool>(
            @"SELECT EXISTS(
                SELECT 1 FROM pg_proc p
                JOIN pg_namespace n ON n.oid = p.pronamespace
                WHERE p.proname = 'purge_user' AND n.nspname = 'public')");

        Assert.True(exists);
    }

    [Fact]
    public async Task PurgeUserFunction_GrantsExecuteToDejaApp()
    {
        await using var conn = CreateConnection();

        var hasExecute = await conn.ExecuteScalarAsync<bool>(
            "SELECT has_function_privilege('deja_app', 'public.purge_user(uuid)', 'EXECUTE')");

        Assert.True(hasExecute);
    }

    [Fact]
    public async Task PurgeUserFunction_DeletesAllRowsForUser()
    {
        await using var conn = CreateConnection();
        var userId = Guid.NewGuid();

        // Seed data across all tables
        await conn.ExecuteAsync(
            "INSERT INTO collection_records (user_id, mbid) VALUES (@u, 'purge-test-mbid')",
            new { u = userId });

        await conn.ExecuteAsync(
            @"INSERT INTO scan_events (user_id, client_scan_id, result_status, confidence)
              VALUES (@u, gen_random_uuid(), 'NoMatch', 0.0)",
            new { u = userId });

        await conn.ExecuteAsync(
            @"INSERT INTO scan_results_cache (user_id, phash, result_status, confidence, expires_at)
              VALUES (@u, 12345, 'NoMatch', 0.0, now() + interval '1 hour')",
            new { u = userId });

        await conn.ExecuteAsync(
            "INSERT INTO collection_audit_log (collection_record_id, user_id, operation) VALUES (gen_random_uuid(), @u, 'INSERT')",
            new { u = userId });
        await conn.ExecuteAsync(
            "INSERT INTO scan_request_status (user_id, request_id, result_status) VALUES (@u, gen_random_uuid(), 'Ambiguous')",
            new { u = userId });
        await conn.ExecuteAsync(
            @"WITH req AS (
                SELECT gen_random_uuid() AS request_id
            )
            INSERT INTO scan_ambiguities (user_id, request_id, confidence)
            SELECT @u, request_id, 0.7 FROM req",
            new { u = userId });
        await conn.ExecuteAsync(
            @"INSERT INTO scan_resolution_audit_log (user_id, request_id, selected_mbid)
              VALUES (@u, gen_random_uuid(), 'audit-mbid')",
            new { u = userId });

        // Execute purge
        await conn.ExecuteAsync("SELECT purge_user(@u)", new { u = userId });

        // All rows must be gone
        var counts = new[]
        {
            await conn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM collection_records WHERE user_id = @u", new { u = userId }),
            await conn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM scan_events WHERE user_id = @u", new { u = userId }),
            await conn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM scan_results_cache WHERE user_id = @u", new { u = userId }),
            await conn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM collection_audit_log WHERE user_id = @u", new { u = userId }),
            await conn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM scan_request_status WHERE user_id = @u", new { u = userId }),
            await conn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM scan_ambiguities WHERE user_id = @u", new { u = userId }),
            await conn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM scan_ambiguity_candidates WHERE user_id = @u", new { u = userId }),
            await conn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM scan_resolutions WHERE user_id = @u", new { u = userId }),
            await conn.ExecuteScalarAsync<int>("SELECT COUNT(*) FROM scan_resolution_audit_log WHERE user_id = @u", new { u = userId }),
        };

        Assert.All(counts, c => Assert.Equal(0, c));
    }

    private NpgsqlConnection CreateConnection() =>
        new(_postgres.GetConnectionString());
}
