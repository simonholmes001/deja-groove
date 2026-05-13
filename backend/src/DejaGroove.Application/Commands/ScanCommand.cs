namespace DejaGroove.Application.Commands;

public sealed record ScanCommand(
    Guid? UserId,     // Null until auth is wired in #16; ports must guard against null
    Guid ClientScanId,
    Stream ImageStream,
    string? ContentType,
    DateTimeOffset? CapturedAt,
    Guid RequestId);
