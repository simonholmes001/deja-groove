using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace DejaGroove.Api.Health;

public sealed class PostgresReadinessHealthCheck(IPostgresReadinessProbe probe) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        var result = await probe.CheckAsync(cancellationToken);
        if (result.Healthy)
        {
            return HealthCheckResult.Healthy(result.Description);
        }

        return HealthCheckResult.Unhealthy(result.Description);
    }
}
