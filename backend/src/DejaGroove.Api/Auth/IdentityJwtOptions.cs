namespace DejaGroove.Api.Auth;

public sealed class IdentityJwtOptions
{
    public const string SectionName = "IdentityJwt";

    public string Issuer { get; init; } = string.Empty;

    public string Audience { get; init; } = string.Empty;

    public string SigningKey { get; init; } = string.Empty;

    public int ClockSkewSeconds { get; init; } = 120;
}
