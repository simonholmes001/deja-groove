namespace DejaGroove.Api.Health;

public interface IPostgresReadinessProbe
{
    Task<PostgresReadinessResult> CheckAsync(CancellationToken cancellationToken);
}

public sealed record PostgresReadinessResult(bool Healthy, string Description);
