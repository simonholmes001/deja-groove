using Dapper;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.Ports;
using DejaGroove.Application.Collection;
using DejaGroove.Domain.Collection;
using DejaGroove.Domain.Shared;
using DejaGroove.Infrastructure.Persistence.Collection;

namespace DejaGroove.Infrastructure.Tests.Persistence;

/// <summary>Issues #15/#16: RLS-scoped writes, duplicate constraint handling,
/// atomic idempotency binding, and keyset pagination — against real Postgres.</summary>
[Trait("Category", "Integration")]
[Collection("postgres")]
public sealed class PostgresCollectionRepositoryTests(PostgresFixture fx)
{
    private PostgresCollectionRepository Repo() => new(fx.Factory);
    private PostgresIdempotencyStore Idem() => new(fx.Factory);

    private static AlbumIdentity Mbid(string mbid) =>
        AlbumIdentity.Create(mbid, null, "T", "A", 2000);

    private static CollectionRecord New(Guid user, AlbumIdentity id) =>
        CollectionRecord.Create(user, id, "notes", DateTimeOffset.UtcNow);

    [Fact]
    public async Task Add_ThenGetById_RoundTrips()
    {
        var user = Guid.NewGuid();
        var record = New(user, Mbid($"rt-{Guid.NewGuid():N}"));

        await Repo().AddAsync(record, null);
        var loaded = await Repo().GetByIdAsync(user, record.Id);

        Assert.NotNull(loaded);
        Assert.Equal(record.Id, loaded!.Id);
        Assert.Equal(record.Identity.Mbid, loaded.Identity.Mbid);
    }

    [Fact]
    public async Task Add_DuplicateMbidForSameUser_ThrowsDuplicate()
    {
        var user = Guid.NewGuid();
        var mbid = $"dup-{Guid.NewGuid():N}";
        await Repo().AddAsync(New(user, Mbid(mbid)), null);

        await Assert.ThrowsAsync<DuplicateCollectionRecordException>(() =>
            Repo().AddAsync(New(user, Mbid(mbid)), null));
    }

    [Fact]
    public async Task Add_WithIdempotency_BindsKeyAtomically()
    {
        var user = Guid.NewGuid();
        var record = New(user, Mbid($"idem-{Guid.NewGuid():N}"));

        await Repo().AddAsync(record, new IdempotencyWrite("k-1", "fp-1"));
        var binding = await Idem().TryGetAsync(user, "k-1");

        Assert.NotNull(binding);
        Assert.Equal(record.Id, binding!.CollectionRecordId);
        Assert.Equal("fp-1", binding.Fingerprint);
    }

    [Fact]
    public async Task Add_ReusedIdempotencyKey_ThrowsConcurrentIdempotencyNot500()
    {
        // The (user_id, idempotency_key) PK violation must be translated, not
        // bubble as an unhandled server error.
        var user = Guid.NewGuid();
        await Repo().AddAsync(New(user, Mbid($"k1-{Guid.NewGuid():N}")),
            new IdempotencyWrite("dup-key", "fp"));

        await Assert.ThrowsAsync<ConcurrentIdempotencyKeyException>(() =>
            Repo().AddAsync(New(user, Mbid($"k2-{Guid.NewGuid():N}")),
                new IdempotencyWrite("dup-key", "fp")));
    }

    [Fact]
    public async Task FindActiveByIdentity_MatchesByMbid()
    {
        var user = Guid.NewGuid();
        var id = Mbid($"find-{Guid.NewGuid():N}");
        await Repo().AddAsync(New(user, id), null);

        var found = await Repo().FindActiveByIdentityAsync(user, id);

        Assert.NotNull(found);
    }

    [Fact]
    public async Task Rls_OneUserCannotSeeAnotherUsersRecord()
    {
        var alice = Guid.NewGuid();
        var bob = Guid.NewGuid();
        var record = New(alice, Mbid($"rls-{Guid.NewGuid():N}"));
        await Repo().AddAsync(record, null);

        Assert.Null(await Repo().GetByIdAsync(bob, record.Id));
        Assert.Null(await Repo().FindActiveByIdentityAsync(bob, record.Identity));
        var bobPage = await Repo().ListAsync(new CollectionQuery { UserId = bob });
        Assert.Empty(bobPage.Items);
    }

    [Fact]
    public async Task List_KeysetPagination_IsStableAndComplete()
    {
        var user = Guid.NewGuid();
        for (var i = 0; i < 5; i++)
            await Repo().AddAsync(New(user, Mbid($"pg-{i}-{Guid.NewGuid():N}")), null);

        var page1 = await Repo().ListAsync(new CollectionQuery { UserId = user, Limit = 2 });
        Assert.Equal(2, page1.Items.Count);
        Assert.NotNull(page1.NextCursor);

        var page2 = await Repo().ListAsync(new CollectionQuery
        {
            UserId = user,
            Limit = 2,
            Cursor = CollectionCursor.TryDecode(page1.NextCursor)
        });

        var seen = page1.Items.Concat(page2.Items).Select(r => r.Id).ToHashSet();
        Assert.Equal(4, seen.Count); // no overlap across pages
    }

    [Fact]
    public async Task Add_DuplicateTitleArtistOnly_ThrowsDuplicate()
    {
        // Blocker M2: title/artist-only albums now have a DB unique index.
        var user = Guid.NewGuid();
        var id = AlbumIdentity.Create(null, null, "Live At Leeds", "The Who", 1970);
        await Repo().AddAsync(New(user, id), null);

        await Assert.ThrowsAsync<DuplicateCollectionRecordException>(() =>
            Repo().AddAsync(New(user,
                AlbumIdentity.Create(null, null, "LIVE AT LEEDS", "the who", 1970)), null));
    }

    [Fact]
    public async Task GetByIdIncludingDeleted_ReturnsSoftDeletedRecord()
    {
        // Blocker M3: the idempotency replay lookup must see deleted rows.
        var user = Guid.NewGuid();
        var record = New(user, Mbid($"del-{Guid.NewGuid():N}"));
        await Repo().AddAsync(record, null);
        await using (var conn = new Npgsql.NpgsqlConnection(fx.ConnectionString))
            await conn.ExecuteAsync(
                "UPDATE collection_records SET deleted_at = now() WHERE id=@id",
                new { id = record.Id });

        Assert.Null(await Repo().GetByIdAsync(user, record.Id));
        Assert.NotNull(await Repo().GetByIdIncludingDeletedAsync(user, record.Id));
    }

    [Fact]
    public async Task List_SortByTitle_IsOrderedAndKeysetStable()
    {
        // Blocker M1: title sort must actually order AND paginate correctly.
        var user = Guid.NewGuid();
        foreach (var t in new[] { "Delta", "Alpha", "Charlie", "Bravo" })
            await Repo().AddAsync(New(user,
                AlbumIdentity.Create(null, null, t, "Various", 2000)), null);

        var q = new CollectionQuery
        {
            UserId = user,
            SortField = CollectionSortField.Title,
            SortDirection = SortDirection.Ascending,
            Limit = 2
        };
        var page1 = await Repo().ListAsync(q);
        var page2 = await Repo().ListAsync(q with
        {
            Cursor = CollectionCursor.TryDecode(page1.NextCursor)
        });

        var ordered = page1.Items.Concat(page2.Items)
            .Select(r => r.Identity.Title).ToList();
        Assert.Equal(new[] { "Alpha", "Bravo", "Charlie", "Delta" }, ordered);
    }

    [Fact]
    public async Task List_Search_FiltersByTitleOrArtist()
    {
        var user = Guid.NewGuid();
        await Repo().AddAsync(New(user,
            AlbumIdentity.Create(null, null, "Bitches Brew", "Miles Davis", 1970)), null);
        await Repo().AddAsync(New(user,
            AlbumIdentity.Create(null, null, "Blue Train", "John Coltrane", 1957)), null);

        var page = await Repo().ListAsync(new CollectionQuery { UserId = user, Search = "coltrane" });

        Assert.Single(page.Items);
        Assert.Equal("John Coltrane", page.Items[0].Identity.Artist);
    }

    [Fact]
    public async Task Update_ChangeFormatAndNotes_PersistsAndReturnsUpdated()
    {
        var user = Guid.NewGuid();
        var record = CollectionRecord.Rehydrate(
            Guid.NewGuid(), user, Mbid($"upd-{Guid.NewGuid():N}"), "orig", 1,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null, RecordFormat.Cd);
        await Repo().AddAsync(record, null);

        var updated = record.WithUpdate(RecordFormat.Vinyl, "updated notes", DateTimeOffset.UtcNow);
        var result = await Repo().UpdateAsync(updated);

        Assert.NotNull(result);
        Assert.Equal(RecordFormat.Vinyl, result!.Format);
        Assert.Equal("updated notes", result.Notes);
        Assert.Equal(2, result.Version);
    }

    [Fact]
    public async Task Update_NotExistent_ReturnsNull()
    {
        var user = Guid.NewGuid();
        var phantom = CollectionRecord.Rehydrate(
            Guid.NewGuid(), user, Mbid("phantom"), "n", 1,
            DateTimeOffset.UtcNow, DateTimeOffset.UtcNow, null);

        var result = await Repo().UpdateAsync(phantom);

        Assert.Null(result);
    }

    [Fact]
    public async Task Update_IncrementsVersion()
    {
        var user = Guid.NewGuid();
        var record = New(user, Mbid($"ver-{Guid.NewGuid():N}"));
        await Repo().AddAsync(record, null);

        var updated = record.WithUpdate(RecordFormat.Cd, "notes", DateTimeOffset.UtcNow);
        var result = await Repo().UpdateAsync(updated);

        Assert.NotNull(result);
        Assert.Equal(2, result!.Version);
    }

    [Fact]
    public async Task Update_Format_IsPersistedInDb()
    {
        var user = Guid.NewGuid();
        var record = New(user, Mbid($"fmt-{Guid.NewGuid():N}"));
        await Repo().AddAsync(record, null);

        var updated = record.WithUpdate(RecordFormat.Cassette, record.Notes, DateTimeOffset.UtcNow);
        await Repo().UpdateAsync(updated);

        var reloaded = await Repo().GetByIdAsync(user, record.Id);
        Assert.Equal(RecordFormat.Cassette, reloaded!.Format);
    }
}
