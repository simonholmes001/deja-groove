using System.Text;
using DejaGroove.Domain.Collection;

namespace DejaGroove.Application.Collection;

/// <summary>
/// Sort fields that are keyset-safe with the (sort, created_at, id) cursor.
/// Year is intentionally excluded — its nullability makes a stable keyset
/// boundary error-prone, so the API rejects it rather than paginate wrongly.
/// </summary>
public enum CollectionSortField { CreatedAt, Title, Artist }

public enum SortDirection { Ascending, Descending }

/// <summary>
/// A keyset-pagination query over a user's active collection. Keyset (not
/// OFFSET) so a page boundary stays stable while concurrent inserts happen.
/// </summary>
public sealed record CollectionQuery
{
    public required Guid UserId { get; init; }
    public string? Search { get; init; }
    public string? Format { get; init; }
    public CollectionSortField SortField { get; init; } = CollectionSortField.CreatedAt;
    public SortDirection SortDirection { get; init; } = SortDirection.Descending;
    public CollectionCursor? Cursor { get; init; }

    private int _limit = 25;
    public int Limit
    {
        get => _limit;
        init => _limit = value switch
        {
            < 1 => 1,
            > 100 => 100,
            _ => value
        };
    }
}

public sealed record CollectionPage(IReadOnlyList<CollectionRecord> Items, string? NextCursor);

/// <summary>
/// Opaque, stable page cursor. Encodes the full ordering tuple
/// <c>(sortField, sortKey, createdAt, id)</c>. <c>createdAt</c> + <c>id</c> are
/// the deterministic tie-breakers that keep the boundary unique even when many
/// rows share the primary sort key, so pagination is stable under concurrent
/// writes for every supported sort field. Each part is independently
/// base64-encoded so an arbitrary text sort key cannot break the delimiter.
/// </summary>
public sealed record CollectionCursor(
    CollectionSortField Field,
    string SortKey,
    DateTimeOffset CreatedAt,
    Guid Id)
{
    public string Encode()
    {
        var raw = string.Join('|',
            ((int)Field).ToString(),
            Convert.ToBase64String(Encoding.UTF8.GetBytes(SortKey)),
            CreatedAt.UtcTicks.ToString("D19"),
            Id.ToString("N"));
        return Convert.ToBase64String(Encoding.UTF8.GetBytes(raw));
    }

    public static CollectionCursor? TryDecode(string? token)
    {
        if (string.IsNullOrWhiteSpace(token))
            return null;

        try
        {
            var raw = Encoding.UTF8.GetString(Convert.FromBase64String(token));
            var parts = raw.Split('|');
            if (parts.Length != 4)
                return null;

            if (!int.TryParse(parts[0], out var fieldValue) ||
                !Enum.IsDefined(typeof(CollectionSortField), fieldValue))
                return null;
            if (!long.TryParse(parts[2], out var ticks))
                return null;
            if (!Guid.TryParseExact(parts[3], "N", out var id))
                return null;

            var sortKey = Encoding.UTF8.GetString(Convert.FromBase64String(parts[1]));
            return new CollectionCursor(
                (CollectionSortField)fieldValue, sortKey,
                new DateTimeOffset(ticks, TimeSpan.Zero), id);
        }
        catch (FormatException)
        {
            return null;
        }
    }
}
