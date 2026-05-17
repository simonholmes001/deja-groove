using System.Security.Claims;
using DejaGroove.Api.Auth;
using DejaGroove.Api.Controllers;
using DejaGroove.Api.Middleware;
using DejaGroove.Application.Ports;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.FileProviders;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace DejaGroove.Api.Tests.Auth;

public sealed class AuthOptionsAndPortsTests
{
    [Fact]
    public void ValidationResult_OkAndFail_ConstructExpectedValues()
    {
        var ok = ValidationResult.Ok();
        var fail = ValidationResult.Fail("bad_image", "bad");

        Assert.True(ok.IsValid);
        Assert.False(fail.IsValid);
        Assert.Equal("bad_image", fail.ErrorCode);
        Assert.Equal("bad", fail.ErrorMessage);
    }

    [Fact]
    public void ValidateIdentityJwtOptions_RejectsInvalidClockSkew()
    {
        var sut = new ValidateIdentityJwtOptions(new StubHostEnvironment("Production"));
        var bad = new IdentityJwtOptions
        {
            Issuer = "iss",
            Audience = "aud",
            SigningKey = "abcdefghijklmnopqrstuvwxyz123456",
            ClockSkewSeconds = 999
        };

        var result = sut.Validate(null, bad);
        Assert.True(result.Failed);
    }

    [Fact]
    public void ValidateIdentityJwtOptions_AllowsDevelopmentPlaceholder()
    {
        var sut = new ValidateIdentityJwtOptions(new StubHostEnvironment("Development"));
        var opts = new IdentityJwtOptions
        {
            Issuer = "iss",
            Audience = "aud",
            SigningKey = "__SET_VIA_ENV_OR_USER_SECRETS_32_PLUS__",
            ClockSkewSeconds = 60
        };

        var result = sut.Validate(null, opts);
        Assert.True(result.Succeeded);
    }

    [Fact]
    public void ConfigureJwtBearerOptions_SetsExpectedValidationParameters()
    {
        var opts = Options.Create(new IdentityJwtOptions
        {
            Issuer = "iss",
            Audience = "aud",
            SigningKey = "abcdefghijklmnopqrstuvwxyz123456",
            ClockSkewSeconds = 42
        });
        var sut = new ConfigureJwtBearerOptions(opts, NullLoggerFactory.Instance);
        var jwt = new JwtBearerOptions();

        sut.Configure(JwtBearerDefaults.AuthenticationScheme, jwt);

        Assert.False(jwt.MapInboundClaims);
        Assert.Equal("iss", jwt.TokenValidationParameters.ValidIssuer);
        Assert.Equal("aud", jwt.TokenValidationParameters.ValidAudience);
        Assert.Equal(TimeSpan.FromSeconds(42), jwt.TokenValidationParameters.ClockSkew);
        Assert.NotNull(jwt.Events?.OnAuthenticationFailed);
    }

    [Fact]
    public async Task ExceptionHandlingMiddleware_WhenDelegateThrows_Writes500Envelope()
    {
        var context = new DefaultHttpContext();
        context.Items[RequestIdMiddleware.RequestIdKey] = Guid.NewGuid();
        var sut = new ExceptionHandlingMiddleware(
            _ => throw new InvalidOperationException("boom"),
            NullLogger<ExceptionHandlingMiddleware>.Instance);

        await sut.InvokeAsync(context);

        Assert.Equal(StatusCodes.Status500InternalServerError, context.Response.StatusCode);
        Assert.Equal("application/json", context.Response.ContentType);
    }

    [Fact]
    public void IdentityContractController_UsesClaimsAndRequestId()
    {
        var controller = new IdentityContractController();
        var context = new DefaultHttpContext();
        var requestId = Guid.NewGuid();
        context.Items[RequestIdMiddleware.RequestIdKey] = requestId;
        context.User = new ClaimsPrincipal(new ClaimsIdentity(new[]
        {
            new Claim("sub", "user-1"),
            new Claim("aud", "api"),
            new Claim("iss", "issuer")
        }, "test"));
        controller.ControllerContext = new ControllerContext { HttpContext = context };

        var result = controller.GetContractProbe() as OkObjectResult;

        Assert.NotNull(result);
        var json = System.Text.Json.JsonSerializer.Serialize(result!.Value);
        Assert.Contains(requestId.ToString(), json);
        Assert.Contains("user-1", json);
        Assert.Contains("api", json);
        Assert.Contains("issuer", json);
    }

    private sealed class StubHostEnvironment(string name) : Microsoft.Extensions.Hosting.IHostEnvironment
    {
        public string EnvironmentName { get; set; } = name;
        public string ApplicationName { get; set; } = "Tests";
        public string ContentRootPath { get; set; } = "/";
        public IFileProvider ContentRootFileProvider { get; set; } = new NullFileProvider();
    }
}
