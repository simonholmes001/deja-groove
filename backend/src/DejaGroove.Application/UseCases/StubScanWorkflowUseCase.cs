using DejaGroove.Application.Commands;
using DejaGroove.Application.UseCases;
using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Application.UseCases;

/// <summary>
/// Stub implementation for #11. Returns a fixed safe_to_buy result.
/// Replaced by the real orchestration pipeline in #12.
/// </summary>
public sealed class StubScanWorkflowUseCase : IScanWorkflowUseCase
{
    public Task<ScanResult> ExecuteAsync(ScanCommand command, CancellationToken ct = default)
    {
        var identity = AlbumIdentity.Create(
            mbid: "stub-mbid-0000",
            discogsReleaseId: null,
            title: "Stub Album",
            artist: "Stub Artist",
            year: 2026);

        return Task.FromResult(ScanResult.SafeToBuy(identity, confidence: 0.99f));
    }
}
