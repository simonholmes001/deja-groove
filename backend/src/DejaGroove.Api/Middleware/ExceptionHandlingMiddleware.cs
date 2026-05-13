using System.Text.Json;
using DejaGroove.Api.Responses;

namespace DejaGroove.Api.Middleware;

public sealed class ExceptionHandlingMiddleware(RequestDelegate next, ILogger<ExceptionHandlingMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unhandled exception for request {RequestId}",
                context.Items[RequestIdMiddleware.RequestIdKey]);
            await WriteErrorAsync(context, 500, "internal_error", "An unexpected error occurred.", retryable: true);
        }
    }

    private static Task WriteErrorAsync(HttpContext context, int statusCode, string code, string message, bool retryable)
    {
        if (context.Response.HasStarted)
            return Task.CompletedTask;

        var requestId = context.Items[RequestIdMiddleware.RequestIdKey] is Guid g ? g : Guid.Empty;
        var envelope = new ErrorResponse
        {
            Error = new ErrorDetail
            {
                Code = code,
                Message = message,
                Retryable = retryable,
                RequestId = requestId
            }
        };

        context.Response.StatusCode = statusCode;
        context.Response.ContentType = "application/json";
        return context.Response.WriteAsync(JsonSerializer.Serialize(envelope));
    }
}
