using System.Net;
using System.Security.Claims;
using System.Text;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;

namespace DejaGroove.Api.Tests.Auth;

public sealed class IdentityContractEndpointTests
{
    private const string Issuer = "https://deja-groove.example";
    private const string Audience = "deja-groove-api";
    private const string SigningKey = "__SET_VIA_ENV_OR_USER_SECRETS_32_PLUS__";

    private static HttpClient CreateClient()
    {
        var factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.ConfigureAppConfiguration((_, config) =>
                {
                    config.AddInMemoryCollection(new Dictionary<string, string?>
                    {
                        ["IdentityJwt:Issuer"] = Issuer,
                        ["IdentityJwt:Audience"] = Audience,
                        ["IdentityJwt:SigningKey"] = SigningKey,
                        ["IdentityJwt:ClockSkewSeconds"] = "0"
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

    private static string BuildToken(string? subValue)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(SigningKey));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
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
