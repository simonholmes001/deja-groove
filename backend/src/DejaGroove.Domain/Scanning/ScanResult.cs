using DejaGroove.Domain.Shared;

namespace DejaGroove.Domain.Scanning;

public sealed class ScanResult
{
    public ScanStatus Status { get; }
    public float Confidence { get; }
    public AlbumIdentity? AlbumIdentity { get; }
    public IReadOnlyList<AlbumIdentity> Candidates { get; }
    public Guid? CollectionRecordId { get; }

    private ScanResult(
        ScanStatus status,
        float confidence,
        AlbumIdentity? albumIdentity,
        IReadOnlyList<AlbumIdentity> candidates,
        Guid? collectionRecordId)
    {
        Status = status;
        Confidence = confidence;
        AlbumIdentity = albumIdentity;
        Candidates = candidates;
        CollectionRecordId = collectionRecordId;
    }

    public static ScanResult SafeToBuy(AlbumIdentity identity, float confidence) =>
        new(ScanStatus.SafeToBuy, confidence, identity, [], collectionRecordId: null);

    public static ScanResult NoMatch() =>
        new(ScanStatus.NoMatch, 0f, albumIdentity: null, [], collectionRecordId: null);

    public static ScanResult Owned(AlbumIdentity identity, Guid? collectionRecordId, float confidence)
    {
        if (collectionRecordId is null)
            throw new ArgumentException("Owned result requires a collectionRecordId.", nameof(collectionRecordId));

        return new(ScanStatus.Owned, confidence, identity, [], collectionRecordId);
    }

    public static ScanResult Ambiguous(IEnumerable<AlbumIdentity> candidates, float confidence)
    {
        var capped = candidates.Take(3).ToList();

        if (capped.Count == 0)
            throw new ArgumentException("Ambiguous result requires at least one candidate.", nameof(candidates));

        return new(ScanStatus.Ambiguous, confidence, albumIdentity: null, capped, collectionRecordId: null);
    }
}
