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

        await Assert.ThrowsAsync<ServiceUnavailableException>(() => validation.ValidateAsync(ReadOnlyMemory<byte>.Empty, "image/jpeg"));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => hash.ComputeAsync(Stream.Null));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => cache.TryGetAsync(Guid.NewGuid(), new PerceptualHash(1)));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => cache.StoreAsync(Guid.NewGuid(), new PerceptualHash(1), ScanResult.NoMatch(), TimeSpan.FromSeconds(1)));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => matcher.IdentifyAsync(Stream.Null));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => ownership.CheckAsync(Guid.NewGuid(), identity));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => events.AppendAsync(new ScanEvent(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid(), ScanStatus.NoMatch, 0, null, null, DateTimeOffset.UtcNow)));
    }

    [Fact]
    public async Task ImageHeaderValidationPort_AcceptsJpegAndPngHeaders()
    {
        var validation = new ImageHeaderValidationPort();

        var jpeg = await validation.ValidateAsync(new byte[] { 0xFF, 0xD8, 0xFF, 0xE0 }, "image/jpeg");
        var png = await validation.ValidateAsync(new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A }, "image/png");

        Assert.True(jpeg.IsValid);
        Assert.True(png.IsValid);
    }

    [Fact]
    public async Task ImageHeaderValidationPort_RejectsUnsupportedHeader()
    {
        var validation = new ImageHeaderValidationPort();

        var result = await validation.ValidateAsync(new byte[] { 0x47, 0x49, 0x46 }, "image/gif");

        Assert.False(result.IsValid);
        Assert.Equal("unsupported_image", result.ErrorCode);
    }
}
