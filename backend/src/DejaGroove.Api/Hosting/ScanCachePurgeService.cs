using DejaGroove.Application.Ports;

namespace DejaGroove.Api.Hosting;

/// <summary>
/// Periodically evicts expired pHash cache rows (issue #79). PostgreSQL has no
/// TTL, and there is no Redis, so eviction is an in-process sweep on a cheap
/// indexed predicate. Failures are logged and retried on the next tick — a
/// stale row is harmless until its expires_at is honoured by the read path.
/// </summary>
public sealed class ScanCachePurgeService(
    IServiceProvider services,
    ILogger<ScanCachePurgeService> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromHours(1);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(Interval);
        do
        {
            try
            {
                using var scope = services.CreateScope();
                var maintenance = scope.ServiceProvider.GetRequiredService<IScanCacheMaintenance>();
                var purged = await maintenance.PurgeExpiredAsync(stoppingToken);
                if (purged > 0)
                    logger.LogInformation("Purged {Count} expired scan cache rows.", purged);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break;
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "Scan cache purge sweep failed; retrying next interval.");
            }
        } while (await timer.WaitForNextTickAsync(stoppingToken));
    }
}
