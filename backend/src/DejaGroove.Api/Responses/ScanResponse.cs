using System.Text.Json.Serialization;

namespace DejaGroove.Api.Responses;

public sealed class ScanResponse
{
    [JsonPropertyName("status")]
    public string Status { get; init; } = default!;

    [JsonPropertyName("confidence")]
    public float Confidence { get; init; }

    [JsonPropertyName("album")]
    public AlbumDto? Album { get; init; }

    // owned_record deferred to #12 when ScanResult.Owned is reachable
    // and the domain carries format + date_added fields

    [JsonPropertyName("candidates")]
    public IReadOnlyList<CandidateDto> Candidates { get; init; } = [];

    [JsonPropertyName("request_id")]
    public Guid RequestId { get; init; }
}

public sealed class AlbumDto
{
    [JsonPropertyName("mbid")]
    public string? Mbid { get; init; }

    [JsonPropertyName("discogs_release_id")]
    public string? DiscogsReleaseId { get; init; }

    [JsonPropertyName("title")]
    public string Title { get; init; } = default!;

    [JsonPropertyName("artist")]
    public string Artist { get; init; } = default!;

    [JsonPropertyName("year")]
    public int? Year { get; init; }
}

public sealed class OwnedRecordDto
{
    [JsonPropertyName("collection_album_id")]
    public Guid CollectionAlbumId { get; init; }

    [JsonPropertyName("format")]
    public string Format { get; init; } = default!;

    [JsonPropertyName("date_added")]
    public DateTimeOffset DateAdded { get; init; }
}

public sealed class CandidateDto
{
    [JsonPropertyName("mbid")]
    public string? Mbid { get; init; }

    [JsonPropertyName("discogs_release_id")]
    public string? DiscogsReleaseId { get; init; }

    [JsonPropertyName("title")]
    public string Title { get; init; } = default!;

    [JsonPropertyName("artist")]
    public string Artist { get; init; } = default!;

    [JsonPropertyName("year")]
    public int? Year { get; init; }
}
