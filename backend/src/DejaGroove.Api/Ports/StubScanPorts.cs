using System.Collections.Concurrent;
using System.Security.Cryptography;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Api.Ports;

public sealed class StubImageValidationPort : IImageValidationPort
{
    public Task<ValidationResult> ValidateAsync(Stream imageStream, string? contentType, CancellationToken ct = default)
        => Task.FromResult(ValidationResult.Ok());
}

public sealed class StubPerceptualHashPort : IPerceptualHashPort
{
    public async Task<PerceptualHash> ComputeAsync(Stream imageStream, CancellationToken ct = default)
    {
        using var ms = new MemoryStream();
        await imageStream.CopyToAsync(ms, ct);
        var hash = SHA256.HashData(ms.ToArray());
        return new PerceptualHash(BitConverter.ToUInt64(hash, 0));
    }
}

public sealed class InMemoryScanCachePort : IScanCachePort
{
    private readonly ConcurrentDictionary<string, CacheEntry> _cache = new();

    public Task<ScanResult?> TryGetAsync(Guid userId, PerceptualHash hash, CancellationToken ct = default)
    {
        var key = BuildKey(userId, hash);
        if (!_cache.TryGetValue(key, out var entry) || entry.ExpiresAt <= DateTimeOffset.UtcNow)
        {
            _cache.TryRemove(key, out _);
            return Task.FromResult<ScanResult?>(null);
        }

        return Task.FromResult<ScanResult?>(entry.Result);
    }

    public Task StoreAsync(Guid userId, PerceptualHash hash, ScanResult result, TimeSpan ttl, CancellationToken ct = default)
    {
        var key = BuildKey(userId, hash);
        _cache[key] = new CacheEntry(result, DateTimeOffset.UtcNow.Add(ttl));
        return Task.CompletedTask;
    }

    private static string BuildKey(Guid userId, PerceptualHash hash) => $"{userId:N}:{hash.Value}";

    private sealed record CacheEntry(ScanResult Result, DateTimeOffset ExpiresAt);
}

public sealed class StubAlbumMatchingPort : IAlbumMatchingPort
{
    public Task<ScanResult> IdentifyAsync(Stream imageStream, CancellationToken ct = default)
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

public sealed class StubCollectionOwnershipPort : ICollectionOwnershipPort
{
    public Task<(bool IsOwned, Guid? CollectionRecordId)> CheckAsync(Guid userId, AlbumIdentity identity, CancellationToken ct = default)
        => Task.FromResult((false, (Guid?)null));
}

public sealed class InMemoryScanEventRepository : IScanEventRepository
{
    public Task AppendAsync(ScanEvent scanEvent, CancellationToken ct = default) => Task.CompletedTask;
}

public sealed class InMemoryAmbiguousScanRepository : IAmbiguousScanRepository
{
    private readonly ConcurrentDictionary<string, ScanStatus> _scanStatuses = new();
    private readonly ConcurrentDictionary<string, AmbiguousScanSnapshot> _ambiguous = new();
    private readonly ConcurrentDictionary<string, ResolvedScanSnapshot> _resolutions = new();

    public Task UpsertScanStatusAsync(Guid userId, Guid requestId, ScanStatus status, CancellationToken ct = default)
    {
        _scanStatuses[BuildKey(userId, requestId)] = status;
        return Task.CompletedTask;
    }

    public Task<ScanStatus?> GetScanStatusAsync(Guid userId, Guid requestId, CancellationToken ct = default)
    {
        var found = _scanStatuses.TryGetValue(BuildKey(userId, requestId), out var status);
        return Task.FromResult(found ? status : (ScanStatus?)null);
    }

    public Task UpsertAmbiguousAsync(AmbiguousScanSnapshot snapshot, CancellationToken ct = default)
    {
        _ambiguous[BuildKey(snapshot.UserId, snapshot.RequestId)] = snapshot;
        return Task.CompletedTask;
    }

    public Task<AmbiguousScanSnapshot?> GetAmbiguousAsync(Guid userId, Guid requestId, CancellationToken ct = default)
    {
        var found = _ambiguous.TryGetValue(BuildKey(userId, requestId), out var snapshot);
        return Task.FromResult(found ? snapshot : null);
    }

    public Task<ResolvedScanSnapshot?> GetResolutionAsync(Guid userId, Guid requestId, CancellationToken ct = default)
    {
        var found = _resolutions.TryGetValue(BuildKey(userId, requestId), out var snapshot);
        return Task.FromResult(found ? snapshot : null);
    }

    public Task PersistResolutionAsync(ResolvedScanSnapshot snapshot, CancellationToken ct = default)
    {
        _scanStatuses[BuildKey(snapshot.UserId, snapshot.RequestId)] = snapshot.Result.Status;
        _resolutions[BuildKey(snapshot.UserId, snapshot.RequestId)] = snapshot;
        return Task.CompletedTask;
    }

    private static string BuildKey(Guid userId, Guid requestId) => $"{userId:N}:{requestId:N}";
}

public sealed class UnconfiguredImageValidationPort : IImageValidationPort
{
    public Task<ValidationResult> ValidateAsync(Stream imageStream, string? contentType, CancellationToken ct = default) =>
        throw ScanPortErrors.Unconfigured();
}

public sealed class UnconfiguredPerceptualHashPort : IPerceptualHashPort
{
    public Task<PerceptualHash> ComputeAsync(Stream imageStream, CancellationToken ct = default) =>
        throw ScanPortErrors.Unconfigured();
}

public sealed class UnconfiguredScanCachePort : IScanCachePort
{
    public Task<ScanResult?> TryGetAsync(Guid userId, PerceptualHash hash, CancellationToken ct = default) =>
        throw ScanPortErrors.Unconfigured();

    public Task StoreAsync(Guid userId, PerceptualHash hash, ScanResult result, TimeSpan ttl, CancellationToken ct = default) =>
        throw ScanPortErrors.Unconfigured();
}

public sealed class UnconfiguredAlbumMatchingPort : IAlbumMatchingPort
{
    public Task<ScanResult> IdentifyAsync(Stream imageStream, CancellationToken ct = default) =>
        throw ScanPortErrors.Unconfigured();
}

public sealed class UnconfiguredCollectionOwnershipPort : ICollectionOwnershipPort
{
    public Task<(bool IsOwned, Guid? CollectionRecordId)> CheckAsync(Guid userId, AlbumIdentity identity, CancellationToken ct = default) =>
        throw ScanPortErrors.Unconfigured();
}

public sealed class UnconfiguredScanEventRepository : IScanEventRepository
{
    public Task AppendAsync(ScanEvent scanEvent, CancellationToken ct = default) =>
        throw ScanPortErrors.Unconfigured();
}

public sealed class UnconfiguredAmbiguousScanRepository : IAmbiguousScanRepository
{
    public Task UpsertScanStatusAsync(Guid userId, Guid requestId, ScanStatus status, CancellationToken ct = default) =>
        throw ScanPortErrors.Unconfigured();
    public Task<ScanStatus?> GetScanStatusAsync(Guid userId, Guid requestId, CancellationToken ct = default) =>
        throw ScanPortErrors.Unconfigured();
    public Task UpsertAmbiguousAsync(AmbiguousScanSnapshot snapshot, CancellationToken ct = default) =>
        throw ScanPortErrors.Unconfigured();
    public Task<AmbiguousScanSnapshot?> GetAmbiguousAsync(Guid userId, Guid requestId, CancellationToken ct = default) =>
        throw ScanPortErrors.Unconfigured();
    public Task<ResolvedScanSnapshot?> GetResolutionAsync(Guid userId, Guid requestId, CancellationToken ct = default) =>
        throw ScanPortErrors.Unconfigured();
    public Task PersistResolutionAsync(ResolvedScanSnapshot snapshot, CancellationToken ct = default) =>
        throw ScanPortErrors.Unconfigured();
}

internal static class ScanPortErrors
{
    public static ServiceUnavailableException Unconfigured() =>
        new("scan_dependencies_unconfigured", "Scan dependencies are not configured.");
}
