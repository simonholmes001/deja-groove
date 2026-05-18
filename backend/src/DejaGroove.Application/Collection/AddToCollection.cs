using DejaGroove.Domain.Collection;
using DejaGroove.Domain.Shared;

namespace DejaGroove.Application.Collection;

public sealed record AddToCollectionCommand
{
    public required Guid UserId { get; init; }
    public required AlbumIdentity Identity { get; init; }
    public string? Notes { get; init; }

    /// <summary>Client-supplied idempotency key. Null disables replay safety.</summary>
    public string? IdempotencyKey { get; init; }

    /// <summary>Stable hash of the request payload, used to detect a reused
    /// idempotency key carrying a different body.</summary>
    public string RequestFingerprint { get; init; } = string.Empty;

    /// <summary>When true, bypass duplicate detection and add anyway.</summary>
    public bool AddAnyway { get; init; }
}

public enum AddToCollectionOutcome
{
    /// <summary>A new record was created.</summary>
    Created,

    /// <summary>A prior request with the same idempotency key was replayed.</summary>
    Replayed,

    /// <summary>The album is already owned and <c>AddAnyway</c> was not set.</summary>
    DuplicateDetected
}

public sealed record AddToCollectionResult(
    AddToCollectionOutcome Outcome,
    CollectionRecord? Record,
    CollectionRecord? ExistingDuplicate)
{
    public static AddToCollectionResult Created(CollectionRecord record) =>
        new(AddToCollectionOutcome.Created, record, null);

    public static AddToCollectionResult Replayed(CollectionRecord record) =>
        new(AddToCollectionOutcome.Replayed, record, null);

    public static AddToCollectionResult Duplicate(CollectionRecord existing) =>
        new(AddToCollectionOutcome.DuplicateDetected, null, existing);
}
