using Microsoft.AspNetCore.Http;

namespace DejaGroove.Api.Errors;

public static class ApiErrorCatalog
{
    public static ApiErrorDefinition InternalError { get; } =
        new(StatusCodes.Status500InternalServerError, "internal_error", "An unexpected error occurred.", true);

    public static ApiErrorDefinition FromStatusCode(int statusCode) =>
        statusCode switch
        {
            StatusCodes.Status400BadRequest => new(statusCode, "validation_error", "The request is invalid.", false),
            StatusCodes.Status401Unauthorized => new(statusCode, "unauthorized", "Authentication is required.", false),
            StatusCodes.Status403Forbidden => new(statusCode, "forbidden", "The requested operation is not allowed.", false),
            StatusCodes.Status404NotFound => new(statusCode, "not_found", "The requested resource was not found.", false),
            StatusCodes.Status405MethodNotAllowed => new(statusCode, "method_not_allowed", "The requested HTTP method is not supported.", false),
            StatusCodes.Status409Conflict => new(statusCode, "conflict", "The request could not be completed because of a conflict.", false),
            StatusCodes.Status413PayloadTooLarge => new(statusCode, "payload_too_large", "The request payload is too large.", false),
            StatusCodes.Status429TooManyRequests => new(statusCode, "rate_limited", "Too many requests were sent. Retry later.", true),
            StatusCodes.Status500InternalServerError => InternalError,
            StatusCodes.Status502BadGateway => new(statusCode, "bad_gateway", "A downstream dependency returned an invalid response.", true),
            StatusCodes.Status503ServiceUnavailable => new(statusCode, "service_unavailable", "A required dependency is unavailable.", true),
            StatusCodes.Status504GatewayTimeout => new(statusCode, "timeout", "A required dependency timed out.", true),
            _ when statusCode >= StatusCodes.Status500InternalServerError =>
                new(statusCode, "server_error", "The server could not process the request.", true),
            _ => new(statusCode, "request_failed", "The request could not be processed.", false)
        };
}
