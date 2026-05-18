using Npgsql;

namespace DejaGroove.Api.Health;

public sealed class NpgsqlPostgresReadinessProbe(IConfiguration configuration) : IPostgresReadinessProbe
{
    public async Task<PostgresReadinessResult> CheckAsync(CancellationToken cancellationToken)
    {
        var connectionString = ResolveConnectionString();
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return new PostgresReadinessResult(false, "ConnectionStrings:Postgres or ConnectionStrings:PostgresAdmin is not configured.");
        }

        try
        {
            await using var connection = new NpgsqlConnection(connectionString);
            await connection.OpenAsync(cancellationToken);

            await using var command = connection.CreateCommand();
            command.CommandText = "SELECT 1";
            await command.ExecuteScalarAsync(cancellationToken);

            return new PostgresReadinessResult(true, "PostgreSQL connection succeeded.");
        }
        catch (Exception)
        {
            return new PostgresReadinessResult(false, "PostgreSQL connection failed.");
        }
    }

    private string? ResolveConnectionString()
    {
        // Health should track the same database contract used by the app in this branch.
        // Prefer runtime connection, then fall back to admin connection used by startup migrations.
        return configuration.GetConnectionString("Postgres")
            ?? configuration.GetConnectionString("PostgresAdmin");
    }
}
