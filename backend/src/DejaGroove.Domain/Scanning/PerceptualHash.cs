namespace DejaGroove.Domain.Scanning;

/// <summary>Typed wrapper around a 64-bit perceptual hash. Used as cache key.</summary>
public sealed class PerceptualHash : IEquatable<PerceptualHash>
{
    public ulong Value { get; }

    public PerceptualHash(ulong value) => Value = value;

    public bool Equals(PerceptualHash? other) => other is not null && Value == other.Value;
    public override bool Equals(object? obj) => Equals(obj as PerceptualHash);
    public override int GetHashCode() => Value.GetHashCode();
    public override string ToString() => Value.ToString("x16");
}
