using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Extensions.Options;
using Microsoft.IdentityModel.Tokens;

namespace DejaGroove.Api.Auth;

public sealed class ConfigureJwtBearerOptions(
    IOptions<IdentityJwtOptions> identityJwtOptions,
    ILoggerFactory loggerFactory) : IConfigureNamedOptions<JwtBearerOptions>
{
    public void Configure(string? name, JwtBearerOptions options)
    {
        if (name != JwtBearerDefaults.AuthenticationScheme)
            return;

        var jwtOptions = identityJwtOptions.Value;
        options.Authority = jwtOptions.Authority;
        if (!string.IsNullOrWhiteSpace(jwtOptions.MetadataAddress))
            options.MetadataAddress = jwtOptions.MetadataAddress;
        options.RequireHttpsMetadata = jwtOptions.RequireHttpsMetadata;
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidateAudience = true,
            ValidAudience = jwtOptions.Audience,
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(jwtOptions.ClockSkewSeconds),
            NameClaimType = "sub"
        };
        options.Events = new JwtBearerEvents
        {
            OnAuthenticationFailed = context =>
            {
                var logger = loggerFactory.CreateLogger("IdentityJwt");
                logger.LogWarning(
                    "JWT authentication failed. Path={Path} ExceptionType={ExceptionType} Authority={Authority} Audience={Audience}",
                    context.HttpContext.Request.Path,
                    context.Exception.GetType().Name,
                    jwtOptions.Authority,
                    jwtOptions.Audience);
                return Task.CompletedTask;
            }
        };
    }

    public void Configure(JwtBearerOptions options)
        => Configure(Options.DefaultName, options);
}
