using DejaGroove.Application.Commands;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Scanning;
using Microsoft.Extensions.Logging;

namespace DejaGroove.Application.UseCases;

public sealed class ScanWorkflowUseCase(
    IImageValidationPort imageValidation,
    IPerceptualHashPort perceptualHash,
    IScanCachePort scanCache,
    IAlbumMatchingPort albumMatching,
    ICollectionOwnershipPort collectionOwnership,
    IScanEventRepository scanEventRepository,
    IAmbiguousScanRepository ambiguousScans,
    ILogger<ScanWorkflowUseCase> logger) : IScanWorkflowUseCase
{
    private static readonly TimeSpan CacheTtl = TimeSpan.FromHours(24);

    public async Task<ScanResult> ExecuteAsync(ScanCommand command, CancellationToken ct = default)
    {
        logger.LogInformation(
            "Processing scan request {RequestId} for user {UserId} with matcher {MatcherType}.",
            command.RequestId,
            command.UserId,
            albumMatching.GetType().Name);

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
                logger.LogInformation(
                    "Scan request {RequestId} cache hit for user {UserId}.",
                    command.RequestId,
                    userId);
                await PersistEventAsync(command, userId, cached, ct);
                logger.LogInformation(
                    "Scan request {RequestId} completed from cache with status {Status} and confidence {Confidence}.",
                    command.RequestId,
                    cached.Status,
                    cached.Confidence);
                return cached;
            }

            logger.LogInformation(
                "Scan request {RequestId} cache miss for user {UserId}.",
                command.RequestId,
                userId);
        }

        var matched = await IdentifyWithSingleRetryAsync(imageBytes, ct, command.RequestId);
        var finalResult = await ApplyOwnershipIfNeededAsync(command.UserId, matched, ct);

        if (command.UserId is Guid cacheUserId)
        {
            await scanCache.StoreAsync(cacheUserId, hash, finalResult, CacheTtl, ct);
            await PersistEventAsync(command, cacheUserId, finalResult, ct);
            await PersistAmbiguityStateBestEffortAsync(cacheUserId, command.RequestId, finalResult, ct);
        }

        logger.LogInformation(
            "Scan request {RequestId} completed with status {Status} and confidence {Confidence}.",
            command.RequestId,
            finalResult.Status,
            finalResult.Confidence);

        return finalResult;
    }

    private async Task<ScanResult> IdentifyWithSingleRetryAsync(byte[] imageBytes, CancellationToken ct, Guid requestId = default)
    {
        try
        {
            return await albumMatching.IdentifyAsync(CreateImageStream(imageBytes), ct);
        }
        catch (Exception ex) when (IsTransient(ex) && !ct.IsCancellationRequested)
        {
            logger.LogWarning(
                ex,
                "Transient scan recognition failure for request {RequestId}; retrying once.",
                requestId);
            return await albumMatching.IdentifyAsync(CreateImageStream(imageBytes), ct);
        }
    }

    private async Task<ScanResult> ApplyOwnershipIfNeededAsync(Guid? userId, ScanResult matched, CancellationToken ct)
    {
        if (userId is null || matched.Status != ScanStatus.SafeToBuy || matched.AlbumIdentity is null)
            return matched;

        var ownership = await collectionOwnership.CheckAsync(userId.Value, matched.AlbumIdentity, ct);
        logger.LogInformation(
            "Scan request ownership check for user {UserId}: owned={IsOwned}.",
            userId,
            ownership.IsOwned);
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
            logger.LogWarning(
                "Ambiguous scan persistence unavailable for request {RequestId}; continuing without persistence.",
                requestId);
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
