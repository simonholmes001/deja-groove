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
    private const int MinConcurrentRequests = 1;
    private const int MaxConcurrentRequests = 64;
    private const int MinFailurePercent = 1;
    private const int MaxFailurePercent = 100;
    private const int MinMinimumThroughput = 2;
    private const int MaxMinimumThroughput = 100;
    private const int MinSamplingSeconds = 1;
    private const int MaxSamplingSeconds = 300;
    private const int MinBreakSeconds = 1;
    private const int MaxBreakSeconds = 300;

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

        if (options.MaxConcurrentRequests is < MinConcurrentRequests or > MaxConcurrentRequests)
            return Fail($"MaxConcurrentRequests must be between {MinConcurrentRequests} and {MaxConcurrentRequests}");

        if (options.CircuitBreakerFailureThresholdPercent is < MinFailurePercent or > MaxFailurePercent)
            return Fail($"CircuitBreakerFailureThresholdPercent must be between {MinFailurePercent} and {MaxFailurePercent}");

        if (options.CircuitBreakerMinimumThroughput is < MinMinimumThroughput or > MaxMinimumThroughput)
            return Fail($"CircuitBreakerMinimumThroughput must be between {MinMinimumThroughput} and {MaxMinimumThroughput}");

        if (options.CircuitBreakerSamplingSeconds is < MinSamplingSeconds or > MaxSamplingSeconds)
            return Fail($"CircuitBreakerSamplingSeconds must be between {MinSamplingSeconds} and {MaxSamplingSeconds}");

        if (options.CircuitBreakerBreakSeconds is < MinBreakSeconds or > MaxBreakSeconds)
            return Fail($"CircuitBreakerBreakSeconds must be between {MinBreakSeconds} and {MaxBreakSeconds}");

        if (!RecognitionPromptRegistry.Versions.Contains(options.PromptVersion))
            return Fail(
                $"PromptVersion '{options.PromptVersion}' is not registered. " +
                $"Registered: {string.Join(", ", RecognitionPromptRegistry.Versions)}");

        return ValidateOptionsResult.Success;
    }

    private static ValidateOptionsResult Fail(string reason) =>
        ValidateOptionsResult.Fail($"{OpenAiOptions.SectionName}: {reason}");
}
