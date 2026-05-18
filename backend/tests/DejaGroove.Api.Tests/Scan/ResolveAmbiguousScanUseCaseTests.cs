using DejaGroove.Application.Commands;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.Ports;
using DejaGroove.Application.UseCases;
using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;
using NSubstitute;

namespace DejaGroove.Api.Tests.Scan;

public sealed class ResolveAmbiguousScanUseCaseTests
{
    private static readonly AlbumIdentity Candidate = AlbumIdentity.Create("mbid-1", "123", "Kind of Blue", "Miles Davis", 1959);

    [Fact]
    public async Task ExecuteAsync_WhenRequestNotFound_ThrowsNotFound()
    {
        var repo = Substitute.For<IAmbiguousScanRepository>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        repo.GetScanStatusAsync(Arg.Any<Guid>(), Arg.Any<Guid>(), Arg.Any<CancellationToken>()).Returns((ScanStatus?)null);

        var sut = new ResolveAmbiguousScanUseCase(repo, ownership);

        await Assert.ThrowsAsync<NotFoundException>(() =>
            sut.ExecuteAsync(new ResolveAmbiguousScanCommand(Guid.NewGuid(), Guid.NewGuid(), "mbid-1", null)));
    }

    [Fact]
    public async Task ExecuteAsync_WhenNotAmbiguous_ThrowsConflict()
    {
        var repo = Substitute.For<IAmbiguousScanRepository>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        repo.GetScanStatusAsync(Arg.Any<Guid>(), Arg.Any<Guid>(), Arg.Any<CancellationToken>()).Returns(ScanStatus.SafeToBuy);

        var sut = new ResolveAmbiguousScanUseCase(repo, ownership);

        await Assert.ThrowsAsync<ConflictException>(() =>
            sut.ExecuteAsync(new ResolveAmbiguousScanCommand(Guid.NewGuid(), Guid.NewGuid(), "mbid-1", null)));
    }

    [Fact]
    public async Task ExecuteAsync_WhenSelectedIdentityIsNotCandidate_ThrowsUnprocessableEntity()
    {
        var userId = Guid.NewGuid();
        var requestId = Guid.NewGuid();
        var repo = Substitute.For<IAmbiguousScanRepository>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        repo.GetScanStatusAsync(userId, requestId, Arg.Any<CancellationToken>()).Returns(ScanStatus.Ambiguous);
        repo.GetAmbiguousAsync(userId, requestId, Arg.Any<CancellationToken>())
            .Returns(new AmbiguousScanSnapshot(userId, requestId, 0.5f, [Candidate], DateTimeOffset.UtcNow));

        var sut = new ResolveAmbiguousScanUseCase(repo, ownership);

        await Assert.ThrowsAsync<UnprocessableEntityException>(() =>
            sut.ExecuteAsync(new ResolveAmbiguousScanCommand(userId, requestId, "other", null)));
    }

    [Fact]
    public async Task ExecuteAsync_WhenAlreadyResolvedWithSameSelection_ReturnsExistingResult()
    {
        var userId = Guid.NewGuid();
        var requestId = Guid.NewGuid();
        var existing = ScanResult.SafeToBuy(Candidate, 0.7f);
        var repo = Substitute.For<IAmbiguousScanRepository>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();
        repo.GetResolutionAsync(userId, requestId, Arg.Any<CancellationToken>())
            .Returns(new ResolvedScanSnapshot(userId, requestId, Candidate, existing, DateTimeOffset.UtcNow));

        var sut = new ResolveAmbiguousScanUseCase(repo, ownership);
        var result = await sut.ExecuteAsync(new ResolveAmbiguousScanCommand(userId, requestId, Candidate.Mbid, Candidate.DiscogsReleaseId));

        Assert.Same(existing, result);
        await ownership.DidNotReceiveWithAnyArgs().CheckAsync(default, default!, default);
    }

    [Fact]
    public async Task ExecuteAsync_WhenCandidateHasBothIds_SelectionBySingleIdStillMatches()
    {
        var userId = Guid.NewGuid();
        var requestId = Guid.NewGuid();
        var repo = Substitute.For<IAmbiguousScanRepository>();
        var ownership = Substitute.For<ICollectionOwnershipPort>();

        repo.GetScanStatusAsync(userId, requestId, Arg.Any<CancellationToken>()).Returns(ScanStatus.Ambiguous);
        repo.GetAmbiguousAsync(userId, requestId, Arg.Any<CancellationToken>())
            .Returns(new AmbiguousScanSnapshot(userId, requestId, 0.5f, [Candidate], DateTimeOffset.UtcNow));
        ownership.CheckAsync(userId, Candidate, Arg.Any<CancellationToken>()).Returns((false, (Guid?)null));

        var sut = new ResolveAmbiguousScanUseCase(repo, ownership);
        var result = await sut.ExecuteAsync(new ResolveAmbiguousScanCommand(userId, requestId, Candidate.Mbid, null));

        Assert.Equal(ScanStatus.SafeToBuy, result.Status);
    }
}
