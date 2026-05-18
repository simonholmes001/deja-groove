namespace DejaGroove.Application.Exceptions;

/// <summary>
/// Raised when an idempotency key is reused with a different request body.
/// The contract treats this as a client error (HTTP 409): the key has already
/// been bound to a different operation and must not be replayed.
/// </summary>
public sealed class IdempotencyConflictException(string code, string message) : Exception(message)
{
    public string Code { get; } = code;
}
