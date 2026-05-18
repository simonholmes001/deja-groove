using DejaGroove.Application.Collection;

namespace DejaGroove.Application.Tests.Collection;

public sealed class CollectionCursorTests
{
    [Fact]
    public void EncodeThenDecode_RoundTripsExactly()
    {
        var original = new CollectionCursor(
            CollectionSortField.Title,
            "RUMOURS",
            new DateTimeOffset(2026, 5, 18, 9, 30, 15, TimeSpan.Zero),
            Guid.NewGuid());

        var decoded = CollectionCursor.TryDecode(original.Encode());

        Assert.Equal(original, decoded);
    }

    [Fact]
    public void EncodeThenDecode_SortKeyWithDelimiterAndUnicode_Survives()
    {
        // The sort key is an arbitrary album title — pipes, colons and unicode
        // must not corrupt the opaque token.
        var original = new CollectionCursor(
            CollectionSortField.Artist,
            "A|B:C üñ |::|",
            DateTimeOffset.UtcNow,
            Guid.NewGuid());

        Assert.Equal(original, CollectionCursor.TryDecode(original.Encode()));
    }

    [Fact]
    public void Encode_IsOpaqueBase64_NotPlaintext()
    {
        var cursor = new CollectionCursor(
            CollectionSortField.CreatedAt, "", DateTimeOffset.UtcNow, Guid.NewGuid());

        var token = cursor.Encode();

        Assert.DoesNotContain("|", token);
        Assert.DoesNotContain("-", token);
    }

    [Theory]
    [InlineData(null)]
    [InlineData("")]
    [InlineData("   ")]
    [InlineData("not-base64!!")]
    [InlineData("bm90LWEtY3Vyc29y")] // base64("not-a-cursor") — wrong shape
    public void TryDecode_InvalidToken_ReturnsNull(string? token)
    {
        Assert.Null(CollectionCursor.TryDecode(token));
    }

    [Fact]
    public void TryDecode_UnknownSortField_ReturnsNull()
    {
        var bad = Convert.ToBase64String(
            System.Text.Encoding.UTF8.GetBytes("99|" +
                Convert.ToBase64String("k"u8.ToArray()) + "|0000000000000000000|" +
                Guid.NewGuid().ToString("N")));

        Assert.Null(CollectionCursor.TryDecode(bad));
    }

    [Fact]
    public void TryDecode_TamperedTicks_ReturnsNull()
    {
        var bad = Convert.ToBase64String(
            System.Text.Encoding.UTF8.GetBytes("0|" +
                Convert.ToBase64String("k"u8.ToArray()) + "|notanumber|" +
                Guid.NewGuid().ToString("N")));

        Assert.Null(CollectionCursor.TryDecode(bad));
    }
}
