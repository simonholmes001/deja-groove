namespace DejaGroove.Domain.Shared;

public sealed class AlbumIdentity : IEquatable<AlbumIdentity>
{
    public string? Mbid { get; }
    public string? DiscogsReleaseId { get; }
    public string? Title { get; }
    public string? Artist { get; }
    public int? Year { get; }

    private AlbumIdentity(string? mbid, string? discogsReleaseId, string? title, string? artist, int? year)
    {
        Mbid = mbid;
        DiscogsReleaseId = discogsReleaseId;
        Title = title;
        Artist = artist;
        Year = year;
    }

    public static AlbumIdentity Create(string? mbid, string? discogsReleaseId, string? title, string? artist, int? year)
    {
        bool hasStableId = mbid != null || discogsReleaseId != null;
        bool hasTitleAndArtist = title != null && artist != null;

        if (!hasStableId && !hasTitleAndArtist)
            throw new ArgumentException(
                "AlbumIdentity requires at least one stable ID (mbid or discogsReleaseId), or both title and artist.");

        return new AlbumIdentity(mbid, discogsReleaseId, title, artist, year);
    }

    public bool Equals(AlbumIdentity? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;

        // Mbid takes precedence
        if (Mbid != null && other.Mbid != null)
            return string.Equals(Mbid, other.Mbid, StringComparison.OrdinalIgnoreCase);

        if (DiscogsReleaseId != null && other.DiscogsReleaseId != null)
            return string.Equals(DiscogsReleaseId, other.DiscogsReleaseId, StringComparison.OrdinalIgnoreCase);

        return string.Equals(Title?.ToUpperInvariant(), other.Title?.ToUpperInvariant(), StringComparison.Ordinal)
            && string.Equals(Artist?.ToUpperInvariant(), other.Artist?.ToUpperInvariant(), StringComparison.Ordinal);
    }

    public override bool Equals(object? obj) => Equals(obj as AlbumIdentity);

    public override int GetHashCode()
    {
        if (Mbid != null) return HashCode.Combine(nameof(AlbumIdentity), Mbid.ToUpperInvariant());
        if (DiscogsReleaseId != null) return HashCode.Combine(nameof(AlbumIdentity), DiscogsReleaseId.ToUpperInvariant());
        return HashCode.Combine(Title?.ToUpperInvariant(), Artist?.ToUpperInvariant());
    }

    public override string ToString() =>
        Mbid != null ? $"mbid:{Mbid}"
        : DiscogsReleaseId != null ? $"discogs:{DiscogsReleaseId}"
        : $"{Artist} – {Title}";
}
