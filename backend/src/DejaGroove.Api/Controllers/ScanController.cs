using DejaGroove.Api.Middleware;
using DejaGroove.Api.Requests;
using DejaGroove.Api.Errors;
using DejaGroove.Api.Responses;
using DejaGroove.Api.Features;
using DejaGroove.Application.Commands;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.UseCases;
using DejaGroove.Domain.Scanning;
using FluentValidation;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using System.Security.Claims;

namespace DejaGroove.Api.Controllers;

[ApiController]
[Route("v1")]
public sealed class ScanController(
    IScanWorkflowUseCase useCase,
    IResolveAmbiguousScanUseCase resolveUseCase,
    IValidator<ScanRequest> validator,
    IOptions<ScanFeaturesOptions> featureOptions) : ControllerBase
{
    private const long MaxImageBytes = 10 * 1024 * 1024;

    [HttpPost("scan")]
    [Consumes("multipart/form-data")]
    public async Task<IActionResult> PostAsync([FromForm] ScanRequest request, CancellationToken ct)
    {
        var requestId = HttpContext.Items[RequestIdMiddleware.RequestIdKey] is Guid g ? g : Guid.Empty;

        // 10 MB limit check — return 413 before validation
        if (request.Image != null && request.Image.Length > MaxImageBytes)
        {
            throw new HttpErrorException(413, "image_too_large", "Image must be ≤ 10 MB.", retryable: false);
        }

        var validation = await validator.ValidateAsync(request, ct);
        if (!validation.IsValid)
        {
            throw new InputValidationException(
                "validation_error",
                string.Join("; ", validation.Errors.Select(e => e.ErrorMessage)));
        }

        _ = Guid.TryParse(request.ClientScanId, out var clientScanId);
        _ = DateTimeOffset.TryParse(request.CapturedAt, out var capturedAt);

        await using var imageStream = request.Image!.OpenReadStream();

        var hasUserId = TryGetUserId(out var userId);

        var command = new ScanCommand(
            UserId: hasUserId ? userId : null,
            ClientScanId: clientScanId,
            ImageStream: imageStream,
            ContentType: request.Image.ContentType,
            CapturedAt: request.CapturedAt != null ? capturedAt : null,
            RequestId: requestId);

        var result = await useCase.ExecuteAsync(command, ct);

        return Ok(MapToResponse(result, requestId));
    }

    [Authorize(Policy = "IdentityContract")]
    [HttpPost("scan/{requestId:guid}/resolve")]
    public async Task<IActionResult> ResolveAsync([FromRoute] Guid requestId, [FromBody] ResolveScanRequest request, CancellationToken ct)
    {
        if (!featureOptions.Value.EnableResolveEndpoint)
            return NotFound();

        if (!TryGetUserId(out var userId))
        {
            var currentRequestId = HttpContext.Items[RequestIdMiddleware.RequestIdKey] is Guid g ? g : Guid.Empty;
            return Unauthorized(new ErrorResponse
            {
                Error = new ErrorDetail
                {
                    Code = "invalid_subject_claim",
                    Message = "Token subject must be a UUID.",
                    Retryable = false,
                    RequestId = currentRequestId
                }
            });
        }

        var command = new ResolveAmbiguousScanCommand(userId, requestId, request.SelectedMbid, request.SelectedDiscogsReleaseId);
        var resolved = await resolveUseCase.ExecuteAsync(command, ct);
        return Ok(MapToResponse(resolved, requestId));
    }

    private bool TryGetUserId(out Guid userId)
    {
        var subject = User.FindFirst("sub")?.Value ?? User.FindFirst(ClaimTypes.NameIdentifier)?.Value;
        return Guid.TryParse(subject, out userId);
    }

    private static ScanResponse MapToResponse(ScanResult result, Guid requestId)
    {
        AlbumDto? albumDto = null;
        if (result.AlbumIdentity is not null)
        {
            albumDto = new AlbumDto
            {
                Mbid = result.AlbumIdentity.Mbid,
                DiscogsReleaseId = result.AlbumIdentity.DiscogsReleaseId,
                Title = result.AlbumIdentity.Title ?? string.Empty,
                Artist = result.AlbumIdentity.Artist ?? string.Empty,
                Year = result.AlbumIdentity.Year
            };
        }

        var candidates = result.Candidates
            .Select(c => new CandidateDto
            {
                Mbid = c.Mbid,
                DiscogsReleaseId = c.DiscogsReleaseId,
                Title = c.Title ?? string.Empty,
                Artist = c.Artist ?? string.Empty,
                Year = c.Year
            })
            .ToList();

        return new ScanResponse
        {
            Status = MapStatus(result.Status),
            Confidence = result.Confidence,
            Album = albumDto,
            Candidates = candidates,
            RequestId = requestId
        };
    }

    private static string MapStatus(ScanStatus status) => status switch
    {
        ScanStatus.Owned => "owned",
        ScanStatus.SafeToBuy => "safe_to_buy",
        ScanStatus.Ambiguous => "ambiguous",
        ScanStatus.NoMatch => "no_match",
        _ => throw new ArgumentOutOfRangeException(nameof(status), status, "Unknown scan status.")
    };
}
