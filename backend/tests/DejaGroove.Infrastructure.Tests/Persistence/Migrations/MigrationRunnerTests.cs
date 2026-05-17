using Dapper;
using DejaGroove.Infrastructure.Persistence.Migrations;
using Microsoft.Extensions.Logging.Abstractions;
using Npgsql;
using Testcontainers.PostgreSql;

namespace DejaGroove.Infrastructure.Tests.Persistence.Migrations;

/// <summary>
/// Verifies that MigrationRunner applies all scripts and is idempotent.
/// Uses a single shared container to avoid Docker startup overhead per test.
/// </summary>
[Trait("Category", "Integration")]
public sealed class MigrationRunnerTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    public Task InitializeAsync() => _postgres.StartAsync();
    public Task DisposeAsync() => _postgres.DisposeAsync().AsTask();

    [Fact]
    public async Task ApplyAsync_OnFreshDatabase_CreatesAllExpectedTables()
    {
        var runner = new MigrationRunner(
            _postgres.GetConnectionString(),
            NullLogger<MigrationRunner>.Instance);

        await runner.ApplyAsync();

        var missing = new List<string>();
        foreach (var table in new[] { "collection_records", "scan_events", "scan_results_cache", "collection_audit_log" })
        {
            if (!await TableExistsAsync(table))
                missing.Add(table);
        }

        Assert.Empty(missing);
    }

    [Fact]
    public async Task ApplyAsync_CalledTwice_IsIdempotent()
    {
        var runner = new MigrationRunner(
            _postgres.GetConnectionString(),
            NullLogger<MigrationRunner>.Instance);

        await runner.ApplyAsync();
        var ex = await Record.ExceptionAsync(() => runner.ApplyAsync());

        Assert.Null(ex);
    }

    [Fact]
    public void Constructor_NullConnectionString_Throws()
    {
        Assert.Throws<ArgumentNullException>(() =>
            new MigrationRunner(null!, NullLogger<MigrationRunner>.Instance));
    }

    [Fact]
    public void Constructor_WhitespaceConnectionString_Throws()
    {
        Assert.Throws<ArgumentException>(() =>
            new MigrationRunner("   ", NullLogger<MigrationRunner>.Instance));
    }

    private async Task<bool> TableExistsAsync(string tableName)
    {
        await using var conn = new NpgsqlConnection(_postgres.GetConnectionString());
        return await conn.ExecuteScalarAsync<bool>(
            "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = @name)",
            new { name = tableName });
    }
}
