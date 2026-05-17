using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Security.Claims;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace DejaGroove.Api.Tests.Auth;

public sealed class IdentityContractEndpointTests
{
    private const string Issuer = "https://deja-groove.example";
    private const string Audience = "deja-groove-api";
    private static readonly RsaSecurityKey SigningKey;

    static IdentityContractEndpointTests()
    {
        var rsa = RSA.Create(2048);
        SigningKey = new RsaSecurityKey(rsa) { KeyId = "test-kid-1" };
    }

    private static HttpClient CreateClient()
    {
        var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.ConfigureAppConfiguration((_, config) =>
                {
                    config.AddInMemoryCollection(new Dictionary<string, string?>
                    {
                        ["IdentityJwt:Authority"] = Issuer,
                        ["IdentityJwt:Audience"] = Audience,
                        ["IdentityJwt:RequireHttpsMetadata"] = "false",
                        ["IdentityJwt:ClockSkewSeconds"] = "0"
                    });
                });
                builder.ConfigureServices(services =>
                {
                    services.PostConfigure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
                    {
                        var oidcConfig = new OpenIdConnectConfiguration { Issuer = Issuer };
                        oidcConfig.SigningKeys.Add(SigningKey);
                        options.ConfigurationManager = new StaticConfigurationManager<OpenIdConnectConfiguration>(oidcConfig);
                        options.TokenValidationParameters.ValidIssuer = Issuer;
                        options.TokenValidationParameters.ValidAudience = Audience;
                        options.TokenValidationParameters.ValidateIssuerSigningKey = true;
                        options.TokenValidationParameters.IssuerSigningKey = SigningKey;
                    });
                });
            });
        return factory.CreateClient();
    }

    [Fact]
    public async Task ContractProbe_WithoutToken_Returns401()
    {
        using var client = CreateClient();
        var response = await client.GetAsync("/v1/identity/contract-probe");
        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task ContractProbe_WithEmptySub_IsDenied()
    {
        using var client = CreateClient();
        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", BuildToken(subValue: ""));

        var response = await client.GetAsync("/v1/identity/contract-probe");

        Assert.True(
            response.StatusCode is HttpStatusCode.Forbidden or HttpStatusCode.Unauthorized,
            $"Expected 401/403 but got {(int)response.StatusCode} ({response.StatusCode}).");
    }

    [Fact]
    public async Task ContractProbe_WithValidToken_Returns200AndClaimEnvelope()
    {
        using var client = CreateClient();
        client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", BuildToken(subValue: "user-123"));

        var response = await client.GetAsync("/v1/identity/contract-probe");
        var body = await response.Content.ReadAsStringAsync();

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        Assert.Contains("user-123", body);
        Assert.Contains(Audience, body);
        Assert.Contains(Issuer, body);
    }

    private static string BuildToken(string? subValue)
    {
        var creds = new SigningCredentials(SigningKey, SecurityAlgorithms.RsaSha256);
        var now = DateTime.UtcNow;
        var claims = new List<Claim>();
        if (subValue is not null)
            claims.Add(new Claim("sub", subValue));

        var token = new JwtSecurityToken(
            issuer: Issuer,
            audience: Audience,
            claims: claims,
            notBefore: now.AddMinutes(-1),
            expires: now.AddMinutes(10),
            signingCredentials: creds);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
