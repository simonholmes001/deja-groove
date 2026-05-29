using DejaGroove.Api.Ports;
using DejaGroove.Application.Ports;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace DejaGroove.Api.Tests.Bootstrap;

public sealed class AlbumMatchingRegistrationTests
{
    [Fact]
    public void WithoutOpenAiKey_RegistersUnconfiguredAlbumMatcher()
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
        var matcher = scope.ServiceProvider.GetRequiredService<IAlbumMatchingPort>();
        Assert.IsType<UnconfiguredAlbumMatchingPort>(matcher);
    }
}
