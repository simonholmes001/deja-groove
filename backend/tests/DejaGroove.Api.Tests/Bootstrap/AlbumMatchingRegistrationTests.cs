using DejaGroove.Api.Ports;
using DejaGroove.Api.Features;
using DejaGroove.Application.Ports;
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
    public void WithoutOpenAiKey_InProduction_RegistersUnconfiguredScanDependenciesAndLeavesResolveDisabled()
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
        Assert.IsType<UnconfiguredImageValidationPort>(scope.ServiceProvider.GetRequiredService<IImageValidationPort>());
        Assert.IsType<UnconfiguredPerceptualHashPort>(scope.ServiceProvider.GetRequiredService<IPerceptualHashPort>());
        Assert.IsType<UnconfiguredScanCachePort>(scope.ServiceProvider.GetRequiredService<IScanCachePort>());
        Assert.IsType<UnconfiguredAlbumMatchingPort>(scope.ServiceProvider.GetRequiredService<IAlbumMatchingPort>());
        Assert.IsType<UnconfiguredCollectionOwnershipPort>(scope.ServiceProvider.GetRequiredService<ICollectionOwnershipPort>());
        Assert.IsType<UnconfiguredScanEventRepository>(scope.ServiceProvider.GetRequiredService<IScanEventRepository>());
        Assert.False(scope.ServiceProvider.GetRequiredService<IOptions<ScanFeaturesOptions>>().Value.EnableResolveEndpoint);
    }
}
