using DejaGroove.Application.Commands;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Scanning;

namespace DejaGroove.Application.UseCases;

public sealed class ResolveAmbiguousScanUseCase(
    IAmbiguousScanRepository ambiguousScans,
    ICollectionOwnershipPort ownership) : IResolveAmbiguousScanUseCase
{
    public async Task<ScanResult> ExecuteAsync(ResolveAmbiguousScanCommand command, CancellationToken ct = default)
    {
        var selected = FindSelectedIdentity(command);

        var existingResolution = await ambiguousScans.GetResolutionAsync(command.UserId, command.RequestId, ct);
        if (existingResolution is not null)
        {
            if (MatchesSelectedIdentity(existingResolution.SelectedIdentity, selected))
                return existingResolution.Result;

            throw new ConflictException("scan_already_resolved", "Scan request has already been resolved with a different selection.");
        }

        var status = await ambiguousScans.GetScanStatusAsync(command.UserId, command.RequestId, ct);
        if (status is null)
            throw new NotFoundException("scan_request_not_found", "Scan request was not found.");
        if (status != ScanStatus.Ambiguous)
            throw new ConflictException("scan_request_not_ambiguous", "Scan request is not in ambiguous status.");

        var ambiguous = await ambiguousScans.GetAmbiguousAsync(command.UserId, command.RequestId, ct);
        if (ambiguous is null)
            throw new ConflictException("scan_request_not_ambiguous", "Scan request is not in ambiguous status.");

        var candidate = ambiguous.Candidates.FirstOrDefault(c => MatchesSelectedIdentity(c, selected));
        if (candidate is null)
            throw new UnprocessableEntityException("candidate_not_in_original_set", "Selected identity is not part of the original candidate set.");

        var ownershipResult = await ownership.CheckAsync(command.UserId, candidate, ct);
        var resolved = ownershipResult.IsOwned
            ? ScanResult.Owned(candidate, ownershipResult.CollectionRecordId!.Value, ambiguous.Confidence)
            : ScanResult.SafeToBuy(candidate, ambiguous.Confidence);

        await ambiguousScans.SaveResolutionAsync(new ResolvedScanSnapshot(
            command.UserId,
            command.RequestId,
            candidate,
            resolved,
            DateTimeOffset.UtcNow), ct);

        await ambiguousScans.AppendResolutionAuditAsync(command.UserId, command.RequestId, candidate, ct);

        return resolved;
    }

    private static Domain.Shared.AlbumIdentity FindSelectedIdentity(ResolveAmbiguousScanCommand command)
    {
        if (string.IsNullOrWhiteSpace(command.SelectedMbid) && string.IsNullOrWhiteSpace(command.SelectedDiscogsReleaseId))
            throw new InputValidationException("validation_error", "Either selected_mbid or selected_discogs_release_id must be provided.");

        return Domain.Shared.AlbumIdentity.Create(
            command.SelectedMbid,
            command.SelectedDiscogsReleaseId,
            title: null,
            artist: null,
            year: null);
    }

    private static bool MatchesSelectedIdentity(Domain.Shared.AlbumIdentity candidate, Domain.Shared.AlbumIdentity selected)
    {
        if (!string.IsNullOrWhiteSpace(selected.Mbid))
            return string.Equals(candidate.Mbid, selected.Mbid, StringComparison.OrdinalIgnoreCase);

        if (!string.IsNullOrWhiteSpace(selected.DiscogsReleaseId))
            return string.Equals(candidate.DiscogsReleaseId, selected.DiscogsReleaseId, StringComparison.OrdinalIgnoreCase);

        return false;
    }
}
