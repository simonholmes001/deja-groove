using DbUp;
using DbUp.Engine.Output;
using Microsoft.Extensions.Logging;
using Npgsql;
using Polly;
using Polly.Retry;

namespace DejaGroove.Infrastructure.Persistence.Migrations;

public sealed class MigrationRunner
{
    private readonly string _connectionString;
    private readonly ILogger<MigrationRunner> _logger;

    public MigrationRunner(string connectionString, ILogger<MigrationRunner> logger)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(connectionString);
        _connectionString = connectionString;
        _logger = logger;
    }

    public async Task ApplyAsync(CancellationToken cancellationToken = default)
    {
        var retryPipeline = new ResiliencePipelineBuilder()
            .AddRetry(new RetryStrategyOptions
            {
                ShouldHandle = new PredicateBuilder().Handle<NpgsqlException>(),
                MaxRetryAttempts = 4,
                Delay = TimeSpan.FromSeconds(2),
                BackoffType = DelayBackoffType.Exponential,
                UseJitter = true,
                OnRetry = args =>
                {
                    _logger.LogWarning(
                        args.Outcome.Exception,
                        "Database not ready, retrying migration (attempt {Attempt} of 4)",
                        args.AttemptNumber + 1);
                    return ValueTask.CompletedTask;
                }
            })
            .Build();

        await retryPipeline.ExecuteAsync(async ct =>
        {
            var upgrader = DeployChanges.To
                .PostgresqlDatabase(_connectionString)
                .WithScriptsEmbeddedInAssembly(
                    typeof(MigrationRunner).Assembly,
                    name => name.Contains(".Scripts."))
                .WithTransactionPerScript()
                .LogTo(new MsLogAdapter(_logger))
                .Build();

            var result = await Task.Run(() => upgrader.PerformUpgrade(), ct);

            if (!result.Successful)
                throw new InvalidOperationException(
                    $"Migration failed at '{result.ErrorScript?.Name}': {result.Error?.Message}",
                    result.Error);

            _logger.LogInformation(
                "Database migration complete — {Count} script(s) applied",
                result.Scripts.Count());

        }, cancellationToken);
    }
}

/// <summary>Routes DbUp log output through the application's structured logger.</summary>
internal sealed class MsLogAdapter : IUpgradeLog
{
    private readonly ILogger _logger;

    public MsLogAdapter(ILogger logger) => _logger = logger;

    public void WriteInformation(string format, params object[] args) =>
        _logger.LogInformation(format, args);

    public void WriteWarning(string format, params object[] args) =>
        _logger.LogWarning(format, args);

    public void WriteError(string format, params object[] args) =>
        _logger.LogError(format, args);
}
