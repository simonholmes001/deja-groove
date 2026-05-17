using DejaGroove.Api.Auth;
using DejaGroove.Api.Middleware;
using DejaGroove.Api.Ports;
using DejaGroove.Api.Requests;
using DejaGroove.Api.Validation;
using DejaGroove.Application.Ports;
using DejaGroove.Application.UseCases;
using DejaGroove.Infrastructure.Persistence.Migrations;
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

// Application layer
builder.Services.AddScoped<IScanWorkflowUseCase, ScanWorkflowUseCase>();
if (builder.Environment.IsDevelopment() || builder.Environment.IsEnvironment("Testing"))
{
    builder.Services.AddSingleton<IImageValidationPort, StubImageValidationPort>();
    builder.Services.AddSingleton<IPerceptualHashPort, StubPerceptualHashPort>();
    builder.Services.AddSingleton<IScanCachePort, InMemoryScanCachePort>();
    builder.Services.AddSingleton<IAlbumMatchingPort, StubAlbumMatchingPort>();
    builder.Services.AddSingleton<ICollectionOwnershipPort, StubCollectionOwnershipPort>();
    builder.Services.AddSingleton<IScanEventRepository, InMemoryScanEventRepository>();
}
else
{
    builder.Services.AddSingleton<IImageValidationPort, UnconfiguredImageValidationPort>();
    builder.Services.AddSingleton<IPerceptualHashPort, UnconfiguredPerceptualHashPort>();
    builder.Services.AddSingleton<IScanCachePort, UnconfiguredScanCachePort>();
    builder.Services.AddSingleton<IAlbumMatchingPort, UnconfiguredAlbumMatchingPort>();
    builder.Services.AddSingleton<ICollectionOwnershipPort, UnconfiguredCollectionOwnershipPort>();
    builder.Services.AddSingleton<IScanEventRepository, UnconfiguredScanEventRepository>();
}

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

// Run database migrations before accepting traffic.
// MigrationRunner retries on NpgsqlException to tolerate a brief delay while
// the Flexible Server becomes ready after a cold start or failover.
// An empty connection string skips migration — used by HTTP-only contract
// tests that exercise the API shape without a real database.
var connectionString = app.Configuration.GetConnectionString("Postgres");
if (!string.IsNullOrWhiteSpace(connectionString))
{
    var migrationLogger = app.Services
        .GetRequiredService<ILoggerFactory>()
        .CreateLogger<MigrationRunner>();
    await new MigrationRunner(connectionString, migrationLogger).ApplyAsync();
}

app.UseMiddleware<RequestIdMiddleware>();
app.UseMiddleware<ExceptionHandlingMiddleware>();
app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

app.Run();

// Expose Program for WebApplicationFactory in integration tests
public partial class Program { }
