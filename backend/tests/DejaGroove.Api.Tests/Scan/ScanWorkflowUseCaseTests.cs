using DejaGroove.Application.Commands;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.Ports;
using DejaGroove.Application.UseCases;
using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;
using NSubstitute;

namespace DejaGroove.Api.Tests.Scan;

public sealed class ScanWorkflowUseCaseTests
{
    private static readonly AlbumIdentity Identity = AlbumIdentity.Create("mbid-1", null, "Kind of Blue", "Miles Davis", 1959);

    private static ScanWorkflowUseCase CreateSut(
        IImageValidationPort imageValidation,
        IPerceptualHashPort pHash,
        IScanCachePort cache,
        IAlbumMatchingPort matcher,
        ICollectionOwnershipPort ownership,
        IScanEventRepository events)
    {
        imageValidation
            .ValidateAsync(Arg.Any<Stream>(), Arg.Any<string?>(), Arg.Any<CancellationToken>())
            .Returns(ValidationResult.Ok());

        return new ScanWorkflowUseCase(imageValidation, pHash, cache, matcher, ownership, events);
    }

    [Fact]
    public async Task ExecuteAsync_WhenCacheHit_ReturnsCachedResultAndSkipsMatcher()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);
        var cached = ScanResult.SafeToBuy(Identity, 0.88f);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns(cached);

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events);
        var command = BuildCommand(userId);

        var result = await sut.ExecuteAsync(command);

        Assert.Same(cached, result);
        await matcher.DidNotReceiveWithAnyArgs().IdentifyAsync(default!, default);
        await ownership.DidNotReceiveWithAnyArgs().CheckAsync(default, default!, default);
    }

    [Fact]
    public async Task ExecuteAsync_WhenMatcherReturnsSafeToBuyAndAlbumIsOwned_ReturnsOwned()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();

        var userId = Guid.NewGuid();
        var recordId = Guid.NewGuid();
        var hash = new PerceptualHash(42);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(ScanResult.SafeToBuy(Identity, 0.91f));
        ownership.CheckAsync(userId, Identity, Arg.Any<CancellationToken>()).Returns((true, (Guid?)recordId));

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events);
        var command = BuildCommand(userId);

        var result = await sut.ExecuteAsync(command);

        Assert.Equal(ScanStatus.Owned, result.Status);
        Assert.Equal(recordId, result.CollectionRecordId);
    }

    [Fact]
    public async Task ExecuteAsync_WhenMatcherReturnsAmbiguous_SkipsOwnershipAndReturnsAmbiguous()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);
        var ambiguous = ScanResult.Ambiguous([Identity], 0.52f);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(ambiguous);

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events);
        var command = BuildCommand(userId);

        var result = await sut.ExecuteAsync(command);

        Assert.Equal(ScanStatus.Ambiguous, result.Status);
        await ownership.DidNotReceiveWithAnyArgs().CheckAsync(default, default!, default);
    }

    [Fact]
    public async Task ExecuteAsync_WhenUserIdIsMissing_SkipsOwnershipCheck()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();

        var hash = new PerceptualHash(42);
        var safe = ScanResult.SafeToBuy(Identity, 0.74f);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(safe);

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events);
        var command = BuildCommand(userId: null);

        var result = await sut.ExecuteAsync(command);

        Assert.Equal(ScanStatus.SafeToBuy, result.Status);
        await ownership.DidNotReceiveWithAnyArgs().CheckAsync(default, default!, default);
    }

    [Fact]
    public async Task ExecuteAsync_WhenMatcherFailsTransiently_RetriesOnce()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>())
            .Returns(_ => throw new TimeoutException("first attempt timed out"), _ => ScanResult.SafeToBuy(Identity, 0.93f));
        ownership.CheckAsync(userId, Identity, Arg.Any<CancellationToken>()).Returns((false, (Guid?)null));

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events);
        var command = BuildCommand(userId);

        var result = await sut.ExecuteAsync(command);

        Assert.Equal(ScanStatus.SafeToBuy, result.Status);
        await matcher.Received(2).IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ExecuteAsync_WhenImageValidationFails_ThrowsInputValidationException_AndSkipsDownstreamCalls()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();

        imageValidation
            .ValidateAsync(Arg.Any<Stream>(), Arg.Any<string?>(), Arg.Any<CancellationToken>())
            .Returns(ValidationResult.Fail("invalid_image", "Image signature mismatch."));

        var sut = new ScanWorkflowUseCase(imageValidation, pHash, cache, matcher, ownership, events);

        var ex = await Assert.ThrowsAsync<InputValidationException>(() => sut.ExecuteAsync(BuildCommand(Guid.NewGuid())));
        Assert.Equal("invalid_image", ex.Code);

        await pHash.DidNotReceiveWithAnyArgs().ComputeAsync(default!, default);
        await cache.DidNotReceiveWithAnyArgs().TryGetAsync(default, default!, default);
        await matcher.DidNotReceiveWithAnyArgs().IdentifyAsync(default!, default);
        await events.DidNotReceiveWithAnyArgs().AppendAsync(default!, default);
    }

    [Fact]
    public async Task ExecuteAsync_WhenCacheMissWithUserId_StoresResultAndAppendsEvent()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);
        var matched = ScanResult.SafeToBuy(Identity, 0.82f);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(matched);
        ownership.CheckAsync(userId, Identity, Arg.Any<CancellationToken>()).Returns((false, (Guid?)null));

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events);
        var command = BuildCommand(userId);

        var result = await sut.ExecuteAsync(command);

        Assert.Equal(ScanStatus.SafeToBuy, result.Status);
        await cache.Received(1).StoreAsync(
            userId,
            hash,
            result,
            Arg.Is<TimeSpan>(t => t == TimeSpan.FromHours(24)),
            Arg.Any<CancellationToken>());
        await events.Received(1).AppendAsync(
            Arg.Is<ScanEvent>(e =>
                e.UserId == userId &&
                e.ClientScanId == command.ClientScanId &&
                e.ResultStatus == ScanStatus.SafeToBuy &&
                e.AlbumIdentity == Identity),
            Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ExecuteAsync_WhenUserIdMissing_DoesNotStoreCacheOrAppendEvent()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();

        var hash = new PerceptualHash(42);
        var safe = ScanResult.SafeToBuy(Identity, 0.74f);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(safe);

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events);

        await sut.ExecuteAsync(BuildCommand(userId: null));

        await cache.DidNotReceiveWithAnyArgs().StoreAsync(default, default!, default!, default, default);
        await events.DidNotReceiveWithAnyArgs().AppendAsync(default!, default);
    }

    [Fact]
    public async Task ExecuteAsync_WhenMatcherThrowsNonTransient_DoesNotRetry()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>())
            .Returns(_ => Task.FromException<ScanResult>(new InvalidOperationException("fatal matcher error")));

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events);

        await Assert.ThrowsAsync<InvalidOperationException>(() => sut.ExecuteAsync(BuildCommand(userId)));
        await matcher.Received(1).IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ExecuteAsync_WhenMatcherTimesOutTwice_ThrowsAndStopsAfterSingleRetry()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>())
            .Returns(
                _ => Task.FromException<ScanResult>(new TimeoutException("first timeout")),
                _ => Task.FromException<ScanResult>(new TimeoutException("second timeout")));

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events);

        await Assert.ThrowsAsync<TimeoutException>(() => sut.ExecuteAsync(BuildCommand(userId)));
        await matcher.Received(2).IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>());
    }

    private static ScanCommand BuildCommand(Guid? userId)
    {
        var bytes = new byte[] { 0x01, 0x02, 0x03 };
        return new ScanCommand(userId, Guid.NewGuid(), new MemoryStream(bytes), "image/jpeg", DateTimeOffset.UtcNow, Guid.NewGuid());
    }
}
