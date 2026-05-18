using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.IdentityModel.Protocols;
using Microsoft.IdentityModel.Protocols.OpenIdConnect;
using Microsoft.IdentityModel.Tokens;

namespace DejaGroove.Api.Tests.Collection;

public sealed class CollectionContractTests
{
    private const string Issuer = "https://deja-groove.example";
    private const string Audience = "deja-groove-api";
    private static readonly RsaSecurityKey SigningKey;

    static CollectionContractTests()
    {
        var rsa = RSA.Create(2048);
        SigningKey = new RsaSecurityKey(rsa) { KeyId = "test-kid-collection" };
    }

    private static HttpClient CreateClient(string subject = "collector-1")
    {
        var factory = new WebApplicationFactory<Program>().WithWebHostBuilder(builder =>
        {
            builder.ConfigureAppConfiguration((_, config) =>
                config.AddInMemoryCollection(new Dictionary<string, string?>
                {
                    ["IdentityJwt:Authority"] = Issuer,
                    ["IdentityJwt:Audience"] = Audience,
                    ["IdentityJwt:RequireHttpsMetadata"] = "false",
                    ["IdentityJwt:ClockSkewSeconds"] = "0"
                }));
            builder.ConfigureServices(services =>
                services.PostConfigure<JwtBearerOptions>(JwtBearerDefaults.AuthenticationScheme, options =>
                {
                    var oidc = new OpenIdConnectConfiguration { Issuer = Issuer };
                    oidc.SigningKeys.Add(SigningKey);
                    options.ConfigurationManager =
                        new StaticConfigurationManager<OpenIdConnectConfiguration>(oidc);
                    options.TokenValidationParameters.ValidIssuer = Issuer;
                    options.TokenValidationParameters.ValidAudience = Audience;
                    options.TokenValidationParameters.IssuerSigningKey = SigningKey;
                }));
        });

        var client = factory.CreateClient();
        client.DefaultRequestHeaders.Authorization =
            new AuthenticationHeaderValue("Bearer", BuildToken(subject));
        return client;
    }

    private static object Album(string mbid = "mbid-rumours", string? notes = "VG+") =>
        new { mbid, title = "Rumours", artist = "Fleetwood Mac", year = 1977, notes };

    [Fact]
    public async Task Post_WithoutToken_Returns401()
    {
        using var factory = new WebApplicationFactory<Program>();
        using var client = factory.CreateClient();

        var response = await client.PostAsJsonAsync("/v1/collection", Album());

        Assert.Equal(HttpStatusCode.Unauthorized, response.StatusCode);
    }

    [Fact]
    public async Task Post_NewAlbum_Returns201WithId()
    {
        using var client = CreateClient();

        var response = await client.PostAsJsonAsync("/v1/collection", Album());

        Assert.Equal(HttpStatusCode.Created, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.NotEqual(Guid.Empty, body.GetProperty("id").GetGuid());
    }

    [Fact]
    public async Task Post_NoIdentityFields_Returns400()
    {
        using var client = CreateClient();

        var response = await client.PostAsJsonAsync("/v1/collection",
            new { notes = "nothing identifying" });

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Post_DuplicateAlbum_Returns409DuplicateDetected()
    {
        using var client = CreateClient();
        await client.PostAsJsonAsync("/v1/collection", Album());

        var response = await client.PostAsJsonAsync("/v1/collection", Album());

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("duplicate_detected", body.GetProperty("error").GetString());
        Assert.True(body.TryGetProperty("existing", out _));
    }

    [Fact]
    public async Task Post_AddAnyway_CannotDefeatUniquenessConstraint_Returns409()
    {
        // add_anyway skips the *application* duplicate pre-check, but the DB
        // uniqueness guarantees still hold — including the V012 title/artist
        // index. An exact active duplicate is always rejected, so dedup is
        // total even when the caller forces the add (blocker M2).
        using var client = CreateClient();
        var album = new { title = "Untitled Demo", artist = "Local Band", year = 2024 };
        await client.PostAsJsonAsync("/v1/collection", album);

        var response = await client.PostAsJsonAsync("/v1/collection",
            new { title = "Untitled Demo", artist = "Local Band", year = 2024, add_anyway = true });

        Assert.Equal(HttpStatusCode.Conflict, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("duplicate_detected", body.GetProperty("error").GetString());
    }

    [Fact]
    public async Task Post_SameIdempotencyKeySameBody_ReplaysSameRecord()
    {
        using var client = CreateClient();
        var first = await PostWithKeyAsync(client, "key-1", Album());
        var firstId = (await first.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();

        var replay = await PostWithKeyAsync(client, "key-1", Album());

        Assert.Equal(HttpStatusCode.OK, replay.StatusCode);
        var replayId = (await replay.Content.ReadFromJsonAsync<JsonElement>()).GetProperty("id").GetGuid();
        Assert.Equal(firstId, replayId);
    }

    [Fact]
    public async Task Post_SameIdempotencyKeyDifferentBody_Returns409()
    {
        using var client = CreateClient();
        await PostWithKeyAsync(client, "key-2", Album(notes: "first"));

        var conflict = await PostWithKeyAsync(client, "key-2", Album(notes: "different"));

        Assert.Equal(HttpStatusCode.Conflict, conflict.StatusCode);
        var body = await conflict.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("idempotency_key_reused", body.GetProperty("error").GetProperty("code").GetString());
    }

    [Fact]
    public async Task Get_List_ReturnsCallerItemsOnly()
    {
        using var client = CreateClient("owner-A");
        await client.PostAsJsonAsync("/v1/collection", Album());

        var response = await client.GetAsync("/v1/collection");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal(1, body.GetProperty("items").GetArrayLength());
    }

    [Fact]
    public async Task Get_UnsupportedSort_Returns400()
    {
        using var client = CreateClient();

        var response = await client.GetAsync("/v1/collection?sort=year");

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var body = await response.Content.ReadFromJsonAsync<JsonElement>();
        Assert.Equal("unsupported_sort", body.GetProperty("error").GetProperty("code").GetString());
    }

    [Fact]
    public async Task Get_SortByTitle_ReturnsAlphabeticalOrder()
    {
        using var client = CreateClient("sorter-1");
        foreach (var t in new[] { "Zoo", "Apple", "Mango" })
            await client.PostAsJsonAsync("/v1/collection",
                new { title = t, artist = "VA", year = 2001 });

        var response = await client.GetAsync("/v1/collection?sort=title&dir=asc");

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var items = (await response.Content.ReadFromJsonAsync<JsonElement>())
            .GetProperty("items").EnumerateArray()
            .Select(e => e.GetProperty("title").GetString()).ToList();
        Assert.Equal(new[] { "Apple", "Mango", "Zoo" }, items);
    }

    [Fact]
    public async Task GetById_Unknown_Returns404()
    {
        using var client = CreateClient();

        var response = await client.GetAsync($"/v1/collection/{Guid.NewGuid()}");

        Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
    }

    private static Task<HttpResponseMessage> PostWithKeyAsync(
        HttpClient client, string key, object body)
    {
        var message = new HttpRequestMessage(HttpMethod.Post, "/v1/collection")
        {
            Content = JsonContent.Create(body)
        };
        message.Headers.Add("Idempotency-Key", key);
        return client.SendAsync(message);
    }

    private static string BuildToken(string sub)
    {
        var creds = new SigningCredentials(SigningKey, SecurityAlgorithms.RsaSha256);
        var token = new JwtSecurityToken(
            issuer: Issuer,
            audience: Audience,
            claims: [new Claim("sub", sub)],
            notBefore: DateTime.UtcNow.AddMinutes(-1),
            expires: DateTime.UtcNow.AddMinutes(10),
            signingCredentials: creds);
        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
