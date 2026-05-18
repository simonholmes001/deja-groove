using DejaGroove.Domain.Shared;

namespace DejaGroove.Domain.Tests.Shared;

public sealed class DeterministicUserIdTests
{
    [Fact]
    public void FromSubject_SameSubject_ProducesSameId()
    {
        var a = DeterministicUserId.FromSubject("auth0|abc-123");
        var b = DeterministicUserId.FromSubject("auth0|abc-123");

        Assert.Equal(a, b);
    }

    [Fact]
    public void FromSubject_DifferentSubjects_ProduceDifferentIds()
    {
        var a = DeterministicUserId.FromSubject("subject-one");
        var b = DeterministicUserId.FromSubject("subject-two");

        Assert.NotEqual(a, b);
    }

    [Fact]
    public void FromSubject_ProducesRfc4122Version5Guid()
    {
        var id = DeterministicUserId.FromSubject("any-subject");
        var bytes = id.ToByteArray();

        // .NET Guid stores the first three groups little-endian. Byte 7 holds
        // the version nibble in RFC layout; in .NET's array that is index 7.
        var versionNibble = (bytes[7] & 0xF0) >> 4;
        Assert.Equal(5, versionNibble);
    }

    [Fact]
    public void FromSubject_NeverReturnsEmptyGuid()
    {
        Assert.NotEqual(Guid.Empty, DeterministicUserId.FromSubject("x"));
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    public void FromSubject_BlankSubject_Throws(string? subject)
    {
        Assert.ThrowsAny<ArgumentException>(() => DeterministicUserId.FromSubject(subject!));
    }

    [Fact]
    public void FromSubject_IsCaseSensitive()
    {
        Assert.NotEqual(
            DeterministicUserId.FromSubject("Subject"),
            DeterministicUserId.FromSubject("subject"));
    }
}
