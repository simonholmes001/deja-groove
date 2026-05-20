using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Infrastructure.Recognition;

/// <summary>
/// Issue #40: the confidence-scoring policy. Turns the vision model's ranked
/// candidates into a <see cref="ScanResult"/> status. Pure and deterministic —
/// no I/O, no clock, no randomness — so the decision boundaries are unit-testable.
/// </summary>
/// <remarks>
/// Decision order (after discarding candidates that cannot form an identity and
/// sorting by descending confidence):
/// <list type="number">
///   <item>no usable candidate → <see cref="ScanStatus.NoMatch"/></item>
///   <item>top confidence below <see cref="NoMatchFloor"/> → <see cref="ScanStatus.NoMatch"/></item>
///   <item>a runner-up within <see cref="AmbiguityDelta"/> of the top → <see cref="ScanStatus.Ambiguous"/></item>
///   <item>top confidence ≥ <see cref="ConfidenceThreshold.Minimum"/> → <see cref="ScanStatus.SafeToBuy"/></item>
///   <item>otherwise (a single uncertain guess) → <see cref="ScanStatus.NoMatch"/></item>
/// </list>
/// The auto-accept bar (<see cref="ConfidenceThreshold.Minimum"/>) is owned by
/// the domain; the floor and closeness band are recognition-tuning constants
/// and live with this adapter policy.
/// </remarks>
public static class RecognitionResultMapper
{
    /// <summary>Below this top confidence the scan is treated as unrecognised.</summary>
    public const float NoMatchFloor = 0.40f;

    /// <summary>A runner-up this close to the top makes the result contested.</summary>
    public const float AmbiguityDelta = 0.10f;

    public static ScanResult Map(IReadOnlyList<RecognitionCandidate> candidates)
    {
        var ranked = candidates
            .Where(static c => !string.IsNullOrWhiteSpace(c.Title) && !string.IsNullOrWhiteSpace(c.Artist))
            .OrderByDescending(static c => c.Confidence)
            .ToList();

        if (ranked.Count == 0)
            return ScanResult.NoMatch();

        var top = ranked[0];
        if (top.Confidence < NoMatchFloor)
            return ScanResult.NoMatch();

        var contested = ranked.Count >= 2 && top.Confidence - ranked[1].Confidence <= AmbiguityDelta;
        if (contested)
            return ScanResult.Ambiguous(ranked.Select(ToIdentity), top.Confidence);

        if (top.Confidence >= ConfidenceThreshold.Minimum)
            return ScanResult.SafeToBuy(ToIdentity(top), top.Confidence);

        return ScanResult.NoMatch();
    }

    private static AlbumIdentity ToIdentity(RecognitionCandidate candidate) =>
        AlbumIdentity.Create(
            mbid: null,
            discogsReleaseId: null,
            title: candidate.Title,
            artist: candidate.Artist,
            year: candidate.Year);
}
