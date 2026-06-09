using DejaGroove.Api.Ports;
using DejaGroove.Api.Features;
using DejaGroove.Application.Ports;
using DejaGroove.Infrastructure.Persistence.Caching;
using DejaGroove.Infrastructure.Persistence.Scanning;
using DejaGroove.Infrastructure.Recognition;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Options;

namespace DejaGroove.Api.Tests.Bootstrap;

public sealed class AlbumMatchingRegistrationTests
{
    [Fact]
    public void WithoutOpenAiKey_InTesting_RegistersUnconfiguredAlbumMatcherButKeepsStubbedScanDependencies()
    {
        using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment("Testing");
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
        Assert.IsType<StubImageValidationPort>(scope.ServiceProvider.GetRequiredService<IImageValidationPort>());
        Assert.IsType<StubPerceptualHashPort>(scope.ServiceProvider.GetRequiredService<IPerceptualHashPort>());
        Assert.IsType<InMemoryScanCachePort>(scope.ServiceProvider.GetRequiredService<IScanCachePort>());
        var matcher = scope.ServiceProvider.GetRequiredService<IAlbumMatchingPort>();
        Assert.IsType<StubCollectionOwnershipPort>(scope.ServiceProvider.GetRequiredService<ICollectionOwnershipPort>());
        Assert.IsType<InMemoryScanEventRepository>(scope.ServiceProvider.GetRequiredService<IScanEventRepository>());
        Assert.IsType<UnconfiguredAlbumMatchingPort>(matcher);
        Assert.True(scope.ServiceProvider.GetRequiredService<IOptions<ScanFeaturesOptions>>().Value.EnableResolveEndpoint);
    }

    [Fact]
    public void WithoutOpenAiKey_InProduction_FailsClosedByDefault()
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
        Assert.IsType<ImageHeaderValidationPort>(scope.ServiceProvider.GetRequiredService<IImageValidationPort>());
        Assert.IsType<Sha256PerceptualHashPort>(scope.ServiceProvider.GetRequiredService<IPerceptualHashPort>());
        Assert.IsType<UnconfiguredScanCachePort>(scope.ServiceProvider.GetRequiredService<IScanCachePort>());
        Assert.IsType<UnconfiguredAlbumMatchingPort>(scope.ServiceProvider.GetRequiredService<IAlbumMatchingPort>());
        Assert.IsType<UnconfiguredCollectionOwnershipPort>(scope.ServiceProvider.GetRequiredService<ICollectionOwnershipPort>());
        Assert.IsType<UnconfiguredScanEventRepository>(scope.ServiceProvider.GetRequiredService<IScanEventRepository>());
        Assert.False(scope.ServiceProvider.GetRequiredService<IOptions<ScanFeaturesOptions>>().Value.EnableResolveEndpoint);
    }

    [Fact]
    public void WithOpenAiKeyAndPostgres_InProduction_RegistersRealScanRuntime()
    {
        using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment("Production");
                builder.UseSetting("OPENAI_KEY", "test-openai-key");
                builder.UseSetting("OpenAi:BaseUrl", "https://example.invalid");
                builder.UseSetting("OpenAi:Model", "gpt-test");
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
        Assert.IsType<ImageHeaderValidationPort>(scope.ServiceProvider.GetRequiredService<IImageValidationPort>());
        Assert.IsType<Sha256PerceptualHashPort>(scope.ServiceProvider.GetRequiredService<IPerceptualHashPort>());
        Assert.IsType<PostgresScanCachePort>(scope.ServiceProvider.GetRequiredService<IScanCachePort>());
        Assert.IsType<OpenAiAlbumMatchingPort>(scope.ServiceProvider.GetRequiredService<IAlbumMatchingPort>());
        Assert.IsType<PostgresCollectionOwnershipPort>(scope.ServiceProvider.GetRequiredService<ICollectionOwnershipPort>());
        Assert.IsType<PostgresScanEventRepository>(scope.ServiceProvider.GetRequiredService<IScanEventRepository>());
        Assert.IsType<PostgresAmbiguousScanRepository>(scope.ServiceProvider.GetRequiredService<IAmbiguousScanRepository>());
    }

    [Fact]
    public void WithExplicitScanRuntime_InProduction_FailsFast()
    {
        using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment("Production");
                builder.UseSetting($"{ScanFeaturesOptions.SectionName}:{nameof(ScanFeaturesOptions.UseStubScanRuntime)}", "true");
                builder.UseSetting($"{ScanFeaturesOptions.SectionName}:{nameof(ScanFeaturesOptions.EnableResolveEndpoint)}", "true");
                builder.ConfigureAppConfiguration((_, config) =>
                {
                    config.AddInMemoryCollection(new Dictionary<string, string?>
                    {
                        ["IdentityJwt:Authority"] = "https://identity.example",
                        ["IdentityJwt:Audience"] = "deja-groove-api"
                    });
                });
            });

        var exception = Assert.Throws<InvalidOperationException>(() => factory.CreateClient());
        Assert.Contains("Stub scan runtime is only allowed in the Testing environment", exception.Message);
    }

    [Fact]
    public void WithOpenAiKey_InProduction_WithoutPostgresScanPersistence_FailsFast()
    {
        using var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseEnvironment("Production");
                builder.UseSetting("OPENAI_KEY", "test-openai-key");
                builder.UseSetting("OpenAi:BaseUrl", "https://example.invalid");
                builder.UseSetting("OpenAi:Model", "gpt-test");
                builder.ConfigureAppConfiguration((_, config) =>
                {
                    config.AddInMemoryCollection(new Dictionary<string, string?>
                    {
                        ["IdentityJwt:Authority"] = "https://identity.example",
                        ["IdentityJwt:Audience"] = "deja-groove-api"
                    });
                });
            });

        var exception = Assert.Throws<InvalidOperationException>(() => factory.CreateClient());
        Assert.Contains("PostgreSQL-backed scan cache", exception.Message);
    }
}
