using System.Net;
using System.Text.Json;
using DejaGroove.Api.Ports;
using DejaGroove.Api.Health;
using DejaGroove.Application.Ports;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace DejaGroove.Api.Tests.Health;

public sealed class HealthEndpointTests
{
    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true
    };

    [Fact]
    public async Task GetHealth_AllowsAnonymousAccessAndReturns200WhenDependenciesAreHealthy()
    {
        using var client = CreateClient(new StubPostgresReadinessProbe(
            new PostgresReadinessResult(true, "PostgreSQL connection succeeded.")));

        var response = await client.GetAsync("/health");
        var body = JsonSerializer.Deserialize<HealthResponse>(
            await response.Content.ReadAsStringAsync(),
            JsonOptions)!;

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Healthy", body.Status);
        Assert.Equal("Healthy", body.Dependencies["postgres"].Status);
        Assert.Equal("PostgreSQL connection succeeded.", body.Dependencies["postgres"].Description);
        Assert.Equal("UnconfiguredAlbumMatchingPort", body.ScanRuntime.Matcher);
        Assert.False(body.ScanRuntime.Configured);
        Assert.Equal("UnconfiguredAlbumMatchingPort", response.Headers.GetValues("X-Scan-Matcher").Single());
    }

    [Fact]
    public async Task GetHealth_Returns503WhenPostgresReadinessFails()
    {
        using var client = CreateClient(new StubPostgresReadinessProbe(
            new PostgresReadinessResult(false, "PostgreSQL connection failed.")));

        var response = await client.GetAsync("/health");
        var body = JsonSerializer.Deserialize<HealthResponse>(
            await response.Content.ReadAsStringAsync(),
            JsonOptions)!;

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        Assert.Equal("Unhealthy", body.Status);
        Assert.Equal("Unhealthy", body.Dependencies["postgres"].Status);
        Assert.Equal("PostgreSQL connection failed.", body.Dependencies["postgres"].Description);
    }

    [Fact]
    public async Task GetHealthLive_Returns200WhenReadinessDependencyIsUnhealthy()
    {
        using var client = CreateClient(new StubPostgresReadinessProbe(
            new PostgresReadinessResult(false, "PostgreSQL connection failed.")));

        var response = await client.GetAsync("/health/live");
        var body = JsonSerializer.Deserialize<HealthResponse>(
            await response.Content.ReadAsStringAsync(),
            JsonOptions)!;

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("Healthy", body.Status);
    }

    [Fact]
    public async Task GetHealth_ReflectsOverriddenScanMatcher()
    {
        using var client = CreateClient(
            new StubPostgresReadinessProbe(new PostgresReadinessResult(true, "PostgreSQL connection succeeded.")),
            new StubAlbumMatchingPort());

        var response = await client.GetAsync("/health");
        var body = JsonSerializer.Deserialize<HealthResponse>(
            await response.Content.ReadAsStringAsync(),
            JsonOptions)!;

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Equal("StubAlbumMatchingPort", body.ScanRuntime.Matcher);
        Assert.True(body.ScanRuntime.Configured);
        Assert.Equal("StubAlbumMatchingPort", response.Headers.GetValues("X-Scan-Matcher").Single());
    }

    private static HttpClient CreateClient(IPostgresReadinessProbe probe, IAlbumMatchingPort? matcher = null)
    {
        var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment("Testing");
                builder.ConfigureServices(services =>
                {
                    services.RemoveAll<IPostgresReadinessProbe>();
                    services.AddSingleton(probe);
                    if (matcher is not null)
                    {
                        services.RemoveAll<IAlbumMatchingPort>();
                        services.AddSingleton(matcher);
                    }
                });
            });

        return factory.CreateClient();
    }

    private sealed class StubPostgresReadinessProbe(PostgresReadinessResult result) : IPostgresReadinessProbe
    {
        public Task<PostgresReadinessResult> CheckAsync(CancellationToken cancellationToken) =>
            Task.FromResult(result);
    }

    private sealed class HealthResponse
    {
        public string Status { get; init; } = string.Empty;

        public Dictionary<string, DependencyResponse> Dependencies { get; init; } = [];

        public ScanRuntimeResponse ScanRuntime { get; init; } = new();
    }

    private sealed class DependencyResponse
    {
        public string Status { get; init; } = string.Empty;

        public string Description { get; init; } = string.Empty;
    }

    private sealed class ScanRuntimeResponse
    {
        public string Matcher { get; init; } = string.Empty;

        public bool Configured { get; init; }
    }
}
