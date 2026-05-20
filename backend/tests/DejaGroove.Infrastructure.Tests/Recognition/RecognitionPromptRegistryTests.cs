using DejaGroove.Infrastructure.Recognition;

namespace DejaGroove.Infrastructure.Tests.Recognition;

/// <summary>
/// Issue #38: prompt templates are versioned and rollback-able. The active
/// prompt is pinned (not "latest wins"), and any prior version stays
/// retrievable so a regression can be rolled back by changing the pin.
/// </summary>
public sealed class RecognitionPromptRegistryTests
{
    [Fact]
    public void Current_ReturnsThePinnedVersion()
    {
        var current = RecognitionPromptRegistry.Current;

        Assert.Equal(RecognitionPromptRegistry.CurrentVersion, current.Version);
        Assert.False(string.IsNullOrWhiteSpace(current.Text));
    }

    [Fact]
    public void Get_KnownVersion_ReturnsThatPrompt()
    {
        var prompt = RecognitionPromptRegistry.Get("1.0.0");

        Assert.Equal("1.0.0", prompt.Version);
        Assert.False(string.IsNullOrWhiteSpace(prompt.Text));
    }

    [Fact]
    public void Get_UnknownVersion_ThrowsWithActionableMessage()
    {
        var ex = Assert.Throws<KeyNotFoundException>(() => RecognitionPromptRegistry.Get("9.9.9"));

        Assert.Contains("9.9.9", ex.Message);
    }

    [Fact]
    public void CurrentVersion_IsRegistered()
    {
        Assert.Contains(RecognitionPromptRegistry.CurrentVersion, RecognitionPromptRegistry.Versions);
    }

    [Fact]
    public void CurrentPrompt_DeclaresTheJsonContractTheParserDependsOn()
    {
        // Guards the #38 ↔ #141 seam: the prompt must keep asking for exactly
        // the fields OpenAiAlbumMatchingPort parses, or recognition silently breaks.
        var text = RecognitionPromptRegistry.Current.Text;

        foreach (var key in new[] { "title", "artist", "year", "confidence", "candidates" })
            Assert.Contains(key, text, StringComparison.OrdinalIgnoreCase);
    }
}
