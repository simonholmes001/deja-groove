using DejaGroove.Infrastructure.Persistence;
using DejaGroove.Infrastructure.Persistence.Migrations;
using Microsoft.Extensions.Logging.Abstractions;
using Testcontainers.PostgreSql;

namespace DejaGroove.Infrastructure.Tests.Persistence;

/// <summary>
/// One migrated PostgreSQL 16 container shared by the collection-domain
/// integration tests. Each test isolates itself with fresh user ids rather
/// than a fresh schema, so a single container keeps the suite fast.
/// </summary>
public sealed class PostgresFixture : IAsyncLifetime
{
    private readonly PostgreSqlContainer _postgres = new PostgreSqlBuilder()
        .WithImage("postgres:16-alpine")
        .Build();

    public string ConnectionString => _postgres.GetConnectionString();
    public PostgresConnectionFactory Factory => new(ConnectionString);

    public async Task InitializeAsync()
    {
        await _postgres.StartAsync();
        await new MigrationRunner(ConnectionString, NullLogger<MigrationRunner>.Instance)
            .ApplyAsync();
    }

    public Task DisposeAsync() => _postgres.DisposeAsync().AsTask();
}

[CollectionDefinition("postgres")]
public sealed class PostgresCollection : ICollectionFixture<PostgresFixture>;
