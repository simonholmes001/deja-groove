using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Domain.Tests.Scanning;

public sealed class ScanEventTests
{
    [Fact]
    public void Constructor_SetsAllProperties()
    {
        var album = AlbumIdentity.Create("mbid", "discogs", "Title", "Artist", 1999);
        var createdAt = DateTimeOffset.UtcNow;
        var capturedAt = createdAt.AddMinutes(-1);

        var evt = new ScanEvent(
            scanEventId: Guid.NewGuid(),
            userId: Guid.NewGuid(),
            clientScanId: Guid.NewGuid(),
            resultStatus: ScanStatus.Owned,
            confidence: 0.91f,
            albumIdentity: album,
            capturedAt: capturedAt,
            createdAt: createdAt);

        Assert.Equal(ScanStatus.Owned, evt.ResultStatus);
        Assert.Equal(0.91f, evt.Confidence);
        Assert.Equal(album, evt.AlbumIdentity);
        Assert.Equal(capturedAt, evt.CapturedAt);
        Assert.Equal(createdAt, evt.CreatedAt);
    }
}
