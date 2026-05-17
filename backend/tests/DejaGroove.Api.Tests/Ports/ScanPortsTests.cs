using DejaGroove.Api.Ports;
using DejaGroove.Application.Exceptions;
using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Api.Tests.Ports;

public sealed class ScanPortsTests
{
    [Fact]
    public async Task InMemoryScanCachePort_ReturnsMiss_WhenNoEntry()
    {
        var cache = new InMemoryScanCachePort();
        var result = await cache.TryGetAsync(Guid.NewGuid(), new PerceptualHash(1));
        Assert.Null(result);
    }

    [Fact]
    public async Task InMemoryScanCachePort_ReturnsHit_ForSameUserAndHash()
    {
        var cache = new InMemoryScanCachePort();
        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);
        var identity = AlbumIdentity.Create("m1", null, null, null, null);
        var scanResult = ScanResult.SafeToBuy(identity, 0.9f);

        await cache.StoreAsync(userId, hash, scanResult, TimeSpan.FromMinutes(5));
        var result = await cache.TryGetAsync(userId, hash);

        Assert.Same(scanResult, result);
    }

    [Fact]
    public async Task InMemoryScanCachePort_IsUserScoped()
    {
        var cache = new InMemoryScanCachePort();
        var hash = new PerceptualHash(42);
        var identity = AlbumIdentity.Create("m1", null, null, null, null);
        var scanResult = ScanResult.SafeToBuy(identity, 0.9f);

        await cache.StoreAsync(Guid.NewGuid(), hash, scanResult, TimeSpan.FromMinutes(5));
        var result = await cache.TryGetAsync(Guid.NewGuid(), hash);

        Assert.Null(result);
    }

    [Fact]
    public async Task InMemoryScanCachePort_EvictsExpiredEntries()
    {
        var cache = new InMemoryScanCachePort();
        var userId = Guid.NewGuid();
        var hash = new PerceptualHash(42);
        var identity = AlbumIdentity.Create("m1", null, null, null, null);
        var scanResult = ScanResult.SafeToBuy(identity, 0.9f);

        await cache.StoreAsync(userId, hash, scanResult, TimeSpan.FromMilliseconds(-1));
        var result = await cache.TryGetAsync(userId, hash);

        Assert.Null(result);
    }

    [Fact]
    public async Task UnconfiguredPorts_ThrowServiceUnavailableException()
    {
        var validation = new UnconfiguredImageValidationPort();
        var hash = new UnconfiguredPerceptualHashPort();
        var cache = new UnconfiguredScanCachePort();
        var matcher = new UnconfiguredAlbumMatchingPort();
        var ownership = new UnconfiguredCollectionOwnershipPort();
        var events = new UnconfiguredScanEventRepository();
        var identity = AlbumIdentity.Create("m1", null, null, null, null);

        await Assert.ThrowsAsync<ServiceUnavailableException>(() => validation.ValidateAsync(Stream.Null, "image/jpeg"));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => hash.ComputeAsync(Stream.Null));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => cache.TryGetAsync(Guid.NewGuid(), new PerceptualHash(1)));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => cache.StoreAsync(Guid.NewGuid(), new PerceptualHash(1), ScanResult.NoMatch(), TimeSpan.FromSeconds(1)));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => matcher.IdentifyAsync(Stream.Null));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => ownership.CheckAsync(Guid.NewGuid(), identity));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => events.AppendAsync(new ScanEvent(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), ScanStatus.NoMatch, 0, null, null, DateTimeOffset.UtcNow)));
    }
}
