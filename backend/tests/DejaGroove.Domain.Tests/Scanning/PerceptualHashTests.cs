using DejaGroove.Domain.Scanning;

namespace DejaGroove.Domain.Tests.Scanning;

public sealed class PerceptualHashTests
{
    [Fact]
    public void Equals_WorksForSameValue()
    {
        var a = new PerceptualHash(42);
        var b = new PerceptualHash(42);
        Assert.True(a.Equals(b));
        Assert.Equal(a.GetHashCode(), b.GetHashCode());
    }

    [Fact]
    public void Equals_ReturnsFalseForNullAndDifferentType()
    {
        var a = new PerceptualHash(42);
        Assert.False(a.Equals((PerceptualHash?)null));
        Assert.False(a.Equals("42"));
    }

    [Fact]
    public void ToString_FormatsAsLowerHex16()
    {
        var hash = new PerceptualHash(0xABCD);
        Assert.Equal("000000000000abcd", hash.ToString());
    }
}
