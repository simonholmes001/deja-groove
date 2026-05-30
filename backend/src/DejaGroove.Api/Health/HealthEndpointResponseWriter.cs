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
        var services = context.RequestServices;
        var matcher = services.GetService<IAlbumMatchingPort>();
        var imageValidation = services.GetService<IImageValidationPort>();
        var perceptualHash = services.GetService<IPerceptualHashPort>();
        var scanCache = services.GetService<IScanCachePort>();
        var collectionOwnership = services.GetService<ICollectionOwnershipPort>();
        var scanEvents = services.GetService<IScanEventRepository>();
        var ambiguousScans = services.GetService<IAmbiguousScanRepository>();

        if (matcher is null)
            return ("unknown", false);

        var configured =
            matcher is not UnconfiguredAlbumMatchingPort &&
            imageValidation is not UnconfiguredImageValidationPort &&
            perceptualHash is not UnconfiguredPerceptualHashPort &&
            scanCache is not UnconfiguredScanCachePort &&
            collectionOwnership is not UnconfiguredCollectionOwnershipPort &&
            scanEvents is not UnconfiguredScanEventRepository &&
            ambiguousScans is not UnconfiguredAmbiguousScanRepository;

        return (matcher.GetType().Name, configured);
    }
}
