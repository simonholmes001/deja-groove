namespace DejaGroove.Application.Exceptions;

/// <summary>
/// Raised by the repository when a concurrent insert loses the race against a
/// unique constraint (<c>ux_collection_records_user_mbid</c> /
/// <c>_user_discogs</c>). The use case translates this into a normal
/// duplicate-detected response so two simultaneous adds behave like a sequential
/// add followed by a duplicate.
/// </summary>
public sealed class DuplicateCollectionRecordException(string message)
    : Exception(message);
