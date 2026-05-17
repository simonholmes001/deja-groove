using DejaGroove.Domain.Shared;
using Xunit;

namespace DejaGroove.Domain.Tests.Scanning;

public class AlbumIdentityTests
{
    [Fact]
    public void Create_WithMbid_Succeeds()
    {
        var identity = AlbumIdentity.Create(mbid: "some-mbid", discogsReleaseId: null, title: null, artist: null, year: null);
        Assert.Equal("some-mbid", identity.Mbid);
    }

    [Fact]
    public void Create_WithDiscogsReleaseId_Succeeds()
    {
        var identity = AlbumIdentity.Create(mbid: null, discogsReleaseId: "12345", title: null, artist: null, year: null);
        Assert.Equal("12345", identity.DiscogsReleaseId);
    }

    [Fact]
    public void Create_WithTitleAndArtist_Succeeds()
    {
        var identity = AlbumIdentity.Create(mbid: null, discogsReleaseId: null, title: "Kind of Blue", artist: "Miles Davis", year: 1959);
        Assert.Equal("Kind of Blue", identity.Title);
        Assert.Equal("Miles Davis", identity.Artist);
    }

    [Fact]
    public void Create_AllNull_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() =>
            AlbumIdentity.Create(mbid: null, discogsReleaseId: null, title: null, artist: null, year: null));
    }

    [Fact]
    public void Create_TitleWithoutArtist_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() =>
            AlbumIdentity.Create(mbid: null, discogsReleaseId: null, title: "Kind of Blue", artist: null, year: null));
    }

    [Fact]
    public void Create_ArtistWithoutTitle_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() =>
            AlbumIdentity.Create(mbid: null, discogsReleaseId: null, title: null, artist: "Miles Davis", year: null));
    }

    [Fact]
    public void Equality_SameMbid_AreEqual()
    {
        var a = AlbumIdentity.Create(mbid: "mbid-1", discogsReleaseId: null, title: null, artist: null, year: null);
        var b = AlbumIdentity.Create(mbid: "mbid-1", discogsReleaseId: null, title: null, artist: null, year: null);
        Assert.Equal(a, b);
    }

    [Fact]
    public void Equality_MbidTakesPrecedenceOverTitleArtist()
    {
        var a = AlbumIdentity.Create(mbid: "mbid-1", discogsReleaseId: null, title: "Title A", artist: "Artist A", year: null);
        var b = AlbumIdentity.Create(mbid: "mbid-1", discogsReleaseId: null, title: "Title B", artist: "Artist B", year: null);
        Assert.Equal(a, b);
    }

    [Fact]
    public void Equality_OneHasDiscogsOtherHasOnlyTitleArtist_AreNotEqual()
    {
        // Regression: previously Equals() fell through to Title+Artist even when one side had DiscogsReleaseId.
        // This violated the GetHashCode contract (equal objects must have equal hash codes).
        var withDiscogs = AlbumIdentity.Create(mbid: null, discogsReleaseId: "12345", title: "Album", artist: "Artist", year: null);
        var withoutDiscogs = AlbumIdentity.Create(mbid: null, discogsReleaseId: null, title: "Album", artist: "Artist", year: null);
        Assert.NotEqual(withDiscogs, withoutDiscogs);
    }

    [Fact]
    public void HashCode_EqualObjects_HaveSameHashCode()
    {
        var a = AlbumIdentity.Create(mbid: null, discogsReleaseId: null, title: "Kind of Blue", artist: "Miles Davis", year: null);
        var b = AlbumIdentity.Create(mbid: null, discogsReleaseId: null, title: "Kind of Blue", artist: "Miles Davis", year: null);
        Assert.Equal(a, b);
        Assert.Equal(a.GetHashCode(), b.GetHashCode());
    }

    [Fact]
    public void HashCode_ContractHolds_WorksAsHashSetKey()
    {
        var a = AlbumIdentity.Create(mbid: "mbid-1", discogsReleaseId: null, title: null, artist: null, year: null);
        var b = AlbumIdentity.Create(mbid: "mbid-1", discogsReleaseId: null, title: null, artist: null, year: null);
        var set = new HashSet<AlbumIdentity> { a };
        Assert.Contains(b, set); // would silently fail if Equals/GetHashCode contract was broken
    }

    [Fact]
    public void Equality_MissingMbidOnOneSide_NotEqualEvenIfTitleMatches()
    {
        var withMbid = AlbumIdentity.Create(mbid: "mbid-1", discogsReleaseId: null, title: "A", artist: "B", year: null);
        var withoutMbid = AlbumIdentity.Create(mbid: null, discogsReleaseId: null, title: "A", artist: "B", year: null);
        Assert.NotEqual(withMbid, withoutMbid);
    }

    [Fact]
    public void Equality_DiscogsMatching_IsCaseInsensitive()
    {
        var a = AlbumIdentity.Create(mbid: null, discogsReleaseId: "AbC123", title: null, artist: null, year: null);
        var b = AlbumIdentity.Create(mbid: null, discogsReleaseId: "abc123", title: null, artist: null, year: null);
        Assert.Equal(a, b);
    }

    [Fact]
    public void Equality_TitleArtistMatching_IsCaseInsensitive()
    {
        var a = AlbumIdentity.Create(mbid: null, discogsReleaseId: null, title: "Kind Of Blue", artist: "Miles Davis", year: null);
        var b = AlbumIdentity.Create(mbid: null, discogsReleaseId: null, title: "kind of blue", artist: "miles davis", year: null);
        Assert.Equal(a, b);
    }

    [Fact]
    public void Equals_WithNull_ReturnsFalse()
    {
        var a = AlbumIdentity.Create(mbid: "mbid-1", discogsReleaseId: null, title: null, artist: null, year: null);
        Assert.False(a.Equals(null));
    }

    [Fact]
    public void ToString_UsesExpectedBranch()
    {
        var mbid = AlbumIdentity.Create(mbid: "m1", discogsReleaseId: null, title: null, artist: null, year: null);
        var discogs = AlbumIdentity.Create(mbid: null, discogsReleaseId: "d1", title: null, artist: null, year: null);
        var fallback = AlbumIdentity.Create(mbid: null, discogsReleaseId: null, title: "T", artist: "A", year: null);

        Assert.Equal("mbid:m1", mbid.ToString());
        Assert.Equal("discogs:d1", discogs.ToString());
        Assert.Equal("A – T", fallback.ToString());
    }
}
