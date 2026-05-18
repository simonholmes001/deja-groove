using DejaGroove.Domain.Shared;

namespace DejaGroove.Domain.Collection;

/// <summary>
/// An album a user has declared they own. Entity root of the collection
/// aggregate. Soft-deleted (never hard-deleted outside GDPR erasure) so that
/// re-acquiring a previously owned release is permitted.
/// </summary>
public sealed class CollectionRecord
{
    public Guid Id { get; }
    public Guid UserId { get; }
    public AlbumIdentity Identity { get; }
    public string? Notes { get; }
    public int Version { get; }
    public DateTimeOffset CreatedAt { get; }
    public DateTimeOffset UpdatedAt { get; }
    public DateTimeOffset? DeletedAt { get; }

    public bool IsActive => DeletedAt is null;

    private CollectionRecord(
        Guid id,
        Guid userId,
        AlbumIdentity identity,
        string? notes,
        int version,
        DateTimeOffset createdAt,
        DateTimeOffset updatedAt,
        DateTimeOffset? deletedAt)
    {
        Id = id;
        UserId = userId;
        Identity = identity;
        Notes = notes;
        Version = version;
        CreatedAt = createdAt;
        UpdatedAt = updatedAt;
        DeletedAt = deletedAt;
    }

    /// <summary>Creates a new, active collection record for an owned album.</summary>
    public static CollectionRecord Create(
        Guid userId,
        AlbumIdentity identity,
        string? notes,
        DateTimeOffset now)
    {
        if (userId == Guid.Empty)
            throw new ArgumentException("userId must not be empty.", nameof(userId));
        ArgumentNullException.ThrowIfNull(identity);

        return new CollectionRecord(
            id: Guid.NewGuid(),
            userId: userId,
            identity: identity,
            notes: notes,
            version: 1,
            createdAt: now,
            updatedAt: now,
            deletedAt: null);
    }

    /// <summary>Reconstructs a record from its persisted state. No invariants
    /// are re-derived — the database row is the source of truth.</summary>
    public static CollectionRecord Rehydrate(
        Guid id,
        Guid userId,
        AlbumIdentity identity,
        string? notes,
        int version,
        DateTimeOffset createdAt,
        DateTimeOffset updatedAt,
        DateTimeOffset? deletedAt) =>
        new(id, userId, identity, notes, version, createdAt, updatedAt, deletedAt);
}
