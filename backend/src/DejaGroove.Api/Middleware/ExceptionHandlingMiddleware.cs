using DejaGroove.Api.Errors;
using DejaGroove.Application.Exceptions;

namespace DejaGroove.Api.Middleware;

public sealed class ExceptionHandlingMiddleware(RequestDelegate next, ILogger<ExceptionHandlingMiddleware> logger)
{
    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await next(context);
        }
        catch (HttpErrorException httpErrorException)
        {
            logger.LogWarning(
                "HTTP error response for request {RequestId}: {Code}",
                context.Items[RequestIdMiddleware.RequestIdKey],
                httpErrorException.Code);

            await ApiErrorResponseWriter.WriteAsync(
                context,
                new ApiErrorDefinition(
                    httpErrorException.StatusCode,
                    httpErrorException.Code,
                    httpErrorException.Message,
                    httpErrorException.Retryable));
        }
        catch (InputValidationException validationException)
        {
            logger.LogWarning(
                "Input validation failed for request {RequestId}: {Code}",
                context.Items[RequestIdMiddleware.RequestIdKey],
                validationException.Code);

            await ApiErrorResponseWriter.WriteAsync(
                context,
                new ApiErrorDefinition(400, validationException.Code, validationException.Message, false));
        }
        catch (ServiceUnavailableException serviceUnavailableException)
        {
            logger.LogError(
                "Service dependency unavailable for request {RequestId}: {Code}",
                context.Items[RequestIdMiddleware.RequestIdKey],
                serviceUnavailableException.Code);

            await ApiErrorResponseWriter.WriteAsync(
                context,
                new ApiErrorDefinition(503, serviceUnavailableException.Code, serviceUnavailableException.Message, true));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unhandled exception for request {RequestId}",
                context.Items[RequestIdMiddleware.RequestIdKey]);
            await ApiErrorResponseWriter.WriteAsync(context, ApiErrorCatalog.InternalError);
        }
    }
}
