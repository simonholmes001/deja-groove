namespace DejaGroove.Api.Middleware;

public sealed class RequestIdMiddleware(RequestDelegate next)
{
    public const string RequestIdKey = "RequestId";
    public const string CorrelationIdHeaderName = "X-Correlation-Id";

    public async Task InvokeAsync(HttpContext context)
    {
        var requestId = ResolveRequestId(context);
        context.Items[RequestIdKey] = requestId;
        context.TraceIdentifier = requestId.ToString();
        context.Response.Headers["X-Request-Id"] = requestId.ToString();
        await next(context);
    }

    private static Guid ResolveRequestId(HttpContext context)
    {
        if (context.Request.Headers.TryGetValue(CorrelationIdHeaderName, out var values) &&
            Guid.TryParse(values.ToString(), out var correlationId))
        {
            return correlationId;
        }

        return Guid.NewGuid();
    }
}
