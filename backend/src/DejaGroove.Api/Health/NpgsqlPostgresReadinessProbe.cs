using Npgsql;

namespace DejaGroove.Api.Health;

public sealed class NpgsqlPostgresReadinessProbe(IConfiguration configuration) : IPostgresReadinessProbe
{
    public async Task<PostgresReadinessResult> CheckAsync(CancellationToken cancellationToken)
    {
        var connectionString = configuration.GetConnectionString("Postgres");
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return new PostgresReadinessResult(false, "ConnectionStrings:Postgres is not configured.");
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
}
