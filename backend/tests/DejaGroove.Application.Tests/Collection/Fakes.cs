using DejaGroove.Application.Collection;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Collection;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Application.Tests.Collection;

/// <summary>In-memory collection store. Models the active-by-identity and
/// unique-constraint behaviour the real repository guarantees.</summary>
internal sealed class FakeCollectionRepository : ICollectionRepository
{
    private readonly List<CollectionRecord> _records = [];
    public int AddCalls { get; private set; }
    public bool ThrowDuplicateOnNextAdd { get; set; }

    public Task<CollectionRecord> AddAsync(
        CollectionRecord record, IdempotencyWrite? idempotency, CancellationToken ct = default)
    {
        AddCalls++;
        if (ThrowDuplicateOnNextAdd)
        {
            ThrowDuplicateOnNextAdd = false;
            throw new DuplicateCollectionRecordException("unique violation");
        }

        _records.Add(record);
        if (idempotency is not null)
            Idempotency[(record.UserId, idempotency.Key)] =
                new IdempotencyRecord(idempotency.Key, idempotency.Fingerprint, record.Id);
        return Task.FromResult(record);
    }

    public Task<CollectionRecord?> FindActiveByIdentityAsync(
        Guid userId, AlbumIdentity identity, CancellationToken ct = default) =>
        Task.FromResult(_records.FirstOrDefault(r =>
            r.UserId == userId && r.IsActive && r.Identity.Equals(identity)));

    public Task<CollectionRecord?> GetByIdAsync(Guid userId, Guid id, CancellationToken ct = default) =>
        Task.FromResult(_records.FirstOrDefault(r => r.UserId == userId && r.Id == id && r.IsActive));

    public Task<CollectionRecord?> GetByIdIncludingDeletedAsync(
        Guid userId, Guid id, CancellationToken ct = default) =>
        Task.FromResult(_records.FirstOrDefault(r => r.UserId == userId && r.Id == id));

    public Task<CollectionPage> ListAsync(CollectionQuery query, CancellationToken ct = default) =>
        Task.FromResult(new CollectionPage(
            _records.Where(r => r.UserId == query.UserId && r.IsActive).ToList(), null));

    public Dictionary<(Guid, string), IdempotencyRecord> Idempotency { get; } = new();

    public void SeedActive(CollectionRecord record) => _records.Add(record);

    /// <summary>Replaces a stored record with a soft-deleted copy, as the
    /// database would after a delete (binding row is untouched).</summary>
    public void SoftDelete(Guid id)
    {
        var i = _records.FindIndex(r => r.Id == id);
        var r = _records[i];
        _records[i] = CollectionRecord.Rehydrate(
            r.Id, r.UserId, r.Identity, r.Notes, r.Version,
            r.CreatedAt, r.UpdatedAt, DateTimeOffset.UtcNow);
    }
}

internal sealed class FakeIdempotencyStore(FakeCollectionRepository repo) : IIdempotencyStore
{
    public Task<IdempotencyRecord?> TryGetAsync(Guid userId, string key, CancellationToken ct = default) =>
        Task.FromResult(repo.Idempotency.TryGetValue((userId, key), out var r) ? r : null);
}

internal sealed class RecordingCacheInvalidation : IScanCacheInvalidationPort
{
    public List<(Guid UserId, AlbumIdentity Identity)> Calls { get; } = [];

    public Task InvalidateForIdentityAsync(Guid userId, AlbumIdentity identity, CancellationToken ct = default)
    {
        Calls.Add((userId, identity));
        return Task.CompletedTask;
    }
}

internal sealed class FixedTimeProvider(DateTimeOffset now) : TimeProvider
{
    public override DateTimeOffset GetUtcNow() => now;
}
