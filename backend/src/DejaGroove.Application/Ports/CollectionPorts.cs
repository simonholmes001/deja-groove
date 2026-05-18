using DejaGroove.Application.Collection;
using DejaGroove.Domain.Collection;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Application.Ports;

/// <summary>The authenticated caller, resolved from the validated JWT.</summary>
public interface ICurrentUser
{
    Guid UserId { get; }
    string Subject { get; }
}

/// <summary>Idempotency-key bookkeeping for collection writes.</summary>
public sealed record IdempotencyRecord(string Key, string Fingerprint, Guid CollectionRecordId);

public interface IIdempotencyStore
{
    Task<IdempotencyRecord?> TryGetAsync(Guid userId, string key, CancellationToken ct = default);
}

/// <summary>
/// Persistence boundary for the collection aggregate. Implementations are
/// responsible for Row-Level-Security scoping and for writing the idempotency
/// row in the same transaction as the insert so a committed record can never
/// be observed without its idempotency key.
/// </summary>
public interface ICollectionRepository
{
    Task<CollectionRecord> AddAsync(
        CollectionRecord record,
        IdempotencyWrite? idempotency,
        CancellationToken ct = default);

    Task<CollectionRecord?> FindActiveByIdentityAsync(
        Guid userId, AlbumIdentity identity, CancellationToken ct = default);

    /// <summary>Active-only lookup for the detail endpoint (soft-deleted ⇒ 404).</summary>
    Task<CollectionRecord?> GetByIdAsync(Guid userId, Guid id, CancellationToken ct = default);

    /// <summary>
    /// Resolves an idempotency-bound record regardless of soft-delete state.
    /// The binding is immutable and points at a real row; a network retry must
    /// replay it even if the record was deleted in between.
    /// </summary>
    Task<CollectionRecord?> GetByIdIncludingDeletedAsync(
        Guid userId, Guid id, CancellationToken ct = default);

    Task<CollectionPage> ListAsync(CollectionQuery query, CancellationToken ct = default);
}

public sealed record IdempotencyWrite(string Key, string Fingerprint);

/// <summary>
/// Invalidation seam for the pHash result cache (issue #79). Called after a
/// collection mutation so a previously cached <c>SafeToBuy</c> verdict for the
/// same album cannot keep being served once the user owns it.
/// </summary>
public interface IScanCacheInvalidationPort
{
    Task InvalidateForIdentityAsync(Guid userId, AlbumIdentity identity, CancellationToken ct = default);
}
