namespace DejaGroove.Application.Commands;

public sealed record ResolveAmbiguousScanCommand(
    Guid UserId,
    Guid RequestId,
    string? SelectedMbid,
    string? SelectedDiscogsReleaseId);
