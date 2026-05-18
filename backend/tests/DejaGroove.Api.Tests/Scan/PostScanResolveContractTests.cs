using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using DejaGroove.Api.Responses;
using DejaGroove.Application.Commands;
using DejaGroove.Application.Exceptions;
using DejaGroove.Application.UseCases;
using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace DejaGroove.Api.Tests.Scan;

public sealed class PostScanResolveContractTests
{
    private const string Issuer = "https://deja-groove.example";
    private const string Audience = "deja-groove-api";
    private static readonly RsaSecurityKey SigningKey;

    static PostScanResolveContractTests()
    {
        var rsa = RSA.Create(2048);
        SigningKey = new RsaSecurityKey(rsa) { KeyId = "test-kid-1" };
    }

    [Fact]
    public async Task Resolve_WhenRequestNotFound_Returns404Envelope()
    {
        var requestId = Guid.NewGuid();
        using var client = CreateClient(new ThrowingResolveUseCase(new NotFoundException("scan_request_not_found", "missing")));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", BuildToken(Guid.NewGuid().ToString()));

        var response = await client.PostAsync($"/v1/scan/{requestId}/resolve", BuildBody("mbid-1", null));

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
        var body = await DeserializeAsync<ErrorResponse>(response);
        Assert.Equal("scan_request_not_found", body.Error.Code);
    }

    [Fact]
    public async Task Resolve_WhenRequestNotAmbiguous_Returns409Envelope()
    {
        var requestId = Guid.NewGuid();
        using var client = CreateClient(new ThrowingResolveUseCase(new ConflictException("scan_request_not_ambiguous", "conflict")));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", BuildToken(Guid.NewGuid().ToString()));

        var response = await client.PostAsync($"/v1/scan/{requestId}/resolve", BuildBody("mbid-1", null));

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        var body = await DeserializeAsync<ErrorResponse>(response);
        Assert.Equal("scan_request_not_ambiguous", body.Error.Code);
    }

    [Fact]
    public async Task Resolve_WhenSelectionInvalid_Returns422Envelope()
    {
        var requestId = Guid.NewGuid();
        using var client = CreateClient(new ThrowingResolveUseCase(new UnprocessableEntityException("candidate_not_in_original_set", "invalid")));
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", BuildToken(Guid.NewGuid().ToString()));

        var response = await client.PostAsync($"/v1/scan/{requestId}/resolve", BuildBody("mbid-x", null));

        Assert.Equal((HttpStatusCode)422, response.StatusCode);
        var body = await DeserializeAsync<ErrorResponse>(response);
        Assert.Equal("candidate_not_in_original_set", body.Error.Code);
    }

    [Fact]
    public async Task Resolve_ReplaySameSelection_IsIdempotent()
    {
        var requestId = Guid.NewGuid();
        var selected = AlbumIdentity.Create("mbid-1", null, "Kind of Blue", "Miles Davis", 1959);
        var result = ScanResult.SafeToBuy(selected, 0.6f);
        var useCase = new RecordingResolveUseCase(result);

        using var client = CreateClient(useCase);
        var userId = Guid.NewGuid();
        client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", BuildToken(userId.ToString()));

        var first = await client.PostAsync($"/v1/scan/{requestId}/resolve", BuildBody("mbid-1", null));
        var second = await client.PostAsync($"/v1/scan/{requestId}/resolve", BuildBody("mbid-1", null));

        Assert.Equal(HttpStatusCode.OK, first.StatusCode);
        Assert.Equal(HttpStatusCode.OK, second.StatusCode);
        Assert.Equal(2, useCase.Calls.Count);
        Assert.Equal(useCase.Calls[0], useCase.Calls[1]);
    }

    private static HttpClient CreateClient(IResolveAmbiguousScanUseCase resolveUseCase)
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
                    services.AddSingleton(resolveUseCase);
                    var oidcConfig = new OpenIdConnectConfiguration { Issuer = Issuer };
                    oidcConfig.SigningKeys.Add(SigningKey);
                    services.PostConfigure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
                    {
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

    private static HttpContent BuildBody(string? mbid, string? discogs)
    {
        var payload = JsonSerializer.Serialize(new { selected_mbid = mbid, selected_discogs_release_id = discogs });
        return new StringContent(payload, Encoding.UTF8, "application/json");
    }

    private static string BuildToken(string sub)
    {
        var creds = new SigningCredentials(SigningKey, SecurityAlgorithms.RsaSha256);
        var now = DateTime.UtcNow;
        var token = new JwtSecurityToken(
            issuer: Issuer,
            audience: Audience,
            claims: [new Claim("sub", sub)],
            notBefore: now.AddMinutes(-1),
            expires: now.AddMinutes(10),
            signingCredentials: creds);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }

    private static async Task<T> DeserializeAsync<T>(HttpResponseMessage response)
    {
        var json = await response.Content.ReadAsStringAsync();
        return JsonSerializer.Deserialize<T>(json)!;
    }

    private sealed class ThrowingResolveUseCase(Exception exception) : IResolveAmbiguousScanUseCase
    {
        public Task<ScanResult> ExecuteAsync(ResolveAmbiguousScanCommand command, CancellationToken ct = default) => Task.FromException<ScanResult>(exception);
    }

    private sealed class RecordingResolveUseCase(ScanResult result) : IResolveAmbiguousScanUseCase
    {
        public List<ResolveAmbiguousScanCommand> Calls { get; } = [];

        public Task<ScanResult> ExecuteAsync(ResolveAmbiguousScanCommand command, CancellationToken ct = default)
        {
            Calls.Add(command);
            return Task.FromResult(result);
        }
    }
}
