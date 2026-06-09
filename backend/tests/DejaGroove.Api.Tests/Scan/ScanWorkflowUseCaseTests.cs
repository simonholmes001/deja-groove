using DejaGroove.Application.Commands;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.Ports;
using DejaGroove.Application.UseCases;
using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
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
        IScanEventRepository events,
        IAmbiguousScanRepository ambiguousScans,
        ILogger<ScanWorkflowUseCase>? logger = null)
    {
        imageValidation
            .ValidateAsync(Arg.Any<ReadOnlyMemory<byte>>(), Arg.Any<string?>(), Arg.Any<CancellationToken>())
            .Returns(ValidationResult.Ok());

        return new ScanWorkflowUseCase(
            imageValidation,
            pHash,
            cache,
            matcher,
            ownership,
            events,
            ambiguousScans,
            logger ?? NullLogger<ScanWorkflowUseCase>.Instance);
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
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);
        var cached = ScanResult.SafeToBuy(Identity, 0.88f);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns(cached);

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events, ambiguousScans);
        var command = BuildCommand(userId);

        var result = await sut.ExecuteAsync(command);

        Assert.Same(cached, result);
        await matcher.DidNotReceiveWithAnyArgs().IdentifyAsync(default!, default);
        await ownership.DidNotReceiveWithAnyArgs().CheckAsync(default, default!, default);
        await events.Received(1).AppendAsync(
            Arg.Is<ScanEvent>(e =>
                e.UserId == userId &&
                e.ClientScanId == command.ClientScanId &&
                e.ResultStatus == cached.Status),
            Arg.Any<CancellationToken>());
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
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();

        var userId = Guid.NewGuid();
        var recordId = Guid.NewGuid();
        var hash = new PerceptualHash(42);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(ScanResult.SafeToBuy(Identity, 0.91f));
        ownership.CheckAsync(userId, Identity, Arg.Any<CancellationToken>()).Returns((true, (Guid?)recordId));

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events, ambiguousScans);
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
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);
        var ambiguous = ScanResult.Ambiguous([Identity], 0.52f);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(ambiguous);

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events, ambiguousScans);
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
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();

        var hash = new PerceptualHash(42);
        var safe = ScanResult.SafeToBuy(Identity, 0.74f);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(safe);

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events, ambiguousScans);
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
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>())
            .Returns(_ => throw new TimeoutException("first attempt timed out"), _ => ScanResult.SafeToBuy(Identity, 0.93f));
        ownership.CheckAsync(userId, Identity, Arg.Any<CancellationToken>()).Returns((false, (Guid?)null));

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events, ambiguousScans);
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
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();

        imageValidation
            .ValidateAsync(Arg.Any<ReadOnlyMemory<byte>>(), Arg.Any<string?>(), Arg.Any<CancellationToken>())
            .Returns(ValidationResult.Fail("invalid_image", "Image signature mismatch."));

        var sut = new ScanWorkflowUseCase(
            imageValidation,
            pHash,
            cache,
            matcher,
            ownership,
            events,
            ambiguousScans,
            NullLogger<ScanWorkflowUseCase>.Instance);

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
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);
        var matched = ScanResult.SafeToBuy(Identity, 0.82f);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(matched);
        ownership.CheckAsync(userId, Identity, Arg.Any<CancellationToken>()).Returns((false, (Guid?)null));

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events, ambiguousScans);
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
        await ambiguousScans.Received(1).UpsertScanStatusAsync(userId, command.RequestId, ScanStatus.SafeToBuy, Arg.Any<CancellationToken>());
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
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();

        var hash = new PerceptualHash(42);
        var safe = ScanResult.SafeToBuy(Identity, 0.74f);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(safe);

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events, ambiguousScans);

        await sut.ExecuteAsync(BuildCommand(userId: null));

        await cache.DidNotReceiveWithAnyArgs().StoreAsync(default, default!, default!, default, default);
        await events.DidNotReceiveWithAnyArgs().AppendAsync(default!, default);
        await ambiguousScans.DidNotReceiveWithAnyArgs().UpsertScanStatusAsync(default, default, default, default);
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
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>())
            .Returns(_ => Task.FromException<ScanResult>(new InvalidOperationException("fatal matcher error")));

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events, ambiguousScans);

        await Assert.ThrowsAsync<InvalidOperationException>(() => sut.ExecuteAsync(BuildCommand(userId)));
        await matcher.Received(1).IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ExecuteAsync_WhenAmbiguityPersistenceUnavailable_DoesNotFailScan()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);
        var matched = ScanResult.SafeToBuy(Identity, 0.82f);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(matched);
        ownership.CheckAsync(userId, Identity, Arg.Any<CancellationToken>()).Returns((false, (Guid?)null));
        ambiguousScans.UpsertScanStatusAsync(userId, Arg.Any<Guid>(), ScanStatus.SafeToBuy, Arg.Any<CancellationToken>())
            .Returns(_ => throw new ServiceUnavailableException("scan_dependencies_unconfigured", "down"));

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events, ambiguousScans);
        var result = await sut.ExecuteAsync(BuildCommand(userId));

        Assert.Equal(ScanStatus.SafeToBuy, result.Status);
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
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>())
            .Returns(
                _ => Task.FromException<ScanResult>(new TimeoutException("first timeout")),
                _ => Task.FromException<ScanResult>(new TimeoutException("second timeout")));

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events, ambiguousScans);

        await Assert.ThrowsAsync<TimeoutException>(() => sut.ExecuteAsync(BuildCommand(userId)));
        await matcher.Received(2).IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task ExecuteAsync_WhenCacheHit_LogsCacheHit()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();
        var logger = new RecordingLogger<ScanWorkflowUseCase>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);
        var cached = ScanResult.SafeToBuy(Identity, 0.88f);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns(cached);

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events, ambiguousScans, logger);
        var command = BuildCommand(userId);

        await sut.ExecuteAsync(command);

        Assert.Contains(logger.Entries, entry =>
            entry.Level == LogLevel.Information &&
            entry.Message.Contains("cache hit", StringComparison.OrdinalIgnoreCase) &&
            entry.Message.Contains(command.RequestId.ToString(), StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task ExecuteAsync_WhenMatcherFailsTransiently_LogsRetry()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();
        var logger = new RecordingLogger<ScanWorkflowUseCase>();

        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);

        pHash.ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>()).Returns(hash);
        cache.TryGetAsync(userId, hash, Arg.Any<CancellationToken>()).Returns((ScanResult?)null);
        matcher.IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>())
            .Returns(_ => throw new TimeoutException("first attempt timed out"), _ => ScanResult.SafeToBuy(Identity, 0.93f));
        ownership.CheckAsync(userId, Identity, Arg.Any<CancellationToken>()).Returns((false, (Guid?)null));

        var sut = CreateSut(imageValidation, pHash, cache, matcher, ownership, events, ambiguousScans, logger);
        var command = BuildCommand(userId);

        await sut.ExecuteAsync(command);

        Assert.Contains(logger.Entries, entry =>
            entry.Level == LogLevel.Warning &&
            entry.Message.Contains("retry", StringComparison.OrdinalIgnoreCase) &&
            entry.Message.Contains(command.RequestId.ToString(), StringComparison.OrdinalIgnoreCase));
    }

    [Fact]
    public async Task ExecuteAsync_WithNonSeekableInput_PassesCompleteImageBytesToValidationHashAndMatcher()
    {
        var imageValidation = Substitute.For<IImageValidationPort>();
        var pHash = Substitute.For<IPerceptualHashPort>();
        var cache = Substitute.For<IScanCachePort>();
        var matcher = Substitute.For<IAlbumMatchingPort>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        var events = Substitute.For<IScanEventRepository>();
        var ambiguousScans = Substitute.For<IAmbiguousScanRepository>();
        var imageBytes = new byte[] { 0xFF, 0xD8, 0xFF, 0xE0, 0x10, 0x20, 0x30 };
        byte[]? validatedBytes = null;
        byte[]? hashedBytes = null;
        byte[]? matchedBytes = null;

        imageValidation
            .ValidateAsync(Arg.Any<ReadOnlyMemory<byte>>(), Arg.Any<string?>(), Arg.Any<CancellationToken>())
            .Returns(call =>
            {
                validatedBytes = call.ArgAt<ReadOnlyMemory<byte>>(0).ToArray();
                return ValidationResult.Ok();
            });
        pHash
            .ComputeAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>())
            .Returns(async call =>
            {
                hashedBytes = await ReadAllAsync(call.ArgAt<Stream>(0));
                return new PerceptualHash(42);
            });
        matcher
            .IdentifyAsync(Arg.Any<Stream>(), Arg.Any<CancellationToken>())
            .Returns(async call =>
            {
                matchedBytes = await ReadAllAsync(call.ArgAt<Stream>(0));
                return ScanResult.SafeToBuy(Identity, 0.91f);
            });

        var sut = new ScanWorkflowUseCase(
            imageValidation,
            pHash,
            cache,
            matcher,
            ownership,
            events,
            ambiguousScans,
            NullLogger<ScanWorkflowUseCase>.Instance);
        var command = new ScanCommand(
            UserId: null,
            ClientScanId: Guid.NewGuid(),
            ImageStream: new NonSeekableReadStream(imageBytes),
            ContentType: "image/jpeg",
            CapturedAt: DateTimeOffset.UtcNow,
            RequestId: Guid.NewGuid());

        await sut.ExecuteAsync(command);

        Assert.Equal(imageBytes, validatedBytes);
        Assert.Equal(imageBytes, hashedBytes);
        Assert.Equal(imageBytes, matchedBytes);
    }

    private static ScanCommand BuildCommand(Guid? userId)
    {
        var bytes = new byte[] { 0x01, 0x02, 0x03 };
        return new ScanCommand(userId, Guid.NewGuid(), new MemoryStream(bytes), "image/jpeg", DateTimeOffset.UtcNow, Guid.NewGuid());
    }

    private static async Task<byte[]> ReadAllAsync(Stream stream)
    {
        using var buffer = new MemoryStream();
        await stream.CopyToAsync(buffer);
        return buffer.ToArray();
    }

    private sealed class NonSeekableReadStream(byte[] bytes) : MemoryStream(bytes)
    {
        public override bool CanSeek => false;

        public override long Length => throw new NotSupportedException();

        public override long Position
        {
            get => throw new NotSupportedException();
            set => throw new NotSupportedException();
        }

        public override long Seek(long offset, SeekOrigin loc) => throw new NotSupportedException();
    }

    private sealed class RecordingLogger<T> : ILogger<T>
    {
        public List<LogEntry> Entries { get; } = [];

        public IDisposable BeginScope<TState>(TState state) where TState : notnull => NullScope.Instance;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            Entries.Add(new LogEntry(logLevel, formatter(state, exception)));
        }

        public sealed record LogEntry(LogLevel Level, string Message);

        private sealed class NullScope : IDisposable
        {
            public static readonly NullScope Instance = new();
            public void Dispose() { }
        }
    }
}
