namespace DejaGroove.Api.Middleware;

public sealed class RequestIdMiddleware(RequestDelegate next)
{
    public const string RequestIdKey = "RequestId";

    public async Task InvokeAsync(HttpContext context)
    {
        var requestId = Guid.NewGuid();
        context.Items[RequestIdKey] = requestId;
        context.Response.Headers["X-Request-Id"] = requestId.ToString();
        await next(context);
    }
}
