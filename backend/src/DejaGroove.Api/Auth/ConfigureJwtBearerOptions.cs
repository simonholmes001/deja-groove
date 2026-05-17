using System.Text;
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
        options.MapInboundClaims = false;
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwtOptions.Issuer,
            ValidateAudience = true,
            ValidAudience = jwtOptions.Audience,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtOptions.SigningKey)),
            ValidateLifetime = true,
            ClockSkew = TimeSpan.FromSeconds(jwtOptions.ClockSkewSeconds),
            NameClaimType = "sub"
        };
        options.Events = new JwtBearerEvents
        {
            OnAuthenticationFailed = context =>
            {
                var logger = loggerFactory.CreateLogger("IdentityJwt");
                logger.LogWarning(context.Exception, "JWT authentication failed for {Path}", context.HttpContext.Request.Path);
                return Task.CompletedTask;
            }
        };
    }

    public void Configure(JwtBearerOptions options)
        => Configure(Options.DefaultName, options);
}
