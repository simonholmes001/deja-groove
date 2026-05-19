using DejaGroove.Application.Collection;
using DejaGroove.Application.Tests.Collection;
using DejaGroove.Application.UseCases;
using DejaGroove.Domain.Collection;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Application.Tests.UseCases;

public sealed class UpdateCollectionUseCaseTests
{
    private static readonly Guid User = Guid.Parse("22222222-2222-2222-2222-222222222222");
    private static readonly Guid OtherUser = Guid.Parse("33333333-3333-3333-3333-333333333333");
    private static readonly DateTimeOffset Now = new(2026, 5, 18, 0, 0, 0, TimeSpan.Zero);

    private readonly FakeCollectionRepository _repo = new();
    private readonly UpdateCollectionUseCase _sut;

    public UpdateCollectionUseCaseTests()
    {
        _sut = new UpdateCollectionUseCase(_repo, new FixedTimeProvider(Now));
    }

    private static AlbumIdentity Album() =>
        AlbumIdentity.Create("mbid-upd", null, "Kind of Blue", "Miles Davis", 1959);

    private CollectionRecord SeedRecord(Guid? userId = null, RecordFormat? format = null, string? notes = "orig")
    {
        var record = CollectionRecord.Rehydrate(
            Guid.NewGuid(), userId ?? User, Album(), notes, 1, Now, Now, null, format);
        _repo.SeedActive(record);
        return record;
    }

    [Fact]
    public async Task Update_ExistingRecord_ReturnsUpdated()
    {
        var record = SeedRecord(format: RecordFormat.Cd, notes: "VG+");

        var result = await _sut.ExecuteAsync(new UpdateCollectionCommand
        {
            UserId = User,
            RecordId = record.Id,
            Format = RecordFormat.Vinyl,
            Notes = "NM"
        });

        Assert.Equal(UpdateCollectionOutcome.Updated, result.Outcome);
        Assert.NotNull(result.Record);
        Assert.Equal(RecordFormat.Vinyl, result.Record!.Format);
        Assert.Equal("NM", result.Record.Notes);
        Assert.Equal(2, result.Record.Version);
    }

    [Fact]
    public async Task Update_NotFound_ReturnsNotFound()
    {
        var result = await _sut.ExecuteAsync(new UpdateCollectionCommand
        {
            UserId = User,
            RecordId = Guid.NewGuid()
        });

        Assert.Equal(UpdateCollectionOutcome.NotFound, result.Outcome);
        Assert.Null(result.Record);
    }

    [Fact]
    public async Task Update_WrongOwner_ReturnsForbidden()
    {
        var record = SeedRecord(OtherUser, null, "notes");

        var result = await _sut.ExecuteAsync(new UpdateCollectionCommand
        {
            UserId = User,
            RecordId = record.Id
        });

        Assert.Equal(UpdateCollectionOutcome.Forbidden, result.Outcome);
        Assert.Null(result.Record);
    }

    [Fact]
    public async Task Update_FormatOnly_PreservesNotes()
    {
        var record = SeedRecord(format: RecordFormat.Cd, notes: "keep-me");

        var result = await _sut.ExecuteAsync(new UpdateCollectionCommand
        {
            UserId = User,
            RecordId = record.Id,
            Format = RecordFormat.Vinyl,
            Notes = null  // not provided → keep existing
        });

        Assert.Equal(UpdateCollectionOutcome.Updated, result.Outcome);
        Assert.Equal(RecordFormat.Vinyl, result.Record!.Format);
        Assert.Equal("keep-me", result.Record.Notes);
    }

    [Fact]
    public async Task Update_NotesOnly_PreservesFormat()
    {
        var record = SeedRecord(format: RecordFormat.Cassette, notes: "old");

        var result = await _sut.ExecuteAsync(new UpdateCollectionCommand
        {
            UserId = User,
            RecordId = record.Id,
            Format = null,  // not provided → keep existing
            Notes = "new notes"
        });

        Assert.Equal(UpdateCollectionOutcome.Updated, result.Outcome);
        Assert.Equal(RecordFormat.Cassette, result.Record!.Format);
        Assert.Equal("new notes", result.Record.Notes);
    }

    [Fact]
    public async Task Update_SameValues_IsIdempotent()
    {
        var record = SeedRecord(format: RecordFormat.Vinyl, notes: "same");

        var first = await _sut.ExecuteAsync(new UpdateCollectionCommand
        {
            UserId = User, RecordId = record.Id, Format = RecordFormat.Vinyl, Notes = "same"
        });
        var second = await _sut.ExecuteAsync(new UpdateCollectionCommand
        {
            UserId = User, RecordId = record.Id, Format = RecordFormat.Vinyl, Notes = "same"
        });

        Assert.Equal(UpdateCollectionOutcome.Updated, first.Outcome);
        Assert.Equal(UpdateCollectionOutcome.Updated, second.Outcome);
        Assert.Equal(first.Record!.Format, second.Record!.Format);
        Assert.Equal(first.Record.Notes, second.Record.Notes);
    }

    [Fact]
    public async Task Update_SoftDeleted_ReturnsNotFound()
    {
        var record = SeedRecord();
        _repo.SoftDelete(record.Id);

        var result = await _sut.ExecuteAsync(new UpdateCollectionCommand
        {
            UserId = User,
            RecordId = record.Id
        });

        Assert.Equal(UpdateCollectionOutcome.NotFound, result.Outcome);
    }

    [Fact]
    public async Task NullCommand_Throws()
    {
        await Assert.ThrowsAsync<ArgumentNullException>(() => _sut.ExecuteAsync(null!));
    }
}
