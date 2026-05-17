using DejaGroove.Domain.Scanning;

namespace DejaGroove.Domain.Tests.Scanning;

public sealed class PerceptualHashTests
{
    [Fact]
    public void EqualValues_AreEqual_AndHexFormatted()
    {
        var a = new PerceptualHash(0x0FUL);
        var b = new PerceptualHash(0x0FUL);

        Assert.True(a.Equals(b));
        Assert.Equal(a.GetHashCode(), b.GetHashCode());
        Assert.Equal("000000000000000f", a.ToString());
    }

    [Fact]
    public void DifferentValues_AreNotEqual()
    {
        var a = new PerceptualHash(1);
        var b = new PerceptualHash(2);
        Assert.False(a.Equals(b));
    }
}
