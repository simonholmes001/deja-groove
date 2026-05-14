using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;
using Xunit;

namespace DejaGroove.Domain.Tests.Scanning;

public class ScanResultTests
{
    private static AlbumIdentity AnyIdentity() =>
        AlbumIdentity.Create(mbid: "mbid-1", discogsReleaseId: null, title: null, artist: null, year: null);

    [Fact]
    public void SafeToBuy_CreatesWithCorrectStatus()
    {
        var result = ScanResult.SafeToBuy(AnyIdentity(), confidence: 0.9f);
        Assert.Equal(ScanStatus.SafeToBuy, result.Status);
        Assert.Equal(0.9f, result.Confidence);
    }

    [Fact]
    public void NoMatch_CreatesWithCorrectStatus()
    {
        var result = ScanResult.NoMatch();
        Assert.Equal(ScanStatus.NoMatch, result.Status);
        Assert.Null(result.AlbumIdentity);
    }

    [Fact]
    public void Owned_RequiresCollectionRecordId()
    {
        var result = ScanResult.Owned(AnyIdentity(), collectionRecordId: Guid.NewGuid(), confidence: 0.95f);
        Assert.Equal(ScanStatus.Owned, result.Status);
        Assert.NotNull(result.CollectionRecordId);
    }

    [Fact]
    public void Owned_WithNullCollectionRecordId_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() =>
            ScanResult.Owned(AnyIdentity(), collectionRecordId: null, confidence: 0.95f));
    }

    [Fact]
    public void Ambiguous_RequiresNonEmptyCandidates()
    {
        var candidates = new[]
        {
            AlbumIdentity.Create(mbid: "mbid-2", discogsReleaseId: null, title: null, artist: null, year: null)
        };
        var result = ScanResult.Ambiguous(candidates, confidence: 0.6f);
        Assert.Equal(ScanStatus.Ambiguous, result.Status);
        Assert.NotEmpty(result.Candidates);
    }

    [Fact]
    public void Ambiguous_WithEmptyCandidates_ThrowsArgumentException()
    {
        Assert.Throws<ArgumentException>(() =>
            ScanResult.Ambiguous([], confidence: 0.4f));
    }

    [Fact]
    public void Ambiguous_CandidatesCappedAtThree()
    {
        var candidates = Enumerable.Range(1, 5)
            .Select(i => AlbumIdentity.Create(mbid: $"mbid-{i}", discogsReleaseId: null, title: null, artist: null, year: null))
            .ToArray();

        var result = ScanResult.Ambiguous(candidates, confidence: 0.5f);
        Assert.Equal(3, result.Candidates.Count);
    }

    [Fact]
    public void ConfidenceThreshold_MinimumIs075()
    {
        Assert.Equal(0.75f, ConfidenceThreshold.Minimum);
    }
}
