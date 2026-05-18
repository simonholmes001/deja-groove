using Dapper;
using DejaGroove.Application.Collection;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Collection;
using DejaGroove.Domain.Shared;
using Npgsql;

namespace DejaGroove.Infrastructure.Persistence.Collection;

/// <summary>
/// RLS-scoped collection persistence. The collection_records INSERT fires the
/// V007 audit trigger (issue #46) and, when supplied, the idempotency row is
/// written in the same transaction (issue #15) so a committed record can never
/// be observed without its key.
/// </summary>
public sealed class PostgresCollectionRepository(PostgresConnectionFactory factory)
    : ICollectionRepository
{
    private const string SelectColumns =
        "id, user_id, mbid, discogs_release_id, title, artist, year, notes, version, created_at, updated_at, deleted_at";

    public Task<CollectionRecord> AddAsync(
        CollectionRecord record, IdempotencyWrite? idempotency, CancellationToken ct = default) =>
        UserScope.RunAsync(factory, record.UserId, async (conn, tx) =>
        {
            try
            {
                await conn.ExecuteAsync(new CommandDefinition(
                    """
                    INSERT INTO collection_records
                        (id, user_id, mbid, discogs_release_id, title, artist, year, notes, version, created_at, updated_at)
                    VALUES
                        (@Id, @UserId, @Mbid, @Discogs, @Title, @Artist, @Year, @Notes, @Version, @CreatedAt, @UpdatedAt)
                    """,
                    new
                    {
                        record.Id,
                        record.UserId,
                        Mbid = record.Identity.Mbid,
                        Discogs = record.Identity.DiscogsReleaseId,
                        Title = record.Identity.Title,
                        Artist = record.Identity.Artist,
                        Year = (short?)record.Identity.Year,
                        record.Notes,
                        record.Version,
                        record.CreatedAt,
                        record.UpdatedAt
                    }, tx, cancellationToken: ct));

                if (idempotency is not null)
                {
                    await conn.ExecuteAsync(new CommandDefinition(
                        """
                        INSERT INTO collection_idempotency_keys
                            (user_id, idempotency_key, request_fingerprint, collection_record_id)
                        VALUES (@UserId, @Key, @Fingerprint, @RecordId)
                        """,
                        new
                        {
                            record.UserId,
                            idempotency.Key,
                            idempotency.Fingerprint,
                            RecordId = record.Id
                        }, tx, cancellationToken: ct));
                }

                return record;
            }
            catch (PostgresException ex) when (ex.SqlState == "23505" &&
                                               ex.ConstraintName?.StartsWith("ux_collection_records") == true)
            {
                throw new DuplicateCollectionRecordException(
                    $"Collection record violates {ex.ConstraintName}.");
            }
        }, ct);

    public Task<CollectionRecord?> FindActiveByIdentityAsync(
        Guid userId, AlbumIdentity identity, CancellationToken ct = default) =>
        UserScope.RunAsync(factory, userId, async (conn, tx) =>
        {
            var (predicate, parameters) = IdentityPredicate(identity);
            var row = await conn.QuerySingleOrDefaultAsync<Row>(new CommandDefinition(
                $"SELECT {SelectColumns} FROM collection_records " +
                $"WHERE user_id = @userId AND deleted_at IS NULL AND {predicate} LIMIT 1",
                Merge(parameters, new { userId }), tx, cancellationToken: ct));
            return row?.ToDomain();
        }, ct);

    public Task<CollectionRecord?> GetByIdAsync(Guid userId, Guid id, CancellationToken ct = default) =>
        GetByIdAsync(userId, id, activeOnly: true, ct);

    public Task<CollectionRecord?> GetByIdIncludingDeletedAsync(
        Guid userId, Guid id, CancellationToken ct = default) =>
        GetByIdAsync(userId, id, activeOnly: false, ct);

    private Task<CollectionRecord?> GetByIdAsync(
        Guid userId, Guid id, bool activeOnly, CancellationToken ct) =>
        UserScope.RunAsync(factory, userId, async (conn, tx) =>
        {
            var sql = $"SELECT {SelectColumns} FROM collection_records " +
                      "WHERE user_id = @userId AND id = @id" +
                      (activeOnly ? " AND deleted_at IS NULL" : "");
            var row = await conn.QuerySingleOrDefaultAsync<Row>(new CommandDefinition(
                sql, new { userId, id }, tx, cancellationToken: ct));
            return row?.ToDomain();
        }, ct);

    public Task<CollectionPage> ListAsync(CollectionQuery query, CancellationToken ct = default) =>
        UserScope.RunAsync(factory, query.UserId, async (conn, tx) =>
        {
            var ascending = query.SortDirection == SortDirection.Ascending;
            var comparison = ascending ? ">" : "<";
            var order = ascending ? "ASC" : "DESC";

            // CreatedAt sorts purely on the (created_at, id) tie-breaker. For
            // Title/Artist the case-folded column leads, with (created_at, id)
            // as the deterministic keyset tail. A bare constant cannot appear
            // in ORDER BY, so the two cases use distinct column lists.
            var hasPrimary = query.SortField != CollectionSortField.CreatedAt;
            var sortExpr = SortExpression(query.SortField);
            var orderBy = hasPrimary
                ? $"{sortExpr} {order}, created_at {order}, id {order}"
                : $"created_at {order}, id {order}";
            var keyset = hasPrimary
                ? $"({sortExpr}, created_at, id) {comparison} (@CursorSortKey, @CursorCreatedAt, @CursorId)"
                : $"(created_at, id) {comparison} (@CursorCreatedAt, @CursorId)";

            // A cursor minted under a different sort field cannot define a
            // valid boundary for this ordering — ignore it and start fresh.
            var cursor = query.Cursor is { } c && c.Field == query.SortField ? c : null;

            var sql =
                $"SELECT {SelectColumns}, {sortExpr} AS sort_key FROM collection_records " +
                "WHERE user_id = @UserId AND deleted_at IS NULL ";

            if (!string.IsNullOrWhiteSpace(query.Search))
                sql += "AND (title ILIKE @SearchLike OR artist ILIKE @SearchLike) ";
            if (!string.IsNullOrWhiteSpace(query.Format))
                sql += "AND format = @Format ";
            if (cursor is not null)
                sql += $"AND {keyset} ";

            sql += $"ORDER BY {orderBy} LIMIT @Take";

            var rows = (await conn.QueryAsync<Row>(new CommandDefinition(sql, new
            {
                query.UserId,
                SearchLike = $"%{query.Search}%",
                query.Format,
                CursorSortKey = cursor?.SortKey,
                CursorCreatedAt = cursor?.CreatedAt,
                CursorId = cursor?.Id,
                Take = query.Limit + 1
            }, tx, cancellationToken: ct))).ToList();

            string? nextCursor = null;
            if (rows.Count > query.Limit)
            {
                var last = rows[query.Limit - 1];
                nextCursor = new CollectionCursor(
                    query.SortField, last.sort_key ?? "", last.created_at, last.id).Encode();
                rows = rows.Take(query.Limit).ToList();
            }

            return new CollectionPage(rows.Select(r => r.ToDomain()).ToList(), nextCursor);
        }, ct);

    // Constant for CreatedAt so the (sort_key, created_at, id) keyset
    // degenerates cleanly to (created_at, id). upper(...) matches the
    // case-insensitive AlbumIdentity comparison and the V012 unique index.
    private static string SortExpression(CollectionSortField field) => field switch
    {
        CollectionSortField.Title => "coalesce(upper(title), '')",
        CollectionSortField.Artist => "coalesce(upper(artist), '')",
        _ => "''"
    };

    private static (string Predicate, object Parameters) IdentityPredicate(AlbumIdentity identity)
    {
        if (identity.Mbid is not null)
            return ("mbid = @mbid", new { mbid = identity.Mbid });
        if (identity.DiscogsReleaseId is not null)
            return ("discogs_release_id = @discogs", new { discogs = identity.DiscogsReleaseId });
        return ("upper(title) = upper(@title) AND upper(artist) = upper(@artist)",
            new { title = identity.Title, artist = identity.Artist });
    }

    private static DynamicParameters Merge(object a, object b)
    {
        var p = new DynamicParameters();
        p.AddDynamicParams(a);
        p.AddDynamicParams(b);
        return p;
    }

    // ReSharper disable InconsistentNaming — column names mirror the schema.
    private sealed class Row
    {
        public Guid id { get; init; }
        public Guid user_id { get; init; }
        public string? mbid { get; init; }
        public string? discogs_release_id { get; init; }
        public string? title { get; init; }
        public string? artist { get; init; }
        public short? year { get; init; }
        public string? notes { get; init; }
        public int version { get; init; }
        public DateTimeOffset created_at { get; init; }
        public DateTimeOffset updated_at { get; init; }
        public DateTimeOffset? deleted_at { get; init; }
        public string? sort_key { get; init; }

        public CollectionRecord ToDomain() => CollectionRecord.Rehydrate(
            id, user_id,
            AlbumIdentity.Create(mbid, discogs_release_id, title, artist, year),
            notes, version, created_at, updated_at, deleted_at);
    }
}
