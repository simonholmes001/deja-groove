using DejaGroove.Infrastructure.Recognition;
using Microsoft.Extensions.Options;

namespace DejaGroove.Infrastructure.Tests.Recognition;

/// <summary>
/// Issue #141: fail fast on misconfiguration at startup rather than on the
/// first scan. Timeout bounds are derived from the architecture's 5.0s server
/// budget / 6.0s client timeout.
/// </summary>
public sealed class ValidateOpenAiOptionsTests
{
    private static OpenAiOptions Valid() => new()
    {
        ApiKey = "sk-test-key",
        Model = "gpt-5.4-vision",
        BaseUrl = "https://api.openai.com/v1",
        TimeoutSeconds = 5,
        MaxRetryAttempts = 1,
        PromptVersion = RecognitionPromptRegistry.CurrentVersion,
    };

    private static ValidateOptionsResult Run(OpenAiOptions o) =>
        new ValidateOpenAiOptions().Validate(null, o);

    [Fact]
    public void ValidOptions_Succeed()
    {
        Assert.True(Run(Valid()).Succeeded);
    }

    [Theory]
    [InlineData("")]
    [InlineData("   ")]
    public void MissingApiKey_Fails(string apiKey)
    {
        var result = Run(Valid() with { ApiKey = apiKey });

        Assert.True(result.Failed);
        Assert.Contains("ApiKey", result.FailureMessage);
    }

    [Fact]
    public void MissingModel_Fails()
    {
        Assert.True(Run(Valid() with { Model = "" }).Failed);
    }

    [Theory]
    [InlineData("not-a-url")]
    [InlineData("ftp://example.com")]
    public void NonHttpBaseUrl_Fails(string url)
    {
        Assert.True(Run(Valid() with { BaseUrl = url }).Failed);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(7)]
    public void TimeoutOutsideBudget_Fails(int seconds)
    {
        Assert.True(Run(Valid() with { TimeoutSeconds = seconds }).Failed);
    }

    [Theory]
    [InlineData(-1)]
    [InlineData(4)]
    public void RetryAttemptsOutOfRange_Fails(int attempts)
    {
        Assert.True(Run(Valid() with { MaxRetryAttempts = attempts }).Failed);
    }

    [Fact]
    public void UnregisteredPromptVersion_Fails()
    {
        var result = Run(Valid() with { PromptVersion = "9.9.9" });

        Assert.True(result.Failed);
        Assert.Contains("9.9.9", result.FailureMessage);
    }
}
