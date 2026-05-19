namespace DejaGroove.Infrastructure.Recognition;

/// <summary>
/// A non-retryable recognition failure: the request was rejected (4xx) or the
/// model returned a response that could not be parsed.
/// </summary>
public sealed class OpenAiRecognitionException : Exception
{
    public OpenAiRecognitionException(string message) : base(message) { }
    public OpenAiRecognitionException(string message, Exception inner) : base(message, inner) { }
}

/// <summary>
/// A retryable recognition failure: a transient transport or server-side error
/// (5xx / 408 / 429). The resilience pipeline retries these.
/// </summary>
public sealed class TransientRecognitionException : Exception
{
    public TransientRecognitionException(string message) : base(message) { }
}
