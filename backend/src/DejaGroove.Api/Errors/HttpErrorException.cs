namespace DejaGroove.Api.Errors;

public sealed class HttpErrorException(int statusCode, string code, string message, bool retryable)
    : Exception(message)
{
    public int StatusCode { get; } = statusCode;

    public string Code { get; } = code;

    public bool Retryable { get; } = retryable;
}
