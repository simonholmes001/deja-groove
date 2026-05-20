using DejaGroove.Domain.Scanning;
using DejaGroove.Infrastructure.Recognition;

namespace DejaGroove.Infrastructure.Tests.Recognition;

/// <summary>
/// Issue #40: formalises the confidence → ScanStatus mapping. Pure, no I/O.
/// Boundary cases are derived from ConfidenceThreshold.Minimum (0.75) and the
/// ambiguity closeness band.
/// </summary>
public sealed class RecognitionResultMapperTests
{
    private static RecognitionCandidate Candidate(string title, string artist, float confidence, int? year = 1979)
        => new(title, artist, year, confidence);

    [Fact]
    public void NoCandidates_MapsToNoMatch()
    {
        var result = RecognitionResultMapper.Map([]);

        Assert.Equal(ScanStatus.NoMatch, result.Status);
        Assert.Null(result.AlbumIdentity);
    }

    [Fact]
    public void SingleConfidentCandidate_AtThreshold_MapsToSafeToBuy()
    {
        var result = RecognitionResultMapper.Map([Candidate("Unknown Pleasures", "Joy Division", 0.75f)]);

        Assert.Equal(ScanStatus.SafeToBuy, result.Status);
        Assert.Equal("Joy Division", result.AlbumIdentity!.Artist);
        Assert.Equal(0.75f, result.Confidence);
    }

    [Fact]
    public void SingleCandidate_BelowNoMatchFloor_MapsToNoMatch()
    {
        var result = RecognitionResultMapper.Map([Candidate("Blurry", "?", 0.20f)]);

        Assert.Equal(ScanStatus.NoMatch, result.Status);
    }

    [Fact]
    public void SingleCandidate_MidConfidence_BelowThreshold_MapsToNoMatch()
    {
        // One plausible-but-uncertain guess: nothing to disambiguate between,
        // and not confident enough to auto-accept.
        var result = RecognitionResultMapper.Map([Candidate("Closer", "Joy Division", 0.60f)]);

        Assert.Equal(ScanStatus.NoMatch, result.Status);
    }

    [Fact]
    public void TwoCloseCandidates_AboveFloor_MapsToAmbiguous()
    {
        var result = RecognitionResultMapper.Map(
        [
            Candidate("Greatest Hits", "Queen", 0.62f),
            Candidate("Greatest Hits II", "Queen", 0.58f),
        ]);

        Assert.Equal(ScanStatus.Ambiguous, result.Status);
        Assert.Equal(2, result.Candidates.Count);
    }

    [Fact]
    public void ConfidentTopButCloseRunnerUp_MapsToAmbiguous()
    {
        // Top is over threshold but a near-tie means we must not auto-accept.
        var result = RecognitionResultMapper.Map(
        [
            Candidate("Let It Be", "The Beatles", 0.80f),
            Candidate("Let It Be... Naked", "The Beatles", 0.74f),
        ]);

        Assert.Equal(ScanStatus.Ambiguous, result.Status);
    }

    [Fact]
    public void ConfidentTopWithDistantRunnerUp_MapsToSafeToBuy()
    {
        var result = RecognitionResultMapper.Map(
        [
            Candidate("Rumours", "Fleetwood Mac", 0.93f),
            Candidate("Tusk", "Fleetwood Mac", 0.40f),
        ]);

        Assert.Equal(ScanStatus.SafeToBuy, result.Status);
        Assert.Equal("Rumours", result.AlbumIdentity!.Title);
    }

    [Fact]
    public void CandidatesMissingTitleOrArtist_AreDiscarded()
    {
        // Vision returns no stable IDs, so a candidate needs BOTH title and
        // artist to form a valid AlbumIdentity; unusable ones are dropped.
        var result = RecognitionResultMapper.Map(
        [
            new RecognitionCandidate(Title: "Kind of Blue", Artist: null, Year: 1959, Confidence: 0.95f),
        ]);

        Assert.Equal(ScanStatus.NoMatch, result.Status);
    }

    [Fact]
    public void AmbiguousResult_IsCappedAtThreeCandidates()
    {
        var result = RecognitionResultMapper.Map(
        [
            Candidate("A", "Artist", 0.60f),
            Candidate("B", "Artist", 0.58f),
            Candidate("C", "Artist", 0.56f),
            Candidate("D", "Artist", 0.55f),
        ]);

        Assert.Equal(ScanStatus.Ambiguous, result.Status);
        Assert.Equal(3, result.Candidates.Count);
    }
}
