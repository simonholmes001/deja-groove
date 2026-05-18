using DejaGroove.Api.Middleware;
using Microsoft.AspNetCore.Http;

namespace DejaGroove.Api.Tests.Middleware;

public sealed class RequestIdMiddlewareTests
{
    [Fact]
    public async Task InvokeAsync_UsesIncomingCorrelationIdAsRequestId()
    {
        var requestId = Guid.NewGuid();
        var context = new DefaultHttpContext();
        context.Request.Headers[RequestIdMiddleware.CorrelationIdHeaderName] = requestId.ToString();

        var middleware = new RequestIdMiddleware(_ => Task.CompletedTask);

        await middleware.InvokeAsync(context);

        Assert.Equal(requestId, Assert.IsType<Guid>(context.Items[RequestIdMiddleware.RequestIdKey]));
        Assert.Equal(requestId.ToString(), context.TraceIdentifier);
        Assert.Equal(requestId.ToString(), context.Response.Headers["X-Request-Id"].ToString());
    }

    [Fact]
    public async Task InvokeAsync_GeneratesRequestIdWhenCorrelationIdIsMissing()
    {
        var context = new DefaultHttpContext();
        var middleware = new RequestIdMiddleware(_ => Task.CompletedTask);

        await middleware.InvokeAsync(context);

        var requestId = Assert.IsType<Guid>(context.Items[RequestIdMiddleware.RequestIdKey]);
        Assert.NotEqual(Guid.Empty, requestId);
        Assert.Equal(requestId.ToString(), context.Response.Headers["X-Request-Id"].ToString());
    }
}
