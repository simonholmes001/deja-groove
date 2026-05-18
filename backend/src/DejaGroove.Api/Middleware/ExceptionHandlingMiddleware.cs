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
        catch (IdempotencyConflictException idempotencyConflict)
        {
            logger.LogWarning(
                "Idempotency conflict for request {RequestId}: {Code}",
                context.Items[RequestIdMiddleware.RequestIdKey],
                idempotencyConflict.Code);

            await ApiErrorResponseWriter.WriteAsync(
                context,
                new ApiErrorDefinition(409, idempotencyConflict.Code, idempotencyConflict.Message, false));
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
        catch (NotFoundException notFoundException)
        {
            await ApiErrorResponseWriter.WriteAsync(
                context,
                new ApiErrorDefinition(404, notFoundException.Code, notFoundException.Message, false));
        }
        catch (ConflictException conflictException)
        {
            await ApiErrorResponseWriter.WriteAsync(
                context,
                new ApiErrorDefinition(409, conflictException.Code, conflictException.Message, false));
        }
        catch (UnprocessableEntityException unprocessableEntityException)
        {
            await ApiErrorResponseWriter.WriteAsync(
                context,
                new ApiErrorDefinition(422, unprocessableEntityException.Code, unprocessableEntityException.Message, false));
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Unhandled exception for request {RequestId}",
                context.Items[RequestIdMiddleware.RequestIdKey]);
            await ApiErrorResponseWriter.WriteAsync(context, ApiErrorCatalog.InternalError);
        }
    }
}
