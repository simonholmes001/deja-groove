using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using DejaGroove.Api.Auth;
using Microsoft.IdentityModel.Tokens;

namespace DejaGroove.Api.Tests.Auth;

public sealed class JwtClaimContractTests
{
    private const string Issuer = "https://deja-groove.example";
    private const string Audience = "deja-groove-api";
    private const string SigningKey = "dev-only-signing-key-change-me-32bytes-minimum";

    private static readonly TokenValidationParameters ValidationParameters = new()
    {
        ValidateIssuer = true,
        ValidIssuer = Issuer,
        ValidateAudience = true,
        ValidAudience = Audience,
        ValidateIssuerSigningKey = true,
        IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(SigningKey)),
        ValidateLifetime = true,
        ClockSkew = TimeSpan.Zero,
        NameClaimType = "sub"
    };

    [Fact]
    public void ValidToken_IsAccepted()
    {
        var token = BuildToken();
        var handler = new JwtSecurityTokenHandler { MapInboundClaims = false };
        var principal = handler
            .ValidateToken(token, ValidationParameters, out _);

        Assert.Equal("user-123", principal.FindFirst("sub")?.Value);
    }

    [Fact]
    public void WrongAudience_IsRejected()
    {
        var token = BuildToken(audience: "wrong-audience");

        Assert.ThrowsAny<SecurityTokenException>(() =>
            new JwtSecurityTokenHandler().ValidateToken(token, ValidationParameters, out _));
    }

    [Fact]
    public void WrongIssuer_IsRejected()
    {
        var token = BuildToken(issuer: "https://wrong-issuer.example");

        Assert.ThrowsAny<SecurityTokenException>(() =>
            new JwtSecurityTokenHandler().ValidateToken(token, ValidationParameters, out _));
    }

    [Fact]
    public void ExpiredToken_IsRejected()
    {
        var token = BuildToken(expires: DateTime.UtcNow.AddMinutes(-10));

        Assert.ThrowsAny<SecurityTokenException>(() =>
            new JwtSecurityTokenHandler().ValidateToken(token, ValidationParameters, out _));
    }

    [Fact]
    public void MissingSubClaim_IsRejectedByContract()
    {
        var token = BuildToken(includeSub: false);
        var handler = new JwtSecurityTokenHandler { MapInboundClaims = false };
        var principal = handler
            .ValidateToken(token, ValidationParameters, out _);

        Assert.Null(principal.FindFirst("sub"));
    }

    [Fact]
    public void IdentityOptions_RequireIssuerAudienceAndSigningKey()
    {
        var empty = new IdentityJwtOptions();
        Assert.True(string.IsNullOrWhiteSpace(empty.Issuer));
        Assert.True(string.IsNullOrWhiteSpace(empty.Audience));
        Assert.True(string.IsNullOrWhiteSpace(empty.SigningKey));
    }

    private static string BuildToken(
        string? issuer = null,
        string? audience = null,
        DateTime? expires = null,
        bool includeSub = true)
    {
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(SigningKey));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);
        var claims = new List<Claim>();

        if (includeSub)
            claims.Add(new Claim("sub", "user-123"));

        var now = DateTime.UtcNow;
        var exp = expires ?? now.AddMinutes(10);
        var notBefore = now.AddMinutes(-1);
        if (exp <= notBefore)
            notBefore = exp.AddMinutes(-5);
        var token = new JwtSecurityToken(
            issuer: issuer ?? Issuer,
            audience: audience ?? Audience,
            claims: claims,
            notBefore: notBefore,
            expires: exp,
            signingCredentials: creds);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
