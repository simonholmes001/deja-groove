using System.Text.Json.Serialization;

namespace DejaGroove.Api.Responses;

public sealed class ErrorResponse
{
    [JsonPropertyName("error")]
    public ErrorDetail Error { get; init; } = default!;
}

public sealed class ErrorDetail
{
    [JsonPropertyName("code")]
    public string Code { get; init; } = default!;

    [JsonPropertyName("message")]
    public string Message { get; init; } = default!;

    [JsonPropertyName("retryable")]
    public bool Retryable { get; init; }

    [JsonPropertyName("request_id")]
    public Guid RequestId { get; init; }
}
