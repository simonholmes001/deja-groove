using Dapper;
using DejaGroove.Infrastructure.Persistence.Migrations;
using Npgsql;
using Testcontainers.PostgreSql;

namespace DejaGroove.Infrastructure.Tests.Persistence.Migrations;

public sealed class MigrationRunnerTests : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    public Task InitializeAsync() => _postgres.StartAsync();
    public Task DisposeAsync() => _postgres.DisposeAsync().AsTask();

    [Fact]
    public async Task ApplyAsync_OnFreshDatabase_CreatesCollectionRecordsTable()
    {
        var runner = new MigrationRunner(_postgres.GetConnectionString());

        await runner.ApplyAsync();

        Assert.True(await TableExistsAsync("collection_records"));
    }

    [Fact]
    public async Task ApplyAsync_OnFreshDatabase_CreatesScanEventsTable()
    {
        var runner = new MigrationRunner(_postgres.GetConnectionString());

        await runner.ApplyAsync();

        Assert.True(await TableExistsAsync("scan_events"));
    }

    [Fact]
    public async Task ApplyAsync_OnFreshDatabase_CreatesScanResultsCacheTable()
    {
        var runner = new MigrationRunner(_postgres.GetConnectionString());

        await runner.ApplyAsync();

        Assert.True(await TableExistsAsync("scan_results_cache"));
    }

    [Fact]
    public async Task ApplyAsync_OnFreshDatabase_CreatesCollectionAuditLogTable()
    {
        var runner = new MigrationRunner(_postgres.GetConnectionString());

        await runner.ApplyAsync();

        Assert.True(await TableExistsAsync("collection_audit_log"));
    }

    [Fact]
    public async Task ApplyAsync_CalledTwice_IsIdempotent()
    {
        var runner = new MigrationRunner(_postgres.GetConnectionString());
        await runner.ApplyAsync();

        var ex = await Record.ExceptionAsync(() => runner.ApplyAsync());

        Assert.Null(ex);
    }

    private async Task<bool> TableExistsAsync(string tableName)
    {
        await using var conn = new NpgsqlConnection(_postgres.GetConnectionString());
        return await conn.ExecuteScalarAsync<bool>(
            "SELECT EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = @name)",
            new { name = tableName });
    }
}
