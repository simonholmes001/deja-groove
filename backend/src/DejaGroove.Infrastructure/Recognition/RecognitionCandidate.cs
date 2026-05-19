namespace DejaGroove.Infrastructure.Recognition;

/// <summary>
/// One album the vision model believes the cover could be. The model returns
/// no stable identifiers, so <see cref="Title"/> and <see cref="Artist"/> must
/// both be present for the candidate to form a usable identity.
/// </summary>
public sealed record RecognitionCandidate(string? Title, string? Artist, int? Year, float Confidence);
