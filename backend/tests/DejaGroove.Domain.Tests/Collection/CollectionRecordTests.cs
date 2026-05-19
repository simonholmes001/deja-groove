using DejaGroove.Domain.Collection;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Domain.Tests.Collection;

public sealed class CollectionRecordTests
{
    private static readonly AlbumIdentity Identity =
        AlbumIdentity.Create(mbid: "mbid-1", discogsReleaseId: null, title: "Blue", artist: "Joni", year: 1971);

    private static readonly DateTimeOffset Now =
        new(2026, 5, 18, 12, 0, 0, TimeSpan.Zero);

    [Fact]
    public void Create_SetsFreshIdentityAndTimestamps()
    {
        var userId = Guid.NewGuid();

        var record = CollectionRecord.Create(userId, Identity, notes: "first press", Now);

        Assert.NotEqual(Guid.Empty, record.Id);
        Assert.Equal(userId, record.UserId);
        Assert.Same(Identity, record.Identity);
        Assert.Equal("first press", record.Notes);
        Assert.Equal(1, record.Version);
        Assert.Equal(Now, record.CreatedAt);
        Assert.Equal(Now, record.UpdatedAt);
        Assert.Null(record.DeletedAt);
        Assert.True(record.IsActive);
    }

    [Fact]
    public void Create_TwoRecords_HaveDistinctIds()
    {
        var a = CollectionRecord.Create(Guid.NewGuid(), Identity, null, Now);
        var b = CollectionRecord.Create(Guid.NewGuid(), Identity, null, Now);

        Assert.NotEqual(a.Id, b.Id);
    }

    [Fact]
    public void Create_EmptyUserId_Throws()
    {
        Assert.Throws<ArgumentException>(() =>
            CollectionRecord.Create(Guid.Empty, Identity, null, Now));
    }

    [Fact]
    public void Create_NullIdentity_Throws()
    {
        Assert.Throws<ArgumentNullException>(() =>
            CollectionRecord.Create(Guid.NewGuid(), null!, null, Now));
    }

    [Fact]
    public void Rehydrate_RestoresPersistedStateExactly()
    {
        var id = Guid.NewGuid();
        var userId = Guid.NewGuid();
        var created = Now.AddDays(-2);
        var updated = Now.AddDays(-1);
        var deleted = Now;

        var record = CollectionRecord.Rehydrate(
            id, userId, Identity, notes: "n", version: 3,
            createdAt: created, updatedAt: updated, deletedAt: deleted);

        Assert.Equal(id, record.Id);
        Assert.Equal(userId, record.UserId);
        Assert.Equal(3, record.Version);
        Assert.Equal(created, record.CreatedAt);
        Assert.Equal(updated, record.UpdatedAt);
        Assert.Equal(deleted, record.DeletedAt);
        Assert.False(record.IsActive);
    }

    [Fact]
    public void WithUpdate_Format_UpdatesFormatIncrementsVersionAndTimestamp()
    {
        var record = CollectionRecord.Create(Guid.NewGuid(), Identity, notes: "original", Now);
        var later = Now.AddHours(1);

        var updated = record.WithUpdate(RecordFormat.Vinyl, record.Notes, later);

        Assert.Equal(RecordFormat.Vinyl, updated.Format);
        Assert.Equal(2, updated.Version);
        Assert.Equal(later, updated.UpdatedAt);
        Assert.Equal(Now, updated.CreatedAt);
    }

    [Fact]
    public void WithUpdate_Notes_UpdatesNotesPreservesFormat()
    {
        var record = CollectionRecord.Rehydrate(
            Guid.NewGuid(), Guid.NewGuid(), Identity, "old notes", 1, Now, Now, null, RecordFormat.Cd);

        var updated = record.WithUpdate(record.Format, "new notes", Now.AddMinutes(1));

        Assert.Equal("new notes", updated.Notes);
        Assert.Equal(RecordFormat.Cd, updated.Format);
        Assert.Equal(2, updated.Version);
    }

    [Fact]
    public void WithUpdate_NullFormatAndNullNotes_CanClearBothFields()
    {
        var record = CollectionRecord.Rehydrate(
            Guid.NewGuid(), Guid.NewGuid(), Identity, "notes", 1, Now, Now, null, RecordFormat.Vinyl);

        var updated = record.WithUpdate(null, null, Now.AddMinutes(1));

        Assert.Null(updated.Format);
        Assert.Null(updated.Notes);
        Assert.Equal(2, updated.Version);
    }

    [Fact]
    public void WithUpdate_PreservesIdentityAndUserId()
    {
        var userId = Guid.NewGuid();
        var record = CollectionRecord.Create(userId, Identity, "notes", Now);

        var updated = record.WithUpdate(RecordFormat.Other, "new notes", Now.AddHours(1));

        Assert.Equal(record.Id, updated.Id);
        Assert.Equal(userId, updated.UserId);
        Assert.Same(Identity, updated.Identity);
        Assert.Equal(record.CreatedAt, updated.CreatedAt);
        Assert.Equal(record.DeletedAt, updated.DeletedAt);
    }
}
