using DejaGroove.Api.Middleware;
using DejaGroove.Api.Requests;
using DejaGroove.Api.Responses;
using DejaGroove.Application.Collection;
using DejaGroove.Application.Ports;
using DejaGroove.Application.UseCases;
using DejaGroove.Domain.Shared;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace DejaGroove.Api.Controllers;

[ApiController]
[Route("v1/collection")]
[Authorize(Policy = "IdentityContract")]
public sealed class CollectionController(
    IAddToCollectionUseCase addUseCase,
    ICollectionQueryUseCase queryUseCase,
    ICurrentUser currentUser) : ControllerBase
{
    private const string IdempotencyHeader = "Idempotency-Key";

    [HttpPost]
    public async Task<IActionResult> AddAsync(
        [FromBody] AddCollectionItemRequest request, CancellationToken ct)
    {
        var requestId = RequestId();

        AlbumIdentity identity;
        try
        {
            identity = AlbumIdentity.Create(
                request.Mbid, request.DiscogsReleaseId, request.Title, request.Artist, request.Year);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(Error("validation_error", ex.Message, requestId));
        }

        Request.Headers.TryGetValue(IdempotencyHeader, out var key);

        var result = await addUseCase.ExecuteAsync(new AddToCollectionCommand
        {
            UserId = currentUser.UserId,
            Identity = identity,
            Notes = request.Notes,
            IdempotencyKey = key.ToString() is { Length: > 0 } k ? k : null,
            RequestFingerprint = request.Fingerprint(),
            AddAnyway = request.AddAnyway
        }, ct);

        return result.Outcome switch
        {
            AddToCollectionOutcome.Created =>
                Created($"/v1/collection/{result.Record!.Id}",
                    CollectionItemDto.From(result.Record!)),

            AddToCollectionOutcome.Replayed =>
                Ok(CollectionItemDto.From(result.Record!)),

            AddToCollectionOutcome.DuplicateDetected =>
                Conflict(new DuplicateDetectedDto
                {
                    Existing = CollectionItemDto.From(result.ExistingDuplicate!),
                    RequestId = requestId
                }),

            _ => throw new InvalidOperationException(
                $"Unhandled add outcome {result.Outcome}.")
        };
    }

    [HttpGet]
    public async Task<IActionResult> ListAsync(
        [FromQuery] string? search,
        [FromQuery] string? format,
        [FromQuery] string? sort,
        [FromQuery(Name = "dir")] string? direction,
        [FromQuery] string? cursor,
        [FromQuery] int? limit,
        CancellationToken ct)
    {
        if (!TryParseSort(sort, out var sortField))
            return BadRequest(Error("unsupported_sort",
                $"Unsupported sort field '{sort}'. Allowed: created_at, title, artist.",
                RequestId()));

        var query = new CollectionQuery
        {
            UserId = currentUser.UserId,
            Search = search,
            Format = format,
            SortField = sortField,
            SortDirection = string.Equals(direction, "asc", StringComparison.OrdinalIgnoreCase)
                ? SortDirection.Ascending
                : SortDirection.Descending,
            Cursor = CollectionCursor.TryDecode(cursor),
            Limit = limit ?? 25
        };

        var page = await queryUseCase.ListAsync(query, ct);

        return Ok(new CollectionPageDto
        {
            Items = page.Items.Select(CollectionItemDto.From).ToList(),
            NextCursor = page.NextCursor
        });
    }

    [HttpGet("{id:guid}")]
    public async Task<IActionResult> GetByIdAsync(Guid id, CancellationToken ct)
    {
        var record = await queryUseCase.GetAsync(currentUser.UserId, id, ct);
        return record is null
            ? NotFound(Error("not_found", "Collection record not found.", RequestId()))
            : Ok(CollectionItemDto.From(record));
    }

    private static bool TryParseSort(string? sort, out CollectionSortField field)
    {
        switch (sort?.Trim().ToLowerInvariant())
        {
            case null or "" or "created_at":
                field = CollectionSortField.CreatedAt;
                return true;
            case "title":
                field = CollectionSortField.Title;
                return true;
            case "artist":
                field = CollectionSortField.Artist;
                return true;
            default:
                // Year (nullable, not keyset-safe) and unknown values are
                // rejected rather than silently ignored.
                field = CollectionSortField.CreatedAt;
                return false;
        }
    }

    private Guid RequestId() =>
        HttpContext.Items[RequestIdMiddleware.RequestIdKey] is Guid g ? g : Guid.Empty;

    private static ErrorResponse Error(string code, string message, Guid requestId) => new()
    {
        Error = new ErrorDetail
        {
            Code = code,
            Message = message,
            Retryable = false,
            RequestId = requestId
        }
    };
}
