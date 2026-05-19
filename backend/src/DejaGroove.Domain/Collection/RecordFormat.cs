namespace DejaGroove.Domain.Collection;

/// <summary>Physical medium on which a recording is stored.</summary>
public sealed class RecordFormat
{
    public static readonly RecordFormat Vinyl = new("vinyl");
    public static readonly RecordFormat Cd = new("cd");
    public static readonly RecordFormat Cassette = new("cassette");
    public static readonly RecordFormat Other = new("other");

    public string Value { get; }

    private RecordFormat(string value) => Value = value;

    /// <summary>
    /// Parses a raw string into a <see cref="RecordFormat"/>.
    /// Returns <c>true</c> for <c>vinyl</c>, <c>cd</c>, <c>cassette</c>, or <c>other</c>
    /// (case-insensitive, trims whitespace).
    /// </summary>
    public static bool TryParse(string? raw, out RecordFormat? result)
    {
        result = raw?.Trim().ToLowerInvariant() switch
        {
            "vinyl"    => Vinyl,
            "cd"       => Cd,
            "cassette" => Cassette,
            "other"    => Other,
            _          => null
        };
        return result is not null;
    }

    public override string ToString() => Value;
    public override bool Equals(object? obj) => obj is RecordFormat f && f.Value == Value;
    public override int GetHashCode() => Value.GetHashCode(StringComparison.Ordinal);
}
