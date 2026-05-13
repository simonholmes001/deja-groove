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
}
