using DejaGroove.Application.Commands;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Scanning;

namespace DejaGroove.Application.UseCases;

public sealed class ScanWorkflowUseCase(
    IImageValidationPort imageValidation,
    IPerceptualHashPort perceptualHash,
    IScanCachePort scanCache,
    IAlbumMatchingPort albumMatching,
    ICollectionOwnershipPort collectionOwnership,
    IScanEventRepository scanEventRepository,
    IAmbiguousScanRepository ambiguousScans) : IScanWorkflowUseCase
{
    private static readonly TimeSpan CacheTtl = TimeSpan.FromHours(24);

    public async Task<ScanResult> ExecuteAsync(ScanCommand command, CancellationToken ct = default)
    {
        var imageBytes = await ReadImageAsync(command.ImageStream, ct);

        var validation = await imageValidation.ValidateAsync(CreateImageStream(imageBytes), command.ContentType, ct);
        if (!validation.IsValid)
            throw new InputValidationException(
                validation.ErrorCode ?? "validation_error",
                validation.ErrorMessage ?? "Image validation failed.");

        var hash = await perceptualHash.ComputeAsync(CreateImageStream(imageBytes), ct);

        if (command.UserId is Guid userId)
        {
            var cached = await scanCache.TryGetAsync(userId, hash, ct);
            if (cached is not null)
            {
                await PersistEventAsync(command, userId, cached, ct);
                return cached;
            }
        }

        var matched = await IdentifyWithSingleRetryAsync(imageBytes, ct);
        var finalResult = await ApplyOwnershipIfNeededAsync(command.UserId, matched, ct);

        if (command.UserId is Guid cacheUserId)
        {
            await scanCache.StoreAsync(cacheUserId, hash, finalResult, CacheTtl, ct);
            await PersistEventAsync(command, cacheUserId, finalResult, ct);
            await PersistAmbiguityStateBestEffortAsync(cacheUserId, command.RequestId, finalResult, ct);
        }

        return finalResult;
    }

    private async Task<ScanResult> IdentifyWithSingleRetryAsync(byte[] imageBytes, CancellationToken ct)
    {
        try
        {
            return await albumMatching.IdentifyAsync(CreateImageStream(imageBytes), ct);
        }
        catch (Exception ex) when (IsTransient(ex) && !ct.IsCancellationRequested)
        {
            return await albumMatching.IdentifyAsync(CreateImageStream(imageBytes), ct);
        }
    }

    private async Task<ScanResult> ApplyOwnershipIfNeededAsync(Guid? userId, ScanResult matched, CancellationToken ct)
    {
        if (userId is null || matched.Status != ScanStatus.SafeToBuy || matched.AlbumIdentity is null)
            return matched;

        var ownership = await collectionOwnership.CheckAsync(userId.Value, matched.AlbumIdentity, ct);
        return ownership.IsOwned
            ? ScanResult.Owned(matched.AlbumIdentity, ownership.CollectionRecordId, matched.Confidence)
            : matched;
    }

    private async Task PersistEventAsync(ScanCommand command, Guid userId, ScanResult result, CancellationToken ct)
    {
        var scanEvent = new ScanEvent(
            scanEventId: Guid.NewGuid(),
            userId: userId,
            clientScanId: command.ClientScanId,
            resultStatus: result.Status,
            confidence: result.Confidence,
            albumIdentity: result.AlbumIdentity,
            capturedAt: command.CapturedAt,
            createdAt: DateTimeOffset.UtcNow);

        await scanEventRepository.AppendAsync(scanEvent, ct);
    }

    private async Task PersistAmbiguityStateBestEffortAsync(Guid userId, Guid requestId, ScanResult result, CancellationToken ct)
    {
        try
        {
            await ambiguousScans.UpsertScanStatusAsync(userId, requestId, result.Status, ct);
            if (result.Status == ScanStatus.Ambiguous)
            {
                await ambiguousScans.UpsertAmbiguousAsync(new AmbiguousScanSnapshot(
                    userId,
                    requestId,
                    result.Confidence,
                    result.Candidates,
                    DateTimeOffset.UtcNow), ct);
            }
        }
        catch (ServiceUnavailableException)
        {
            // Keep scan flow available while resolve persistence is being rolled out.
        }
    }

    private static async Task<byte[]> ReadImageAsync(Stream input, CancellationToken ct)
    {
        using var buffer = new MemoryStream();
        await input.CopyToAsync(buffer, ct);
        return buffer.ToArray();
    }

    private static MemoryStream CreateImageStream(byte[] imageBytes) => new(imageBytes, writable: false);

    private static bool IsTransient(Exception ex) => ex is TimeoutException;
}
