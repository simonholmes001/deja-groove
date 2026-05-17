namespace DejaGroove.Api.Auth;

public sealed class IdentityJwtOptions
{
    public const string SectionName = "IdentityJwt";

    public string Authority { get; init; } = string.Empty;

    public string? MetadataAddress { get; init; }

    public string Audience { get; init; } = string.Empty;

    public bool RequireHttpsMetadata { get; init; } = true;

    public int ClockSkewSeconds { get; init; } = 120;
}
