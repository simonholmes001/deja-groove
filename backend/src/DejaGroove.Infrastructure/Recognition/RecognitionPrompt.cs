namespace DejaGroove.Infrastructure.Recognition;

/// <summary>An immutable, versioned instruction template for the vision model.</summary>
public sealed record RecognitionPrompt(string Version, string Text);
