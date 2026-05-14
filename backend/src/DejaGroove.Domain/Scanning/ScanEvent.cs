using DejaGroove.Domain.Shared;

namespace DejaGroove.Domain.Scanning;

/// <summary>Append-only audit log of every scan attempt. Immutable once created.</summary>
public sealed class ScanEvent
{
    public Guid ScanEventId { get; }
    public Guid UserId { get; }
    public Guid ClientScanId { get; }
    public ScanStatus ResultStatus { get; }
    public float Confidence { get; }
    public AlbumIdentity? AlbumIdentity { get; }
    public DateTimeOffset? CapturedAt { get; }
    public DateTimeOffset CreatedAt { get; }

    public ScanEvent(
        Guid scanEventId,
        Guid userId,
        Guid clientScanId,
        ScanStatus resultStatus,
        float confidence,
        AlbumIdentity? albumIdentity,
        DateTimeOffset? capturedAt,
        DateTimeOffset createdAt)
    {
        ScanEventId = scanEventId;
        UserId = userId;
        ClientScanId = clientScanId;
        ResultStatus = resultStatus;
        Confidence = confidence;
        AlbumIdentity = albumIdentity;
        CapturedAt = capturedAt;
        CreatedAt = createdAt;
    }
}
