using DejaGroove.Domain.Collection;

namespace DejaGroove.Application.Collection;

public sealed record UpdateCollectionCommand
{
    public required Guid UserId { get; init; }
    public required Guid RecordId { get; init; }

    /// <summary>New format value. <c>null</c> means "do not change".</summary>
    public RecordFormat? Format { get; init; }

    /// <summary>New notes value. <c>null</c> means "do not change".</summary>
    public string? Notes { get; init; }
}

public enum UpdateCollectionOutcome
{
    /// <summary>The record was updated successfully.</summary>
    Updated,

    /// <summary>The record does not exist or has been soft-deleted.</summary>
    NotFound,

    /// <summary>The record exists but is owned by a different user.</summary>
    Forbidden
}

public sealed record UpdateCollectionResult(UpdateCollectionOutcome Outcome, CollectionRecord? Record);
