using System.Text.Json;
using DejaGroove.Api.Ports;
using DejaGroove.Application.Ports;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace DejaGroove.Api.Health;

public static class HealthEndpointResponseWriter
{
    public static Task WriteAsync(HttpContext context, HealthReport report)
    {
        context.Response.ContentType = "application/json";
        var scanRuntime = ResolveScanRuntime(context);
        context.Response.Headers["X-Scan-Matcher"] = scanRuntime.Matcher;

        var body = new
        {
            status = report.Status.ToString(),
            scanRuntime = new
            {
                matcher = scanRuntime.Matcher,
                configured = scanRuntime.Configured
            },
            dependencies = report.Entries.ToDictionary(
                entry => entry.Key,
                entry => new
                {
                    status = entry.Value.Status.ToString(),
                    description = entry.Value.Description ?? string.Empty
                })
        };

        return context.Response.WriteAsync(JsonSerializer.Serialize(body));
    }

    private static (string Matcher, bool Configured) ResolveScanRuntime(HttpContext context)
    {
        var matcher = context.RequestServices.GetService<IAlbumMatchingPort>();
        if (matcher is null)
            return ("unknown", false);

        return (matcher.GetType().Name, matcher is not UnconfiguredAlbumMatchingPort);
    }
}
