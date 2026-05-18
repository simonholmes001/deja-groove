using System.Text.Json;
using DejaGroove.Api.Middleware;
using DejaGroove.Api.Responses;

namespace DejaGroove.Api.Errors;

public static class ApiErrorResponseWriter
{
    public static Task WriteAsync(HttpContext context, ApiErrorDefinition error)
    {
        if (context.Response.HasStarted)
        {
            return Task.CompletedTask;
        }

        var requestId = context.Items[RequestIdMiddleware.RequestIdKey] is Guid value
            ? value
            : Guid.Empty;

        var envelope = new ErrorResponse
        {
            Error = new ErrorDetail
            {
                Code = error.Code,
                Message = error.Message,
                Retryable = error.Retryable,
                RequestId = requestId
            }
        };

        context.Response.StatusCode = error.StatusCode;
        context.Response.ContentType = "application/json";

        return context.Response.WriteAsync(JsonSerializer.Serialize(envelope));
    }
}
