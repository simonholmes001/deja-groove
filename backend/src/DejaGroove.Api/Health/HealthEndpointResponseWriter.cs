using System.Text.Json;
using Microsoft.Extensions.Diagnostics.HealthChecks;

namespace DejaGroove.Api.Health;

public static class HealthEndpointResponseWriter
{
    public static Task WriteAsync(HttpContext context, HealthReport report)
    {
        context.Response.ContentType = "application/json";

        var body = new
        {
            status = report.Status.ToString(),
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
}
