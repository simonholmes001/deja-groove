using Microsoft.Extensions.Options;

namespace DejaGroove.Api.Auth;

public sealed class ValidateIdentityJwtOptions(IHostEnvironment env) : IValidateOptions<IdentityJwtOptions>
{
    private const int MinimumClockSkewSeconds = 0;
    private const int MaximumClockSkewSeconds = 300;

    public ValidateOptionsResult Validate(string? name, IdentityJwtOptions options)
    {
        if (string.IsNullOrWhiteSpace(options.Authority))
            return ValidateOptionsResult.Fail($"{IdentityJwtOptions.SectionName}:Authority is required");
        if (string.IsNullOrWhiteSpace(options.Audience))
            return ValidateOptionsResult.Fail($"{IdentityJwtOptions.SectionName}:Audience is required");
        if (options.ClockSkewSeconds < MinimumClockSkewSeconds || options.ClockSkewSeconds > MaximumClockSkewSeconds)
            return ValidateOptionsResult.Fail($"{IdentityJwtOptions.SectionName}:ClockSkewSeconds must be between {MinimumClockSkewSeconds} and {MaximumClockSkewSeconds}");
        if (!options.RequireHttpsMetadata && !env.IsDevelopment())
            return ValidateOptionsResult.Fail($"{IdentityJwtOptions.SectionName}:RequireHttpsMetadata cannot be false outside development");

        return ValidateOptionsResult.Success;
    }
}
