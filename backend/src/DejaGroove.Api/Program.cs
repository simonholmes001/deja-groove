using DejaGroove.Api.Auth;
using DejaGroove.Api.Middleware;
using DejaGroove.Api.Requests;
using DejaGroove.Api.Validation;
using DejaGroove.Application.UseCases;
using FluentValidation;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddSingleton<IValidateOptions<IdentityJwtOptions>, ValidateIdentityJwtOptions>();
builder.Services.AddOptions<IdentityJwtOptions>()
    .Bind(builder.Configuration.GetSection(IdentityJwtOptions.SectionName))
    .ValidateOnStart();

// Suppress automatic 400 from DataAnnotations — FluentValidation owns all validation responses
builder.Services.Configure<ApiBehaviorOptions>(o =>
{
    o.SuppressModelStateInvalidFilter = true;
});

// Application layer — stub replaced by real orchestration in #12
builder.Services.AddScoped<IScanWorkflowUseCase, StubScanWorkflowUseCase>();

// Validation
builder.Services.AddScoped<IValidator<ScanRequest>, ScanRequestValidator>();

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer();
builder.Services.AddSingleton<IConfigureNamedOptions<JwtBearerOptions>, ConfigureJwtBearerOptions>();
builder.Services.AddAuthorization(options =>
{
    options.AddPolicy("IdentityContract", policy =>
    {
        policy.RequireAuthenticatedUser();
        policy.RequireAssertion(context =>
            context.User.Claims.Any(claim =>
                (claim.Type == "sub" || claim.Type == ClaimTypes.NameIdentifier) &&
                !string.IsNullOrWhiteSpace(claim.Value)));
    });
});

// Allow slightly over 10 MB so the controller can return a proper 413 envelope
builder.Services.Configure<Microsoft.AspNetCore.Http.Features.FormOptions>(o =>
{
    o.MultipartBodyLengthLimit = 11 * 1024 * 1024;
});
builder.WebHost.ConfigureKestrel(k =>
{
    k.Limits.MaxRequestBodySize = 11 * 1024 * 1024;
});

var app = builder.Build();

app.UseMiddleware<RequestIdMiddleware>();
app.UseMiddleware<ExceptionHandlingMiddleware>();
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();

// Expose Program for WebApplicationFactory in integration tests
public partial class Program { }
