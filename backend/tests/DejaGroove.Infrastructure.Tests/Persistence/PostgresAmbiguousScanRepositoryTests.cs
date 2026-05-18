using Dapper;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;
using DejaGroove.Infrastructure.Persistence.Scanning;
using Npgsql;

namespace DejaGroove.Infrastructure.Tests.Persistence;

[Trait("Category", "Integration")]
[Collection("postgres")]
public sealed class PostgresAmbiguousScanRepositoryTests(PostgresFixture fx)
{
    private PostgresAmbiguousScanRepository Repo() => new(fx.Factory);

    [Fact]
    public async Task UpsertAmbiguous_ThenGet_ReturnsCandidatesInOrder()
    {
        var user = Guid.NewGuid();
        var requestId = Guid.NewGuid();
        var c1 = AlbumIdentity.Create("m-1", null, "A", "AA", 2001);
        var c2 = AlbumIdentity.Create("m-2", null, "B", "BB", 2002);

        await Repo().UpsertScanStatusAsync(user, requestId, ScanStatus.Ambiguous);
        await Repo().UpsertAmbiguousAsync(new AmbiguousScanSnapshot(
            user, requestId, 0.6f, [c1, c2], DateTimeOffset.UtcNow));

        var loaded = await Repo().GetAmbiguousAsync(user, requestId);

        Assert.NotNull(loaded);
        Assert.Equal(2, loaded!.Candidates.Count);
        Assert.Equal("m-1", loaded.Candidates[0].Mbid);
        Assert.Equal("m-2", loaded.Candidates[1].Mbid);
    }

    [Fact]
    public async Task PersistResolutionAsync_UpdatesStatusAndWritesAuditAtomically()
    {
        var user = Guid.NewGuid();
        var requestId = Guid.NewGuid();
        var selected = AlbumIdentity.Create("sel-1", null, "S", "X", 1999);
        var result = ScanResult.SafeToBuy(selected, 0.77f);

        await Repo().UpsertScanStatusAsync(user, requestId, ScanStatus.Ambiguous);
        await Repo().PersistResolutionAsync(new ResolvedScanSnapshot(
            user, requestId, selected, result, DateTimeOffset.UtcNow));

        var status = await Repo().GetScanStatusAsync(user, requestId);
        var resolved = await Repo().GetResolutionAsync(user, requestId);

        Assert.Equal(ScanStatus.SafeToBuy, status);
        Assert.NotNull(resolved);
        Assert.Equal(ScanStatus.SafeToBuy, resolved!.Result.Status);

        await using var conn = new NpgsqlConnection(fx.ConnectionString);
        await conn.OpenAsync();

        var count = await conn.ExecuteScalarAsync<int>(
            "SELECT COUNT(*) FROM scan_resolution_audit_log WHERE user_id = @u AND request_id = @r",
            new { u = user, r = requestId });

        Assert.Equal(1, count);
    }

    [Fact]
    public async Task GetResolutionAsync_WhenMissing_ReturnsNull()
    {
        var resolved = await Repo().GetResolutionAsync(Guid.NewGuid(), Guid.NewGuid());
        Assert.Null(resolved);
    }

    [Fact]
    public async Task GetAmbiguousAsync_CrossUserRead_IsBlockedByRls()
    {
        var owner = Guid.NewGuid();
        var otherUser = Guid.NewGuid();
        var requestId = Guid.NewGuid();
        var candidate = AlbumIdentity.Create("owner-mbid", null, "Owner", "Artist", 2001);

        await Repo().UpsertScanStatusAsync(owner, requestId, ScanStatus.Ambiguous);
        await Repo().UpsertAmbiguousAsync(new AmbiguousScanSnapshot(
            owner, requestId, 0.61f, [candidate], DateTimeOffset.UtcNow));

        var ownerSnapshot = await Repo().GetAmbiguousAsync(owner, requestId);
        var otherSnapshot = await Repo().GetAmbiguousAsync(otherUser, requestId);

        Assert.NotNull(ownerSnapshot);
        Assert.Null(otherSnapshot);
    }

    [Fact]
    public async Task PersistResolutionAsync_CrossUserWrite_DoesNotAffectOwnerRows()
    {
        var owner = Guid.NewGuid();
        var otherUser = Guid.NewGuid();
        var requestId = Guid.NewGuid();

        var ownerSelected = AlbumIdentity.Create("owner-selected", null, "Owner", "Artist", 1991);
        await Repo().UpsertScanStatusAsync(owner, requestId, ScanStatus.Ambiguous);
        await Repo().PersistResolutionAsync(new ResolvedScanSnapshot(
            owner,
            requestId,
            ownerSelected,
            ScanResult.SafeToBuy(ownerSelected, 0.55f),
            DateTimeOffset.UtcNow));

        var otherSelected = AlbumIdentity.Create("other-selected", null, "Other", "Artist", 1992);
        await Repo().PersistResolutionAsync(new ResolvedScanSnapshot(
            otherUser,
            requestId,
            otherSelected,
            ScanResult.Owned(otherSelected, Guid.NewGuid(), 0.99f),
            DateTimeOffset.UtcNow));

        var ownerResolution = await Repo().GetResolutionAsync(owner, requestId);
        var ownerStatus = await Repo().GetScanStatusAsync(owner, requestId);

        Assert.NotNull(ownerResolution);
        Assert.Equal("owner-selected", ownerResolution!.SelectedIdentity.Mbid);
        Assert.Equal(ScanStatus.SafeToBuy, ownerStatus);
    }

    [Fact]
    public async Task GetScanStatusAsync_WhenMissing_ReturnsNull()
    {
        var status = await Repo().GetScanStatusAsync(Guid.NewGuid(), Guid.NewGuid());
        Assert.Null(status);
    }
}
