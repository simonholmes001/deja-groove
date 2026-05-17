using Microsoft.Extensions.Options;

namespace DejaGroove.Api.Auth;

public sealed class ValidateIdentityJwtOptions(IHostEnvironment env) : IValidateOptions<IdentityJwtOptions>
{
    private const int MinimumSigningKeyLength = 32;
    private const int MinimumClockSkewSeconds = 0;
    private const int MaximumClockSkewSeconds = 300;
    private const string PlaceholderPrefix = "__SET_VIA_ENV";

    public ValidateOptionsResult Validate(string? name, IdentityJwtOptions options)
    {
        if (string.IsNullOrWhiteSpace(options.Issuer))
            return ValidateOptionsResult.Fail($"{IdentityJwtOptions.SectionName}:Issuer is required");
        if (string.IsNullOrWhiteSpace(options.Audience))
            return ValidateOptionsResult.Fail($"{IdentityJwtOptions.SectionName}:Audience is required");
        if (string.IsNullOrWhiteSpace(options.SigningKey))
            return ValidateOptionsResult.Fail($"{IdentityJwtOptions.SectionName}:SigningKey is required");
        if (options.SigningKey.Length < MinimumSigningKeyLength)
            return ValidateOptionsResult.Fail($"{IdentityJwtOptions.SectionName}:SigningKey must be at least {MinimumSigningKeyLength} characters");
        if (options.ClockSkewSeconds < MinimumClockSkewSeconds || options.ClockSkewSeconds > MaximumClockSkewSeconds)
            return ValidateOptionsResult.Fail($"{IdentityJwtOptions.SectionName}:ClockSkewSeconds must be between {MinimumClockSkewSeconds} and {MaximumClockSkewSeconds}");

        if (!env.IsDevelopment() &&
            (options.SigningKey.StartsWith(PlaceholderPrefix, StringComparison.Ordinal) ||
             options.SigningKey.Contains("change-me", StringComparison.OrdinalIgnoreCase)))
        {
            return ValidateOptionsResult.Fail($"{IdentityJwtOptions.SectionName}:SigningKey placeholder is not allowed outside development");
        }

        return ValidateOptionsResult.Success;
    }
}
