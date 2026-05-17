using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Options;

namespace DejaGroove.Api.Tests.Auth;

public sealed class IdentityJwtStartupValidationTests
{
    [Fact]
    public void Startup_WithMissingAuthority_FailsFast()
    {
        var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.ConfigureAppConfiguration((_, config) =>
                {
                    config.AddInMemoryCollection(new Dictionary<string, string?>
                    {
                        ["IdentityJwt:Authority"] = "",
                        ["IdentityJwt:Audience"] = "deja-groove-api",
                        ["IdentityJwt:RequireHttpsMetadata"] = "true",
                        ["IdentityJwt:ClockSkewSeconds"] = "120"
                    });
                });
            });

        var ex = Assert.Throws<OptionsValidationException>(() => factory.CreateClient());
        Assert.Contains("IdentityJwt:Authority is required", ex.Message);
    }
}
