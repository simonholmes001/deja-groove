using System.Collections.Concurrent;
using DejaGroove.Application.Collection;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Collection;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Api.Ports;

/// <summary>
/// In-memory collection adapters for Development/Testing, mirroring the
/// behaviour the PostgreSQL adapters guarantee (active-by-identity lookup,
/// unique-constraint duplicate, atomic idempotency binding). Contract tests
/// exercise the API shape without a database.
/// </summary>
public sealed class InMemoryCollectionStore
{
    public ConcurrentBag<CollectionRecord> Records { get; } = [];
    public ConcurrentDictionary<(Guid, string), IdempotencyRecord> Keys { get; } = new();
}

public sealed class InMemoryCollectionRepository(InMemoryCollectionStore store) : ICollectionRepository
{
    public Task<CollectionRecord> AddAsync(
        CollectionRecord record, IdempotencyWrite? idempotency, CancellationToken ct = default)
    {
        // Mirrors the DB unique indexes: stable-ID rows (V001) and
        // title/artist-only rows (V012) both reject an active duplicate.
        var clash = store.Records.Any(r =>
            r.UserId == record.UserId && r.IsActive && r.Identity.Equals(record.Identity));
        if (clash)
            throw new DuplicateCollectionRecordException("ux_collection_records (in-memory)");

        store.Records.Add(record);
        if (idempotency is not null)
            store.Keys[(record.UserId, idempotency.Key)] =
                new IdempotencyRecord(idempotency.Key, idempotency.Fingerprint, record.Id);
        return Task.FromResult(record);
    }

    public Task<CollectionRecord?> FindActiveByIdentityAsync(
        Guid userId, AlbumIdentity identity, CancellationToken ct = default) =>
        Task.FromResult(store.Records.FirstOrDefault(r =>
            r.UserId == userId && r.IsActive && r.Identity.Equals(identity)));

    public Task<CollectionRecord?> GetByIdAsync(Guid userId, Guid id, CancellationToken ct = default) =>
        Task.FromResult(store.Records.FirstOrDefault(r =>
            r.UserId == userId && r.Id == id && r.IsActive));

    public Task<CollectionRecord?> GetByIdIncludingDeletedAsync(
        Guid userId, Guid id, CancellationToken ct = default) =>
        Task.FromResult(store.Records.FirstOrDefault(r => r.UserId == userId && r.Id == id));

    public Task<CollectionPage> ListAsync(CollectionQuery query, CancellationToken ct = default)
    {
        var ascending = query.SortDirection == SortDirection.Ascending;

        IEnumerable<CollectionRecord> q = store.Records
            .Where(r => r.UserId == query.UserId && r.IsActive);

        if (!string.IsNullOrWhiteSpace(query.Search))
            q = q.Where(r =>
                (r.Identity.Title?.Contains(query.Search, StringComparison.OrdinalIgnoreCase) ?? false) ||
                (r.Identity.Artist?.Contains(query.Search, StringComparison.OrdinalIgnoreCase) ?? false));

        var ordered = (ascending
            ? q.OrderBy(KeyOf, KeyComparer.Instance)
            : q.OrderByDescending(KeyOf, KeyComparer.Instance)).ToList();

        var cursor = query.Cursor is { } c && c.Field == query.SortField ? c : null;
        if (cursor is not null)
        {
            var boundary = (cursor.SortKey, cursor.CreatedAt, cursor.Id);
            ordered = ordered.Where(r =>
            {
                var cmp = KeyComparer.Instance.Compare(KeyOf(r), boundary);
                return ascending ? cmp > 0 : cmp < 0;
            }).ToList();
        }

        var page = ordered.Take(query.Limit + 1).ToList();
        string? next = null;
        if (page.Count > query.Limit)
        {
            var last = page[query.Limit - 1];
            next = new CollectionCursor(
                query.SortField, SortKey(query.SortField, last), last.CreatedAt, last.Id).Encode();
            page = page.Take(query.Limit).ToList();
        }

        return Task.FromResult(new CollectionPage(page, next));

        (string, DateTimeOffset, Guid) KeyOf(CollectionRecord r) =>
            (SortKey(query.SortField, r), r.CreatedAt, r.Id);
    }

    private static string SortKey(CollectionSortField field, CollectionRecord r) => field switch
    {
        CollectionSortField.Title => (r.Identity.Title ?? "").ToUpperInvariant(),
        CollectionSortField.Artist => (r.Identity.Artist ?? "").ToUpperInvariant(),
        _ => ""
    };

    private sealed class KeyComparer : IComparer<(string SortKey, DateTimeOffset CreatedAt, Guid Id)>
    {
        public static readonly KeyComparer Instance = new();

        public int Compare(
            (string SortKey, DateTimeOffset CreatedAt, Guid Id) a,
            (string SortKey, DateTimeOffset CreatedAt, Guid Id) b)
        {
            var k = string.CompareOrdinal(a.SortKey, b.SortKey);
            if (k != 0) return k;
            var t = a.CreatedAt.CompareTo(b.CreatedAt);
            return t != 0 ? t : a.Id.CompareTo(b.Id);
        }
    }
}

public sealed class InMemoryIdempotencyStore(InMemoryCollectionStore store) : IIdempotencyStore
{
    public Task<IdempotencyRecord?> TryGetAsync(Guid userId, string key, CancellationToken ct = default) =>
        Task.FromResult(store.Keys.TryGetValue((userId, key), out var r) ? r : null);
}

public sealed class NoOpScanCacheInvalidation : IScanCacheInvalidationPort
{
    public Task InvalidateForIdentityAsync(Guid userId, AlbumIdentity identity, CancellationToken ct = default) =>
        Task.CompletedTask;
}
