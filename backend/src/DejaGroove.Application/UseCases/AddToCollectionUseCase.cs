using DejaGroove.Application.Collection;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Collection;

namespace DejaGroove.Application.UseCases;

/// <summary>
/// Orchestrates an idempotent, duplicate-aware collection add (issue #15).
///
/// Order of checks:
///   1. Idempotency replay — a known key with a matching fingerprint returns
///      the prior record; a known key with a different body is a conflict.
///   2. Duplicate detection — an already-owned album returns
///      <see cref="AddToCollectionOutcome.DuplicateDetected"/> unless the
///      caller set <c>AddAnyway</c>.
///   3. Insert — the record and its idempotency row are written atomically;
///      a lost unique-constraint race degrades to a duplicate response.
///
/// Cache invalidation (issue #79) runs after a successful insert. It is
/// deliberately outside the write transaction: a brief stale "safe to buy"
/// verdict is low-harm and self-heals via the cache TTL, and keeping the port
/// boundaries clean is worth that bounded window.
/// </summary>
public sealed class AddToCollectionUseCase(
    ICollectionRepository repository,
    IIdempotencyStore idempotencyStore,
    IScanCacheInvalidationPort cacheInvalidation,
    TimeProvider timeProvider) : IAddToCollectionUseCase
{
    public async Task<AddToCollectionResult> ExecuteAsync(
        AddToCollectionCommand command, CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(command);

        var replay = await TryReplayAsync(command, ct);
        if (replay is not null)
            return replay;

        if (!command.AddAnyway)
        {
            var existing = await repository.FindActiveByIdentityAsync(
                command.UserId, command.Identity, ct);
            if (existing is not null)
                return AddToCollectionResult.Duplicate(existing);
        }

        var record = CollectionRecord.Create(
            command.UserId,
            command.Identity,
            command.Notes,
            timeProvider.GetUtcNow());

        var idempotency = command.IdempotencyKey is { Length: > 0 } key
            ? new IdempotencyWrite(key, command.RequestFingerprint)
            : null;

        try
        {
            var persisted = await repository.AddAsync(record, idempotency, ct);
            await cacheInvalidation.InvalidateForIdentityAsync(
                command.UserId, command.Identity, ct);
            return AddToCollectionResult.Created(persisted);
        }
        catch (DuplicateCollectionRecordException)
        {
            // Concurrent insert won the unique constraint. Re-read so the
            // caller sees the same shape as a sequential duplicate.
            var winner = await repository.FindActiveByIdentityAsync(
                command.UserId, command.Identity, ct);
            return winner is not null
                ? AddToCollectionResult.Duplicate(winner)
                : throw new DuplicateCollectionRecordException(
                    "Duplicate insert raced but the winning row could not be re-read.");
        }
    }

    private async Task<AddToCollectionResult?> TryReplayAsync(
        AddToCollectionCommand command, CancellationToken ct)
    {
        if (command.IdempotencyKey is not { Length: > 0 } key)
            return null;

        var prior = await idempotencyStore.TryGetAsync(command.UserId, key, ct);
        if (prior is null)
            return null;

        if (!string.Equals(prior.Fingerprint, command.RequestFingerprint, StringComparison.Ordinal))
            throw new IdempotencyConflictException(
                "idempotency_key_reused",
                "This idempotency key was already used with a different request body.");

        // Resolve regardless of soft-delete: the binding is immutable, so a
        // retry must replay the original result even if the record was since
        // deleted. Anything else would turn a safe retry into a hard 409.
        var record = await repository.GetByIdIncludingDeletedAsync(
                command.UserId, prior.CollectionRecordId, ct)
            ?? throw new IdempotencyConflictException(
                "idempotency_record_missing",
                "The record bound to this idempotency key no longer exists.");

        return AddToCollectionResult.Replayed(record);
    }
}
