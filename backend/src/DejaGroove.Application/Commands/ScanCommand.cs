namespace DejaGroove.Application.Commands;

public sealed record ScanCommand(
    Guid UserId,
    Guid ClientScanId,
    Stream ImageStream,
    string? ContentType,
    DateTimeOffset? CapturedAt,
    Guid RequestId);
