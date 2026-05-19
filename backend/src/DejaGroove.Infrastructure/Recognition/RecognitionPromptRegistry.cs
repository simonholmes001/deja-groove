namespace DejaGroove.Infrastructure.Recognition;

/// <summary>
/// Issue #38: a semantically-versioned registry of recognition prompts.
/// The active prompt is explicitly pinned via <see cref="CurrentVersion"/>
/// (not "highest wins"), so a bad prompt is rolled back by moving the pin to
/// a known-good prior version — every registered version stays retrievable.
/// </summary>
public static class RecognitionPromptRegistry
{
    /// <summary>The pinned, active prompt version. Change this to roll back.</summary>
    public const string CurrentVersion = "1.0.0";

    private const string V1_0_0 = """
        You identify a music album from a photograph of its cover (vinyl, CD, or
        cassette). Respond with STRICT JSON only, no prose, no markdown fences.

        Schema:
        {
          "candidates": [
            { "title": string, "artist": string, "year": integer|null, "confidence": number }
          ]
        }

        Rules:
        - "confidence" is your certainty for that candidate, between 0.0 and 1.0.
        - Order "candidates" by descending confidence. Include at most 5.
        - Include a candidate only if you can give both a title and an artist.
        - If you cannot identify the cover at all, return {"candidates": []}.
        - Do not invent catalogue numbers or identifiers; title, artist and year only.
        """;

    private static readonly IReadOnlyDictionary<string, RecognitionPrompt> Prompts =
        new Dictionary<string, RecognitionPrompt>(StringComparer.Ordinal)
        {
            ["1.0.0"] = new RecognitionPrompt("1.0.0", V1_0_0),
        };

    public static IReadOnlyCollection<string> Versions => (IReadOnlyCollection<string>)Prompts.Keys;

    public static RecognitionPrompt Current => Get(CurrentVersion);

    public static RecognitionPrompt Get(string version)
    {
        if (Prompts.TryGetValue(version, out var prompt))
            return prompt;

        throw new KeyNotFoundException(
            $"No recognition prompt registered for version '{version}'. " +
            $"Registered versions: {string.Join(", ", Prompts.Keys)}.");
    }
}
