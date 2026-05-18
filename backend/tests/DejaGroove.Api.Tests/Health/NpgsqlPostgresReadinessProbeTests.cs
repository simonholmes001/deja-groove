using DejaGroove.Api.Health;
using Microsoft.Extensions.Configuration;

namespace DejaGroove.Api.Tests.Health;

public sealed class NpgsqlPostgresReadinessProbeTests
{
    [Fact]
    public async Task CheckAsync_WhenNoConfiguredConnectionStrings_ReturnsNotConfigured()
    {
        var configuration = new ConfigurationBuilder().AddInMemoryCollection([]).Build();
        var probe = new NpgsqlPostgresReadinessProbe(configuration);

        var result = await probe.CheckAsync(CancellationToken.None);

        Assert.False(result.Healthy);
        Assert.Contains("Postgres or ConnectionStrings:PostgresAdmin", result.Description);
    }

    [Fact]
    public async Task CheckAsync_UsesPostgresAdminFallbackWhenPostgresIsMissing()
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["ConnectionStrings:PostgresAdmin"] = "Host=127.0.0.1;Port=1;Database=postgres;Username=test;Password=test;Timeout=1;Command Timeout=1"
            })
            .Build();
        var probe = new NpgsqlPostgresReadinessProbe(configuration);

        var result = await probe.CheckAsync(CancellationToken.None);

        Assert.False(result.Healthy);
        Assert.Equal("PostgreSQL connection failed.", result.Description);
    }
}
