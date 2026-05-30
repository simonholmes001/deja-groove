using DejaGroove.Api.Ports;
using DejaGroove.Api.Features;
using DejaGroove.Application.Ports;
using DejaGroove.Infrastructure.Persistence.Scanning;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace DejaGroove.Api.Tests.Bootstrap;

public sealed class AmbiguousScanRepositoryRegistrationTests
{
    [Fact]
    public void WithPostgresConnection_RegistersPostgresAmbiguousRepository()
    {
        using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment("Testing");
                builder.UseSetting("ConnectionStrings:Postgres", "Host=localhost;Database=deja;Username=test;Password=test");
                builder.ConfigureAppConfiguration((_, config) =>
                {
                    config.AddInMemoryCollection(new Dictionary<string, string?>
                    {
                        ["IdentityJwt:Authority"] = "https://identity.example",
                        ["IdentityJwt:Audience"] = "deja-groove-api",
                        ["ConnectionStrings:Postgres"] = "Host=localhost;Database=deja;Username=test;Password=test"
                    });
                });
            });

        using var scope = factory.Services.CreateScope();
        var repo = scope.ServiceProvider.GetRequiredService<IAmbiguousScanRepository>();
        Assert.IsType<PostgresAmbiguousScanRepository>(repo);
    }

    [Fact]
    public void WithoutPostgresConnection_InProduction_FailsClosedByDefault()
    {
        using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment("Production");
                builder.ConfigureAppConfiguration((_, config) =>
                {
                    config.AddInMemoryCollection(new Dictionary<string, string?>
                    {
                        ["IdentityJwt:Authority"] = "https://identity.example",
                        ["IdentityJwt:Audience"] = "deja-groove-api"
                    });
                });
            });

        using var scope = factory.Services.CreateScope();
        var repo = scope.ServiceProvider.GetRequiredService<IAmbiguousScanRepository>();
        Assert.IsType<UnconfiguredAmbiguousScanRepository>(repo);
    }

    [Fact]
    public void WithStubRuntimeFlag_InProduction_RegistersInMemoryAmbiguousRepository()
    {
        using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment("Production");
                builder.UseSetting($"{ScanFeaturesOptions.SectionName}:{nameof(ScanFeaturesOptions.UseStubScanRuntime)}", "true");
                builder.ConfigureAppConfiguration((_, config) =>
                {
                    config.AddInMemoryCollection(new Dictionary<string, string?>
                    {
                        ["IdentityJwt:Authority"] = "https://identity.example",
                        ["IdentityJwt:Audience"] = "deja-groove-api"
                    });
                });
            });

        using var scope = factory.Services.CreateScope();
        var repo = scope.ServiceProvider.GetRequiredService<IAmbiguousScanRepository>();
        Assert.IsType<InMemoryAmbiguousScanRepository>(repo);
    }
}
