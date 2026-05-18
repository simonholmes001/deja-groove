using Dapper;
using Npgsql;

namespace DejaGroove.Infrastructure.Persistence;

/// <summary>Opens runtime connections using the least-privilege application
/// login (ConnectionStrings:Postgres).</summary>
public sealed class PostgresConnectionFactory(string connectionString)
{
    private readonly string _connectionString =
        !string.IsNullOrWhiteSpace(connectionString)
            ? connectionString
            : throw new ArgumentException("Connection string is required.", nameof(connectionString));

    public async Task<NpgsqlConnection> OpenAsync(CancellationToken ct = default)
    {
        var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(ct);
        return connection;
    }
}

/// <summary>
/// Runs work inside a transaction scoped to one user. Every statement executes
/// as the <c>deja_app</c> role with <c>app.current_user_id</c> set, so the
/// Row-Level-Security policies (V005/V009) constrain all DML to that user's
/// rows. Both settings are transaction-local and cannot leak across requests.
/// </summary>
public static class UserScope
{
    public static async Task<T> RunAsync<T>(
        PostgresConnectionFactory factory,
        Guid userId,
        Func<NpgsqlConnection, NpgsqlTransaction, Task<T>> work,
        CancellationToken ct = default)
    {
        if (userId == Guid.Empty)
            throw new ArgumentException("userId must not be empty.", nameof(userId));

        await using var connection = await factory.OpenAsync(ct);
        await using var tx = await connection.BeginTransactionAsync(ct);

        // Role name cannot be a bind parameter; it is a fixed trusted literal.
        await connection.ExecuteAsync(new CommandDefinition(
            "SET LOCAL ROLE deja_app", transaction: tx, cancellationToken: ct));
        await connection.ExecuteAsync(new CommandDefinition(
            "SELECT set_config('app.current_user_id', @uid, true)",
            new { uid = userId.ToString() }, tx, cancellationToken: ct));

        var result = await work(connection, tx);
        await tx.CommitAsync(ct);
        return result;
    }
}
