namespace DejaGroove.Infrastructure.Recognition;

/// <summary>
/// Configuration for the OpenAI vision recognition adapter (issue #141).
/// Bound from the "OpenAi" configuration section; the API key is supplied at
/// runtime (Key Vault / environment) and is never committed.
/// </summary>
public sealed record OpenAiOptions
{
    public const string SectionName = "OpenAi";

    public string ApiKey { get; init; } = string.Empty;

    public string Model { get; init; } = "gpt-5.4-vision";

    public string BaseUrl { get; init; } = "https://api.openai.com/v1";

    /// <summary>Per-call timeout. Bounded by the architecture's scan budget.</summary>
    public int TimeoutSeconds { get; init; } = 5;

    public int MaxRetryAttempts { get; init; } = 1;

    public string PromptVersion { get; init; } = RecognitionPromptRegistry.CurrentVersion;
}
