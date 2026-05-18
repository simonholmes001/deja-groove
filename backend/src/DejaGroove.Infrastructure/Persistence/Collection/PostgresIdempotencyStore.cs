using Dapper;
using DejaGroove.Application.Ports;

namespace DejaGroove.Infrastructure.Persistence.Collection;

/// <summary>RLS-scoped read access to a user's idempotency-key bindings.</summary>
public sealed class PostgresIdempotencyStore(PostgresConnectionFactory factory)
    : IIdempotencyStore
{
    public Task<IdempotencyRecord?> TryGetAsync(
        Guid userId, string key, CancellationToken ct = default) =>
        UserScope.RunAsync(factory, userId, async (conn, tx) =>
        {
            var row = await conn.QuerySingleOrDefaultAsync<Row>(new CommandDefinition(
                """
                SELECT idempotency_key, request_fingerprint, collection_record_id
                FROM collection_idempotency_keys
                WHERE user_id = @userId AND idempotency_key = @key
                """,
                new { userId, key }, tx, cancellationToken: ct));

            return row is null
                ? null
                : new IdempotencyRecord(row.idempotency_key, row.request_fingerprint, row.collection_record_id);
        }, ct);

    // ReSharper disable InconsistentNaming — column names mirror the schema.
    private sealed class Row
    {
        public string idempotency_key { get; init; } = string.Empty;
        public string request_fingerprint { get; init; } = string.Empty;
        public Guid collection_record_id { get; init; }
    }
}
