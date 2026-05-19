using Microsoft.Extensions.Options;

namespace DejaGroove.Infrastructure.Recognition;

/// <summary>
/// Startup validation for <see cref="OpenAiOptions"/> (issue #141). Fails fast
/// so a misconfigured deployment never reaches the first scan.
/// </summary>
public sealed class ValidateOpenAiOptions : IValidateOptions<OpenAiOptions>
{
    // Aligned with the architecture's 5.0s server budget / 6.0s client timeout.
    private const int MinTimeoutSeconds = 1;
    private const int MaxTimeoutSeconds = 6;
    private const int MinRetryAttempts = 0;
    private const int MaxRetryAttempts = 3;

    public ValidateOptionsResult Validate(string? name, OpenAiOptions options)
    {
        if (string.IsNullOrWhiteSpace(options.ApiKey))
            return Fail("ApiKey is required");

        if (string.IsNullOrWhiteSpace(options.Model))
            return Fail("Model is required");

        if (!Uri.TryCreate(options.BaseUrl, UriKind.Absolute, out var baseUri) ||
            (baseUri.Scheme != Uri.UriSchemeHttp && baseUri.Scheme != Uri.UriSchemeHttps))
            return Fail("BaseUrl must be an absolute http(s) URL");

        if (options.TimeoutSeconds is < MinTimeoutSeconds or > MaxTimeoutSeconds)
            return Fail($"TimeoutSeconds must be between {MinTimeoutSeconds} and {MaxTimeoutSeconds}");

        if (options.MaxRetryAttempts is < MinRetryAttempts or > MaxRetryAttempts)
            return Fail($"MaxRetryAttempts must be between {MinRetryAttempts} and {MaxRetryAttempts}");

        if (!RecognitionPromptRegistry.Versions.Contains(options.PromptVersion))
            return Fail(
                $"PromptVersion '{options.PromptVersion}' is not registered. " +
                $"Registered: {string.Join(", ", RecognitionPromptRegistry.Versions)}");

        return ValidateOptionsResult.Success;
    }

    private static ValidateOptionsResult Fail(string reason) =>
        ValidateOptionsResult.Fail($"{OpenAiOptions.SectionName}: {reason}");
}
