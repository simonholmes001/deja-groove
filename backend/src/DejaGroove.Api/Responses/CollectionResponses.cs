using System.Text.Json.Serialization;
using DejaGroove.Domain.Collection;

namespace DejaGroove.Api.Responses;

public sealed class CollectionItemDto
{
    [JsonPropertyName("id")] public Guid Id { get; init; }
    [JsonPropertyName("mbid")] public string? Mbid { get; init; }
    [JsonPropertyName("discogs_release_id")] public string? DiscogsReleaseId { get; init; }
    [JsonPropertyName("title")] public string? Title { get; init; }
    [JsonPropertyName("artist")] public string? Artist { get; init; }
    [JsonPropertyName("year")] public int? Year { get; init; }
    [JsonPropertyName("notes")] public string? Notes { get; init; }
    [JsonPropertyName("created_at")] public DateTimeOffset CreatedAt { get; init; }
    [JsonPropertyName("updated_at")] public DateTimeOffset UpdatedAt { get; init; }

    public static CollectionItemDto From(CollectionRecord r) => new()
    {
        Id = r.Id,
        Mbid = r.Identity.Mbid,
        DiscogsReleaseId = r.Identity.DiscogsReleaseId,
        Title = r.Identity.Title,
        Artist = r.Identity.Artist,
        Year = r.Identity.Year,
        Notes = r.Notes,
        CreatedAt = r.CreatedAt,
        UpdatedAt = r.UpdatedAt
    };
}

public sealed class CollectionPageDto
{
    [JsonPropertyName("items")]
    public IReadOnlyList<CollectionItemDto> Items { get; init; } = [];

    [JsonPropertyName("next_cursor")]
    public string? NextCursor { get; init; }
}

public sealed class DuplicateDetectedDto
{
    [JsonPropertyName("error")]
    public string Error { get; init; } = "duplicate_detected";

    [JsonPropertyName("message")]
    public string Message { get; init; } = "This album is already in your collection.";

    [JsonPropertyName("existing")]
    public CollectionItemDto Existing { get; init; } = default!;

    [JsonPropertyName("request_id")]
    public Guid RequestId { get; init; }
}
