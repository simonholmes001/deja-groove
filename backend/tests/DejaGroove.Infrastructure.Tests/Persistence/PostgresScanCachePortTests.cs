using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;
using DejaGroove.Infrastructure.Persistence.Caching;

namespace DejaGroove.Infrastructure.Tests.Persistence;

/// <summary>Issue #79: stable (user, phash, version) cache key with the
/// uint64→BIGINT bitcast, TTL semantics, identity invalidation and purge.</summary>
[Trait("Category", "Integration")]
[Collection("postgres")]
public sealed class PostgresScanCachePortTests(PostgresFixture fx)
{
    private PostgresScanCachePort Cache() => new(fx.Factory);

    private static AlbumIdentity Album(string mbid) =>
        AlbumIdentity.Create(mbid, null, "Cached", "Artist", 1999);

    [Fact]
    public async Task Store_SafeToBuy_ThenGet_ReturnsResult()
    {
        var user = Guid.NewGuid();
        var hash = new PerceptualHash(0x0123_4567_89AB_CDEFUL);
        await Cache().StoreAsync(user, hash,
            ScanResult.SafeToBuy(Album("c-stb"), 0.91f), TimeSpan.FromHours(1));

        var hit = await Cache().TryGetAsync(user, hash);

        Assert.NotNull(hit);
        Assert.Equal(ScanStatus.SafeToBuy, hit!.Status);
        Assert.Equal("c-stb", hit.AlbumIdentity!.Mbid);
    }

    [Fact]
    public async Task Store_HighBitHash_RoundTripsThroughSignedBigint()
    {
        // 0xFFFF...F is uint64 max; as signed BIGINT it is -1. The read path
        // must reinterpret the same bits, so the lookup still hits.
        var user = Guid.NewGuid();
        var hash = new PerceptualHash(0xFFFF_FFFF_FFFF_FFFFUL);
        await Cache().StoreAsync(user, hash, ScanResult.NoMatch(), TimeSpan.FromHours(1));

        var hit = await Cache().TryGetAsync(user, hash);

        Assert.NotNull(hit);
        Assert.Equal(ScanStatus.NoMatch, hit!.Status);
    }

    [Fact]
    public async Task Get_ExpiredEntry_ReturnsNull()
    {
        var user = Guid.NewGuid();
        var hash = new PerceptualHash(42);
        await Cache().StoreAsync(user, hash,
            ScanResult.SafeToBuy(Album("c-exp"), 0.8f), TimeSpan.FromSeconds(-1));

        Assert.Null(await Cache().TryGetAsync(user, hash));
    }

    [Fact]
    public async Task Store_Ambiguous_IsNotCached()
    {
        var user = Guid.NewGuid();
        var hash = new PerceptualHash(7);
        await Cache().StoreAsync(user, hash,
            ScanResult.Ambiguous([Album("amb-1"), Album("amb-2")], 0.6f),
            TimeSpan.FromHours(1));

        Assert.Null(await Cache().TryGetAsync(user, hash));
    }

    [Fact]
    public async Task InvalidateForIdentity_RemovesMatchingEntries()
    {
        var user = Guid.NewGuid();
        var hash = new PerceptualHash(0xABCDUL);
        var album = Album("c-inv");
        await Cache().StoreAsync(user, hash,
            ScanResult.SafeToBuy(album, 0.95f), TimeSpan.FromHours(1));

        await Cache().InvalidateForIdentityAsync(user, album);

        Assert.Null(await Cache().TryGetAsync(user, hash));
    }

    [Fact]
    public async Task Purger_RemovesExpired_KeepsFresh()
    {
        var user = Guid.NewGuid();
        var expired = new PerceptualHash(100);
        var fresh = new PerceptualHash(200);
        await Cache().StoreAsync(user, expired, ScanResult.NoMatch(), TimeSpan.FromSeconds(-5));
        await Cache().StoreAsync(user, fresh,
            ScanResult.SafeToBuy(Album("c-fresh"), 0.9f), TimeSpan.FromHours(1));

        var removed = await new ScanCachePurger(fx.ConnectionString).PurgeExpiredAsync();

        Assert.True(removed >= 1);
        Assert.NotNull(await Cache().TryGetAsync(user, fresh));
    }
}
