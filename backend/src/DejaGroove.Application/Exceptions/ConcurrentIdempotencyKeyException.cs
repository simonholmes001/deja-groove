namespace DejaGroove.Application.Exceptions;

/// <summary>
/// Raised when a concurrent request commits the same (user, idempotency key)
/// binding first, so this transaction loses the unique-constraint race on
/// collection_idempotency_keys. The use case resolves it by replaying: the
/// winner's record is returned, or a fingerprint mismatch becomes the normal
/// 409 idempotency conflict. It must never surface as a 500.
/// </summary>
public sealed class ConcurrentIdempotencyKeyException(string message)
    : Exception(message);
