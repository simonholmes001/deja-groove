using Dapper;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Infrastructure.Persistence.Scanning;

public sealed class PostgresCollectionOwnershipPort(PostgresConnectionFactory factory) : ICollectionOwnershipPort
{
    public Task<(bool IsOwned, Guid? CollectionRecordId)> CheckAsync(
        Guid userId,
        AlbumIdentity identity,
        CancellationToken ct = default) =>
        UserScope.RunAsync(factory, userId, async (conn, tx) =>
        {
            var (predicate, parameters) = IdentityPredicate(identity);
            var id = await conn.QuerySingleOrDefaultAsync<Guid?>(new CommandDefinition(
                $"SELECT id FROM collection_records WHERE user_id = @userId AND deleted_at IS NULL AND {predicate} LIMIT 1",
                Merge(parameters, new { userId }),
                tx,
                cancellationToken: ct));

            return (id.HasValue, id);
        }, ct);

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
}

public sealed class PostgresScanEventRepository(PostgresConnectionFactory factory) : IScanEventRepository
{
    public Task AppendAsync(ScanEvent scanEvent, CancellationToken ct = default) =>
        UserScope.RunAsync(factory, scanEvent.UserId, async (conn, tx) =>
        {
            await conn.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO scan_events
                    (scan_event_id, user_id, client_scan_id, result_status, confidence,
                     mbid, discogs_release_id, title, artist, year, captured_at, created_at)
                VALUES
                    (@ScanEventId, @UserId, @ClientScanId, @ResultStatus, @Confidence,
                     @Mbid, @DiscogsReleaseId, @Title, @Artist, @Year, @CapturedAt, @CreatedAt)
                ON CONFLICT (user_id, client_scan_id) DO NOTHING
                """,
                new
                {
                    scanEvent.ScanEventId,
                    scanEvent.UserId,
                    scanEvent.ClientScanId,
                    ResultStatus = scanEvent.ResultStatus.ToString(),
                    scanEvent.Confidence,
                    Mbid = scanEvent.AlbumIdentity?.Mbid,
                    DiscogsReleaseId = scanEvent.AlbumIdentity?.DiscogsReleaseId,
                    Title = scanEvent.AlbumIdentity?.Title,
                    Artist = scanEvent.AlbumIdentity?.Artist,
                    Year = (short?)scanEvent.AlbumIdentity?.Year,
                    scanEvent.CapturedAt,
                    scanEvent.CreatedAt
                },
                tx,
                cancellationToken: ct));

            return 0;
        }, ct);
}
