using System.Text.Json;
using DejaGroove.Application.Exceptions;
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
        catch (InputValidationException validationException)
        {
            logger.LogWarning(
                "Input validation failed for request {RequestId}: {Code}",
                context.Items[RequestIdMiddleware.RequestIdKey],
                validationException.Code);

            await WriteErrorAsync(
                context,
                400,
                validationException.Code,
                validationException.Message,
                retryable: false);
        }
        catch (ServiceUnavailableException serviceUnavailableException)
        {
            logger.LogError(
                "Service dependency unavailable for request {RequestId}: {Code}",
                context.Items[RequestIdMiddleware.RequestIdKey],
                serviceUnavailableException.Code);

            await WriteErrorAsync(
                context,
                503,
                serviceUnavailableException.Code,
                serviceUnavailableException.Message,
                retryable: true);
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
