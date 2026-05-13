using DejaGroove.Api.Middleware;
using DejaGroove.Api.Requests;
using DejaGroove.Api.Responses;
using DejaGroove.Application.Commands;
using DejaGroove.Application.UseCases;
using DejaGroove.Domain.Scanning;
using FluentValidation;
using Microsoft.AspNetCore.Mvc;

namespace DejaGroove.Api.Controllers;

[ApiController]
[Route("v1")]
public sealed class ScanController(IScanWorkflowUseCase useCase, IValidator<ScanRequest> validator) : ControllerBase
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
            return StatusCode(413, new ErrorResponse
            {
                Error = new ErrorDetail
                {
                    Code = "image_too_large",
                    Message = "Image must be ≤ 10 MB.",
                    Retryable = false,
                    RequestId = requestId
                }
            });
        }

        var validation = await validator.ValidateAsync(request, ct);
        if (!validation.IsValid)
        {
            return BadRequest(new ErrorResponse
            {
                Error = new ErrorDetail
                {
                    Code = "validation_error",
                    Message = string.Join("; ", validation.Errors.Select(e => e.ErrorMessage)),
                    Retryable = false,
                    RequestId = requestId
                }
            });
        }

        _ = Guid.TryParse(request.ClientScanId, out var clientScanId);
        _ = DateTimeOffset.TryParse(request.CapturedAt, out var capturedAt);

        var command = new ScanCommand(
            UserId: Guid.NewGuid(), // TODO: replace with authenticated user from claims in #16
            ClientScanId: clientScanId,
            ImageStream: request.Image!.OpenReadStream(),
            ContentType: request.Image.ContentType,
            CapturedAt: request.CapturedAt != null ? capturedAt : null,
            RequestId: requestId);

        var result = await useCase.ExecuteAsync(command, ct);

        return Ok(MapToResponse(result, requestId));
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
            Status = result.Status.ToString().ToLowerInvariant(),
            Confidence = result.Confidence,
            Album = albumDto,
            Candidates = candidates,
            RequestId = requestId
        };
    }
}
