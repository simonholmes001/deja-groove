using System.Text.Json;
using DejaGroove.Api.Middleware;
using DejaGroove.Api.Responses;
using DejaGroove.Application.Exceptions;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging.Abstractions;

namespace DejaGroove.Api.Tests.Middleware;

public sealed class ExceptionHandlingMiddlewareTests
{
    [Fact]
    public async Task InvokeAsync_WhenInputValidationException_Returns400ErrorEnvelope()
    {
        var requestId = Guid.NewGuid();
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();
        context.Items[RequestIdMiddleware.RequestIdKey] = requestId;

        RequestDelegate next = _ => throw new InputValidationException("invalid_image", "Image signature mismatch.");
        var middleware = new ExceptionHandlingMiddleware(next, NullLogger<ExceptionHandlingMiddleware>.Instance);

        await middleware.InvokeAsync(context);

        Assert.Equal(400, context.Response.StatusCode);

        context.Response.Body.Position = 0;
        using var reader = new StreamReader(context.Response.Body);
        var json = await reader.ReadToEndAsync();
        var envelope = JsonSerializer.Deserialize<ErrorResponse>(json)!;

        Assert.Equal("invalid_image", envelope.Error.Code);
        Assert.Equal("Image signature mismatch.", envelope.Error.Message);
        Assert.False(envelope.Error.Retryable);
        Assert.Equal(requestId, envelope.Error.RequestId);
    }

    [Fact]
    public async Task InvokeAsync_WhenUnhandledException_Returns500ErrorEnvelope()
    {
        var requestId = Guid.NewGuid();
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();
        context.Items[RequestIdMiddleware.RequestIdKey] = requestId;

        RequestDelegate next = _ => throw new Exception("boom");
        var middleware = new ExceptionHandlingMiddleware(next, NullLogger<ExceptionHandlingMiddleware>.Instance);

        await middleware.InvokeAsync(context);

        Assert.Equal(500, context.Response.StatusCode);
        context.Response.Body.Position = 0;
        using var reader = new StreamReader(context.Response.Body);
        var json = await reader.ReadToEndAsync();
        var envelope = JsonSerializer.Deserialize<ErrorResponse>(json)!;

        Assert.Equal("internal_error", envelope.Error.Code);
        Assert.True(envelope.Error.Retryable);
        Assert.Equal(requestId, envelope.Error.RequestId);
    }

    [Fact]
    public async Task InvokeAsync_WhenServiceUnavailableException_Returns503ErrorEnvelope()
    {
        var requestId = Guid.NewGuid();
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();
        context.Items[RequestIdMiddleware.RequestIdKey] = requestId;

        RequestDelegate next = _ => throw new ServiceUnavailableException("scan_dependencies_unconfigured", "not configured");
        var middleware = new ExceptionHandlingMiddleware(next, NullLogger<ExceptionHandlingMiddleware>.Instance);

        await middleware.InvokeAsync(context);

        Assert.Equal(503, context.Response.StatusCode);
        context.Response.Body.Position = 0;
        using var reader = new StreamReader(context.Response.Body);
        var json = await reader.ReadToEndAsync();
        var envelope = JsonSerializer.Deserialize<ErrorResponse>(json)!;

        Assert.Equal("scan_dependencies_unconfigured", envelope.Error.Code);
        Assert.True(envelope.Error.Retryable);
        Assert.Equal(requestId, envelope.Error.RequestId);
    }

}
