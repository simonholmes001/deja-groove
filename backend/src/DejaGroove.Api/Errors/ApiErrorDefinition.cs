namespace DejaGroove.Api.Errors;

public readonly record struct ApiErrorDefinition(
    int StatusCode,
    string Code,
    string Message,
    bool Retryable);
