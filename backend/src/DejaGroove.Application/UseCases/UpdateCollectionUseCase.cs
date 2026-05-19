using DejaGroove.Application.Collection;
using DejaGroove.Application.Ports;

namespace DejaGroove.Application.UseCases;

/// <summary>
/// Orchestrates a partial update of a collection record (issue #88).
///
/// Ownership check flow:
///   1. Scoped lookup — if null, attempt cross-user lookup to distinguish 403 from 404.
///   2. Soft-deleted records are treated as 404 (the record is logically gone).
///   3. WithUpdate builds a new immutable record; PATCH semantics mean null fields are unchanged.
///   4. A null from UpdateAsync indicates a concurrent delete between the read and write (race → 404).
/// </summary>
public sealed class UpdateCollectionUseCase(
    ICollectionRepository repository,
    TimeProvider timeProvider) : IUpdateCollectionUseCase
{
    public async Task<UpdateCollectionResult> ExecuteAsync(
        UpdateCollectionCommand command, CancellationToken ct = default)
    {
        ArgumentNullException.ThrowIfNull(command);

        var record = await repository.GetByIdIncludingDeletedAsync(command.UserId, command.RecordId, ct);

        if (record is null)
        {
            // Distinguish 404 (doesn't exist) from 403 (exists but owned by someone else).
            var anyRecord = await repository.FindByIdAcrossUsersAsync(command.RecordId, ct);
            return new UpdateCollectionResult(
                anyRecord is not null ? UpdateCollectionOutcome.Forbidden : UpdateCollectionOutcome.NotFound,
                null);
        }

        if (!record.IsActive)
            return new UpdateCollectionResult(UpdateCollectionOutcome.NotFound, null);

        var updated = record.WithUpdate(
            format: command.Format ?? record.Format,
            notes: command.Notes ?? record.Notes,
            now: timeProvider.GetUtcNow());

        var persisted = await repository.UpdateAsync(updated, ct);
        return persisted is null
            ? new UpdateCollectionResult(UpdateCollectionOutcome.NotFound, null)
            : new UpdateCollectionResult(UpdateCollectionOutcome.Updated, persisted);
    }
}
