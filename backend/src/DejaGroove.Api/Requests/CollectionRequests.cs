using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Serialization;

namespace DejaGroove.Api.Requests;

public sealed class AddCollectionItemRequest
{
    [JsonPropertyName("mbid")]
    public string? Mbid { get; init; }

    [JsonPropertyName("discogs_release_id")]
    public string? DiscogsReleaseId { get; init; }

    [JsonPropertyName("title")]
    public string? Title { get; init; }

    [JsonPropertyName("artist")]
    public string? Artist { get; init; }

    [JsonPropertyName("year")]
    public int? Year { get; init; }

    [JsonPropertyName("notes")]
    public string? Notes { get; init; }

    [JsonPropertyName("add_anyway")]
    public bool AddAnyway { get; init; }

    /// <summary>Stable hash of the identity-bearing fields. Two requests with
    /// the same idempotency key must carry the same fingerprint; differing
    /// bodies under one key are a conflict.</summary>
    public string Fingerprint()
    {
        var canonical = string.Join('|',
            Mbid ?? "", DiscogsReleaseId ?? "", Title ?? "", Artist ?? "",
            Year?.ToString() ?? "", Notes ?? "", AddAnyway ? "1" : "0");
        return Convert.ToHexString(
            SHA256.HashData(Encoding.UTF8.GetBytes(canonical)));
    }
}

public sealed class PatchCollectionItemRequest
{
    [JsonPropertyName("format")]
    public string? Format { get; init; }

    [JsonPropertyName("notes")]
    public string? Notes { get; init; }
}
