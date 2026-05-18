using DejaGroove.Domain.Scanning;

namespace DejaGroove.Application.Ports;

public record ValidationResult(bool IsValid, string? ErrorCode = null, string? ErrorMessage = null)
{
    public static ValidationResult Ok() => new(true);
    public static ValidationResult Fail(string code, string message) => new(false, code, message);
}

public interface IImageValidationPort
{
    Task<ValidationResult> ValidateAsync(Stream imageStream, string? contentType, CancellationToken ct = default);
}

public interface IPerceptualHashPort
{
    Task<PerceptualHash> ComputeAsync(Stream imageStream, CancellationToken ct = default);
}

public interface IScanCachePort
{
    Task<ScanResult?> TryGetAsync(Guid userId, PerceptualHash hash, CancellationToken ct = default);
    Task StoreAsync(Guid userId, PerceptualHash hash, ScanResult result, TimeSpan ttl, CancellationToken ct = default);
}

/// <summary>Out-of-band maintenance for the pHash cache (issue #79):
/// time-based eviction of expired entries.</summary>
public interface IScanCacheMaintenance
{
    Task<int> PurgeExpiredAsync(CancellationToken ct = default);
}

public interface IAlbumMatchingPort
{
    Task<ScanResult> IdentifyAsync(Stream imageStream, CancellationToken ct = default);
}

public interface ICollectionOwnershipPort
{
    Task<(bool IsOwned, Guid? CollectionRecordId)> CheckAsync(Guid userId, Domain.Shared.AlbumIdentity identity, CancellationToken ct = default);
}

public interface IScanEventRepository
{
    Task AppendAsync(Domain.Scanning.ScanEvent scanEvent, CancellationToken ct = default);
}
