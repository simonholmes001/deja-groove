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
    public RecordFormat? Format { get; }
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
        RecordFormat? format,
        int version,
        DateTimeOffset createdAt,
        DateTimeOffset updatedAt,
        DateTimeOffset? deletedAt)
    {
        Id = id;
        UserId = userId;
        Identity = identity;
        Notes = notes;
        Format = format;
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
        DateTimeOffset now,
        RecordFormat? format = null)
    {
        if (userId == Guid.Empty)
            throw new ArgumentException("userId must not be empty.", nameof(userId));
        ArgumentNullException.ThrowIfNull(identity);

        return new CollectionRecord(
            id: Guid.NewGuid(),
            userId: userId,
            identity: identity,
            notes: notes,
            format: format,
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
        DateTimeOffset? deletedAt,
        RecordFormat? format = null) =>
        new(id, userId, identity, notes, format, version, createdAt, updatedAt, deletedAt);

    /// <summary>
    /// Returns a new <see cref="CollectionRecord"/> with the supplied values applied,
    /// an incremented <see cref="Version"/>, and <see cref="UpdatedAt"/> set to <paramref name="now"/>.
    /// All other fields (Id, UserId, Identity, CreatedAt, DeletedAt) are preserved.
    /// </summary>
    public CollectionRecord WithUpdate(RecordFormat? format, string? notes, DateTimeOffset now) =>
        new(Id, UserId, Identity, notes, format, Version + 1, CreatedAt, now, DeletedAt);
}
