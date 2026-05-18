using System.Text.Json.Serialization;

namespace DejaGroove.Api.Requests;

public sealed class ResolveScanRequest
{
    [JsonPropertyName("selected_mbid")]
    public string? SelectedMbid { get; init; }

    [JsonPropertyName("selected_discogs_release_id")]
    public string? SelectedDiscogsReleaseId { get; init; }
}
