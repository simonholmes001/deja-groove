using DejaGroove.Application.Collection;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.Tests.Collection;
using DejaGroove.Application.UseCases;
using DejaGroove.Domain.Collection;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Application.Tests.UseCases;

public sealed class AddToCollectionUseCaseTests
{
    private static readonly Guid User = Guid.Parse("11111111-1111-1111-1111-111111111111");
    private static readonly DateTimeOffset Now = new(2026, 5, 18, 0, 0, 0, TimeSpan.Zero);

    private readonly FakeCollectionRepository _repo = new();
    private readonly RecordingCacheInvalidation _cache = new();
    private readonly AddToCollectionUseCase _sut;

    public AddToCollectionUseCaseTests()
    {
        _sut = new AddToCollectionUseCase(
            _repo, new FakeIdempotencyStore(_repo), _cache, new FixedTimeProvider(Now));
    }

    private static AlbumIdentity Album(string mbid = "mbid-aaa") =>
        AlbumIdentity.Create(mbid, null, "Rumours", "Fleetwood Mac", 1977);

    private AddToCollectionCommand Command(
        string? key = null, string fingerprint = "fp", bool addAnyway = false,
        AlbumIdentity? identity = null) => new()
        {
            UserId = User,
            Identity = identity ?? Album(),
            Notes = "VG+",
            IdempotencyKey = key,
            RequestFingerprint = fingerprint,
            AddAnyway = addAnyway
        };

    [Fact]
    public async Task NewAlbum_CreatesRecordAndInvalidatesCache()
    {
        var result = await _sut.ExecuteAsync(Command());

        Assert.Equal(AddToCollectionOutcome.Created, result.Outcome);
        Assert.NotNull(result.Record);
        Assert.Equal(User, result.Record!.UserId);
        Assert.Single(_cache.Calls);
        Assert.Equal(User, _cache.Calls[0].UserId);
    }

    [Fact]
    public async Task OwnedAlbum_WithoutAddAnyway_ReturnsDuplicateAndDoesNotInsert()
    {
        _repo.SeedActive(CollectionRecord.Create(User, Album(), "owned", Now));

        var result = await _sut.ExecuteAsync(Command());

        Assert.Equal(AddToCollectionOutcome.DuplicateDetected, result.Outcome);
        Assert.NotNull(result.ExistingDuplicate);
        Assert.Equal(0, _repo.AddCalls);
        Assert.Empty(_cache.Calls);
    }

    [Fact]
    public async Task OwnedAlbum_WithAddAnyway_InsertsSecondCopy()
    {
        _repo.SeedActive(CollectionRecord.Create(User, Album(), "owned", Now));

        var result = await _sut.ExecuteAsync(Command(addAnyway: true));

        Assert.Equal(AddToCollectionOutcome.Created, result.Outcome);
        Assert.Equal(1, _repo.AddCalls);
    }

    [Fact]
    public async Task SameIdempotencyKey_SameBody_ReplaysPriorRecord()
    {
        var first = await _sut.ExecuteAsync(Command(key: "idem-1"));

        var replay = await _sut.ExecuteAsync(Command(key: "idem-1"));

        Assert.Equal(AddToCollectionOutcome.Replayed, replay.Outcome);
        Assert.Equal(first.Record!.Id, replay.Record!.Id);
        Assert.Equal(1, _repo.AddCalls); // not inserted twice
    }

    [Fact]
    public async Task SameIdempotencyKey_AfterRecordSoftDeleted_StillReplays()
    {
        // Blocker M3: a network retry must replay even if the bound record was
        // soft-deleted between the original call and the retry.
        var first = await _sut.ExecuteAsync(Command(key: "idem-del"));
        _repo.SoftDelete(first.Record!.Id);

        var replay = await _sut.ExecuteAsync(Command(key: "idem-del"));

        Assert.Equal(AddToCollectionOutcome.Replayed, replay.Outcome);
        Assert.Equal(first.Record!.Id, replay.Record!.Id);
    }

    [Fact]
    public async Task SameIdempotencyKey_DifferentBody_ThrowsConflict()
    {
        await _sut.ExecuteAsync(Command(key: "idem-2", fingerprint: "fp-A"));

        var ex = await Assert.ThrowsAsync<IdempotencyConflictException>(() =>
            _sut.ExecuteAsync(Command(key: "idem-2", fingerprint: "fp-B")));

        Assert.Equal("idempotency_key_reused", ex.Code);
    }

    [Fact]
    public async Task ConcurrentUniqueViolation_DegradesToDuplicate()
    {
        _repo.SeedActive(CollectionRecord.Create(User, Album(), "winner", Now));
        _repo.ThrowDuplicateOnNextAdd = true;

        var result = await _sut.ExecuteAsync(Command(addAnyway: true));

        Assert.Equal(AddToCollectionOutcome.DuplicateDetected, result.Outcome);
        Assert.NotNull(result.ExistingDuplicate);
    }

    [Fact]
    public async Task NullCommand_Throws()
    {
        await Assert.ThrowsAsync<ArgumentNullException>(() => _sut.ExecuteAsync(null!));
    }
}
