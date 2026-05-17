using DbUp;

namespace DejaGroove.Infrastructure.Persistence.Migrations;

public sealed class MigrationRunner
{
    private readonly string _connectionString;

    public MigrationRunner(string connectionString)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString);
        _connectionString = connectionString;
    }

    public Task ApplyAsync(CancellationToken _ = default)
    {
        var upgrader = DeployChanges.To
            .PostgresqlDatabase(_connectionString)
            .WithScriptsEmbeddedInAssembly(
                typeof(MigrationRunner).Assembly,
                name => name.Contains(".Scripts."))
            .WithTransactionPerScript()
            .LogToConsole()
            .Build();

        var result = upgrader.PerformUpgrade();

        if (!result.Successful)
            throw new InvalidOperationException(
                $"Migration failed at '{result.ErrorScript?.Name}': {result.Error?.Message}",
                result.Error);

        return Task.CompletedTask;
    }
}
