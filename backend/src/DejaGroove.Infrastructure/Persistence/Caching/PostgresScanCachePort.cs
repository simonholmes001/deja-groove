using Dapper;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Infrastructure.Persistence.Caching;

/// <summary>
/// PostgreSQL-backed pHash result cache (issue #79). Replaces Redis.
///
/// Key schema: (user_id, phash, phash_version). phash is the unsigned 64-bit
/// hash reinterpreted as a signed BIGINT — the bit pattern is preserved and
/// both read and write use the same reinterpretation, so equality lookups are
/// exact. phash_version lets a future hash-algorithm change miss cleanly
/// instead of poisoning results.
///
/// Ambiguous results carry candidate lists the single-row schema cannot model,
/// so they are intentionally not cached (next scan recomputes them).
/// </summary>
public sealed class PostgresScanCachePort(PostgresConnectionFactory factory)
    : IScanCachePort, IScanCacheInvalidationPort
{
    private const short PhashVersion = 1;

    public Task<ScanResult?> TryGetAsync(
        Guid userId, PerceptualHash hash, CancellationToken ct = default) =>
        UserScope.RunAsync(factory, userId, async (conn, tx) =>
        {
            var row = await conn.QuerySingleOrDefaultAsync<Row>(new CommandDefinition(
                """
                SELECT result_status, confidence, mbid, discogs_release_id, title, artist, year, collection_record_id
                FROM scan_results_cache
                WHERE user_id = @userId AND phash = @phash AND phash_version = @ver
                  AND expires_at > now()
                """,
                new { userId, phash = unchecked((long)hash.Value), ver = PhashVersion },
                tx, cancellationToken: ct));

            return row?.ToScanResult();
        }, ct);

    public Task StoreAsync(
        Guid userId, PerceptualHash hash, ScanResult result, TimeSpan ttl,
        CancellationToken ct = default)
    {
        // Ambiguous results are not representable in one row; skip caching them.
        if (result.Status == ScanStatus.Ambiguous)
            return Task.CompletedTask;

        return UserScope.RunAsync(factory, userId, async (conn, tx) =>
        {
            await conn.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO scan_results_cache
                    (user_id, phash, phash_version, result_status, confidence,
                     mbid, discogs_release_id, title, artist, year,
                     collection_record_id, expires_at)
                VALUES
                    (@UserId, @Phash, @Ver, @Status, @Confidence,
                     @Mbid, @Discogs, @Title, @Artist, @Year,
                     @CollectionRecordId, now() + @Ttl)
                ON CONFLICT (user_id, phash, phash_version) DO UPDATE SET
                    result_status        = EXCLUDED.result_status,
                    confidence           = EXCLUDED.confidence,
                    mbid                 = EXCLUDED.mbid,
                    discogs_release_id   = EXCLUDED.discogs_release_id,
                    title                = EXCLUDED.title,
                    artist               = EXCLUDED.artist,
                    year                 = EXCLUDED.year,
                    collection_record_id = EXCLUDED.collection_record_id,
                    expires_at           = EXCLUDED.expires_at
                """,
                new
                {
                    UserId = userId,
                    Phash = unchecked((long)hash.Value),
                    Ver = PhashVersion,
                    Status = result.Status.ToString(),
                    result.Confidence,
                    Mbid = result.AlbumIdentity?.Mbid,
                    Discogs = result.AlbumIdentity?.DiscogsReleaseId,
                    Title = result.AlbumIdentity?.Title,
                    Artist = result.AlbumIdentity?.Artist,
                    Year = (short?)result.AlbumIdentity?.Year,
                    result.CollectionRecordId,
                    Ttl = ttl
                }, tx, cancellationToken: ct));
            return 0;
        }, ct);
    }

    public Task InvalidateForIdentityAsync(
        Guid userId, AlbumIdentity identity, CancellationToken ct = default) =>
        UserScope.RunAsync(factory, userId, async (conn, tx) =>
        {
            await conn.ExecuteAsync(new CommandDefinition(
                """
                DELETE FROM scan_results_cache
                WHERE user_id = @userId
                  AND (
                        (@mbid    IS NOT NULL AND mbid = @mbid)
                     OR (@discogs IS NOT NULL AND discogs_release_id = @discogs)
                     OR (@title   IS NOT NULL AND @artist IS NOT NULL
                         AND upper(title) = upper(@title) AND upper(artist) = upper(@artist))
                      )
                """,
                new
                {
                    userId,
                    mbid = identity.Mbid,
                    discogs = identity.DiscogsReleaseId,
                    title = identity.Title,
                    artist = identity.Artist
                }, tx, cancellationToken: ct));
            return 0;
        }, ct);

    private sealed class Row
    {
        public string result_status { get; init; } = string.Empty;
        public float confidence { get; init; }
        public string? mbid { get; init; }
        public string? discogs_release_id { get; init; }
        public string? title { get; init; }
        public string? artist { get; init; }
        public short? year { get; init; }
        public Guid? collection_record_id { get; init; }

        public ScanResult ToScanResult()
        {
            var status = Enum.Parse<ScanStatus>(result_status);
            if (status == ScanStatus.NoMatch)
                return ScanResult.NoMatch();

            var identity = AlbumIdentity.Create(mbid, discogs_release_id, title, artist, year);
            return status switch
            {
                ScanStatus.Owned => ScanResult.Owned(identity, collection_record_id, confidence),
                _ => ScanResult.SafeToBuy(identity, confidence)
            };
        }
    }
}
