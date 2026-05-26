namespace DejaGroove.Infrastructure.Recognition;

/// <summary>
/// Configuration for the OpenAI vision recognition adapter (issue #141).
/// Non-secret tunables bind from the "OpenAi" configuration section. The API
/// key is sourced separately from the <c>OPENAI_KEY</c> environment variable
/// (never committed, never bound from appsettings).
/// </summary>
public sealed record OpenAiOptions
{
    public const string SectionName = "OpenAi";

    /// <summary>Injected from the OPENAI_KEY environment variable at startup.</summary>
    public string ApiKey { get; set; } = string.Empty;

    public string Model { get; init; } = "gpt-5.4";

    public string BaseUrl { get; init; } = "https://api.openai.com/v1";

    /// <summary>Per-call timeout. Bounded by the architecture's scan budget.</summary>
    public int TimeoutSeconds { get; init; } = 5;

    public int MaxRetryAttempts { get; init; } = 1;

    public int MaxConcurrentRequests { get; init; } = 8;

    public int CircuitBreakerFailureThresholdPercent { get; init; } = 50;

    public int CircuitBreakerMinimumThroughput { get; init; } = 4;

    public int CircuitBreakerSamplingSeconds { get; init; } = 30;

    public int CircuitBreakerBreakSeconds { get; init; } = 20;

    public string PromptVersion { get; init; } = RecognitionPromptRegistry.CurrentVersion;
}
