using Dapper;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Infrastructure.Persistence.Scanning;

/// <summary>
/// PostgreSQL-backed persistence for ambiguous scan snapshots and resolutions.
/// All operations run under user-scoped RLS. Resolution persistence is atomic:
/// status update + resolution row + audit row commit in one transaction.
/// </summary>
public sealed class PostgresAmbiguousScanRepository(PostgresConnectionFactory factory) : IAmbiguousScanRepository
{
    public async Task UpsertScanStatusAsync(Guid userId, Guid requestId, ScanStatus status, CancellationToken ct = default)
    {
        _ = await UserScope.RunAsync(factory, userId, async (conn, tx) =>
        {
            await conn.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO scan_request_status (user_id, request_id, result_status)
                VALUES (@UserId, @RequestId, @Status)
                ON CONFLICT (user_id, request_id) DO UPDATE SET result_status = EXCLUDED.result_status
                """,
                new { UserId = userId, RequestId = requestId, Status = status.ToString() },
                tx, cancellationToken: ct));
            return 0;
        }, ct);
    }

    public Task<ScanStatus?> GetScanStatusAsync(Guid userId, Guid requestId, CancellationToken ct = default) =>
        UserScope.RunAsync<ScanStatus?>(factory, userId, async (conn, tx) =>
        {
            var status = await conn.QuerySingleOrDefaultAsync<string?>(new CommandDefinition(
                "SELECT result_status FROM scan_request_status WHERE user_id=@UserId AND request_id=@RequestId",
                new { UserId = userId, RequestId = requestId }, tx, cancellationToken: ct));
            return status is null ? null : ParseStatus(status, "scan_request_status.result_status");
        }, ct);

    public async Task UpsertAmbiguousAsync(AmbiguousScanSnapshot snapshot, CancellationToken ct = default)
    {
        _ = await UserScope.RunAsync(factory, snapshot.UserId, async (conn, tx) =>
        {
            await conn.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO scan_ambiguities (user_id, request_id, confidence, created_at)
                VALUES (@UserId, @RequestId, @Confidence, @CreatedAt)
                ON CONFLICT (user_id, request_id) DO UPDATE SET confidence = EXCLUDED.confidence
                """,
                new { snapshot.UserId, snapshot.RequestId, snapshot.Confidence, snapshot.CreatedAt },
                tx, cancellationToken: ct));

            await conn.ExecuteAsync(new CommandDefinition(
                "DELETE FROM scan_ambiguity_candidates WHERE user_id=@UserId AND request_id=@RequestId",
                new { snapshot.UserId, snapshot.RequestId }, tx, cancellationToken: ct));

            var rows = snapshot.Candidates
                .Take(3)
                .Select((c, i) => new
                {
                    snapshot.UserId,
                    snapshot.RequestId,
                    Ordinal = (short)(i + 1),
                    c.Mbid,
                    c.DiscogsReleaseId,
                    c.Title,
                    c.Artist,
                    Year = (short?)c.Year
                })
                .ToArray();

            if (rows.Length > 0)
            {
                await conn.ExecuteAsync(new CommandDefinition(
                    """
                    INSERT INTO scan_ambiguity_candidates
                        (user_id, request_id, ordinal, mbid, discogs_release_id, title, artist, year)
                    VALUES
                        (@UserId, @RequestId, @Ordinal, @Mbid, @DiscogsReleaseId, @Title, @Artist, @Year)
                    """,
                    rows, tx, cancellationToken: ct));
            }

            return 0;
        }, ct);
    }

    public Task<AmbiguousScanSnapshot?> GetAmbiguousAsync(Guid userId, Guid requestId, CancellationToken ct = default) =>
        UserScope.RunAsync<AmbiguousScanSnapshot?>(factory, userId, async (conn, tx) =>
        {
            var root = await conn.QuerySingleOrDefaultAsync<AmbiguousRoot>(new CommandDefinition(
                "SELECT confidence, created_at FROM scan_ambiguities WHERE user_id=@UserId AND request_id=@RequestId",
                new { UserId = userId, RequestId = requestId }, tx, cancellationToken: ct));

            if (root is null)
                return null;

            var candidates = (await conn.QueryAsync<CandidateRow>(new CommandDefinition(
                """
                SELECT mbid, discogs_release_id, title, artist, year
                FROM scan_ambiguity_candidates
                WHERE user_id=@UserId AND request_id=@RequestId
                ORDER BY ordinal ASC
                """,
                new { UserId = userId, RequestId = requestId }, tx, cancellationToken: ct)))
                .Select(c => AlbumIdentity.Create(c.mbid, c.discogs_release_id, c.title, c.artist, c.year))
                .ToList();

            return new AmbiguousScanSnapshot(userId, requestId, root.confidence, candidates, root.created_at);
        }, ct);

    public Task<ResolvedScanSnapshot?> GetResolutionAsync(Guid userId, Guid requestId, CancellationToken ct = default) =>
        UserScope.RunAsync<ResolvedScanSnapshot?>(factory, userId, async (conn, tx) =>
        {
            var row = await conn.QuerySingleOrDefaultAsync<ResolutionRow>(new CommandDefinition(
                """
                SELECT selected_mbid, selected_discogs_release_id, result_status, confidence,
                       album_mbid, album_discogs_release_id, album_title, album_artist, album_year,
                       collection_record_id, resolved_at
                FROM scan_resolutions
                WHERE user_id=@UserId AND request_id=@RequestId
                """,
                new { UserId = userId, RequestId = requestId }, tx, cancellationToken: ct));

            return row?.ToSnapshot(userId, requestId);
        }, ct);

    public async Task PersistResolutionAsync(ResolvedScanSnapshot snapshot, CancellationToken ct = default)
    {
        EnsurePersistableResolutionStatus(snapshot.Result.Status);

        _ = await UserScope.RunAsync(factory, snapshot.UserId, async (conn, tx) =>
        {
            await conn.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO scan_request_status (user_id, request_id, result_status)
                VALUES (@UserId, @RequestId, @Status)
                ON CONFLICT (user_id, request_id) DO UPDATE SET result_status = EXCLUDED.result_status
                """,
                new { snapshot.UserId, snapshot.RequestId, Status = snapshot.Result.Status.ToString() },
                tx, cancellationToken: ct));

            await conn.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO scan_resolutions
                    (user_id, request_id, selected_mbid, selected_discogs_release_id, result_status,
                     confidence, album_mbid, album_discogs_release_id, album_title, album_artist,
                     album_year, collection_record_id, resolved_at)
                VALUES
                    (@UserId, @RequestId, @SelectedMbid, @SelectedDiscogsReleaseId, @ResultStatus,
                     @Confidence, @AlbumMbid, @AlbumDiscogsReleaseId, @AlbumTitle, @AlbumArtist,
                     @AlbumYear, @CollectionRecordId, @ResolvedAt)
                ON CONFLICT (user_id, request_id) DO UPDATE SET
                    selected_mbid = EXCLUDED.selected_mbid,
                    selected_discogs_release_id = EXCLUDED.selected_discogs_release_id,
                    result_status = EXCLUDED.result_status,
                    confidence = EXCLUDED.confidence,
                    album_mbid = EXCLUDED.album_mbid,
                    album_discogs_release_id = EXCLUDED.album_discogs_release_id,
                    album_title = EXCLUDED.album_title,
                    album_artist = EXCLUDED.album_artist,
                    album_year = EXCLUDED.album_year,
                    collection_record_id = EXCLUDED.collection_record_id,
                    resolved_at = EXCLUDED.resolved_at
                """,
                new
                {
                    snapshot.UserId,
                    snapshot.RequestId,
                    SelectedMbid = snapshot.SelectedIdentity.Mbid,
                    SelectedDiscogsReleaseId = snapshot.SelectedIdentity.DiscogsReleaseId,
                    ResultStatus = snapshot.Result.Status.ToString(),
                    snapshot.Result.Confidence,
                    AlbumMbid = snapshot.Result.AlbumIdentity?.Mbid,
                    AlbumDiscogsReleaseId = snapshot.Result.AlbumIdentity?.DiscogsReleaseId,
                    AlbumTitle = snapshot.Result.AlbumIdentity?.Title,
                    AlbumArtist = snapshot.Result.AlbumIdentity?.Artist,
                    AlbumYear = (short?)snapshot.Result.AlbumIdentity?.Year,
                    snapshot.Result.CollectionRecordId,
                    ResolvedAt = snapshot.ResolvedAt
                }, tx, cancellationToken: ct));

            await conn.ExecuteAsync(new CommandDefinition(
                """
                INSERT INTO scan_resolution_audit_log
                    (user_id, request_id, selected_mbid, selected_discogs_release_id)
                VALUES (@UserId, @RequestId, @SelectedMbid, @SelectedDiscogsReleaseId)
                """,
                new
                {
                    snapshot.UserId,
                    snapshot.RequestId,
                    SelectedMbid = snapshot.SelectedIdentity.Mbid,
                    SelectedDiscogsReleaseId = snapshot.SelectedIdentity.DiscogsReleaseId
                }, tx, cancellationToken: ct));

            return 0;
        }, ct);
    }

    private sealed class AmbiguousRoot
    {
        public float confidence { get; init; }
        public DateTimeOffset created_at { get; init; }
    }

    private sealed class CandidateRow
    {
        public string? mbid { get; init; }
        public string? discogs_release_id { get; init; }
        public string? title { get; init; }
        public string? artist { get; init; }
        public short? year { get; init; }
    }

    private sealed class ResolutionRow
    {
        public string? selected_mbid { get; init; }
        public string? selected_discogs_release_id { get; init; }
        public string result_status { get; init; } = string.Empty;
        public float confidence { get; init; }
        public string? album_mbid { get; init; }
        public string? album_discogs_release_id { get; init; }
        public string? album_title { get; init; }
        public string? album_artist { get; init; }
        public short? album_year { get; init; }
        public Guid? collection_record_id { get; init; }
        public DateTimeOffset resolved_at { get; init; }

        public ResolvedScanSnapshot ToSnapshot(Guid userId, Guid requestId)
        {
            var selected = AlbumIdentity.Create(selected_mbid, selected_discogs_release_id, null, null, null);
            var status = ParseStatus(result_status, "scan_resolutions.result_status");
            var result = status switch
            {
                ScanStatus.Owned => ScanResult.Owned(
                    AlbumIdentity.Create(album_mbid, album_discogs_release_id, album_title, album_artist, album_year),
                    collection_record_id,
                    confidence),
                ScanStatus.SafeToBuy => ScanResult.SafeToBuy(
                    AlbumIdentity.Create(album_mbid, album_discogs_release_id, album_title, album_artist, album_year),
                    confidence),
                _ => throw new InvalidOperationException(
                    $"Unsupported resolution status '{status}' read from scan_resolutions.result_status.")
            };
            return new ResolvedScanSnapshot(userId, requestId, selected, result, resolved_at);
        }
    }

    private static ScanStatus ParseStatus(string value, string source)
    {
        if (Enum.TryParse<ScanStatus>(value, out var parsed))
            return parsed;

        throw new InvalidOperationException(
            $"Unexpected scan status '{value}' read from {source}.");
    }

    private static void EnsurePersistableResolutionStatus(ScanStatus status)
    {
        if (status is ScanStatus.Owned or ScanStatus.SafeToBuy)
            return;

        throw new InvalidOperationException(
            $"Unsupported resolution status '{status}' for scan_resolutions persistence.");
    }
}
