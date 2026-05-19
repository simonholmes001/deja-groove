using DejaGroove.Api.Auth;
using DejaGroove.Api.Features;
using DejaGroove.Api.Middleware;
using DejaGroove.Api.Ports;
using DejaGroove.Api.Requests;
using DejaGroove.Api.Validation;
using DejaGroove.Api.Health;
using DejaGroove.Application.Ports;
using DejaGroove.Application.UseCases;
using DejaGroove.Api.Hosting;
using DejaGroove.Infrastructure.Persistence;
using DejaGroove.Infrastructure.Persistence.Caching;
using DejaGroove.Infrastructure.Persistence.Collection;
using DejaGroove.Infrastructure.Persistence.Scanning;
using DejaGroove.Infrastructure.Persistence.Migrations;
using FluentValidation;
using System.Security.Claims;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using DejaGroove.Api.Errors;
using Microsoft.Extensions.Options;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();
builder.Services.AddOptions<ScanFeaturesOptions>()
    .Bind(builder.Configuration.GetSection(ScanFeaturesOptions.SectionName));
builder.Services.PostConfigure<ScanFeaturesOptions>(o =>
{
    if (builder.Environment.IsDevelopment() || builder.Environment.IsEnvironment("Testing"))
        o.EnableResolveEndpoint = true;
});
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
builder.Services.AddScoped<IResolveAmbiguousScanUseCase, ResolveAmbiguousScanUseCase>();
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

// Collection domain (issues #15, #16, #46, #79)
builder.Services.AddHttpContextAccessor();
builder.Services.AddScoped<ICurrentUser, ClaimsCurrentUser>();
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddScoped<IAddToCollectionUseCase, AddToCollectionUseCase>();
builder.Services.AddScoped<ICollectionQueryUseCase, CollectionQueryUseCase>();
builder.Services.AddScoped<IUpdateCollectionUseCase, UpdateCollectionUseCase>();

var runtimeConnectionString = builder.Configuration.GetConnectionString("Postgres");
if (!string.IsNullOrWhiteSpace(runtimeConnectionString))
{
    builder.Services.AddSingleton(new PostgresConnectionFactory(runtimeConnectionString));
    builder.Services.AddScoped<ICollectionRepository, PostgresCollectionRepository>();
    builder.Services.AddScoped<IIdempotencyStore, PostgresIdempotencyStore>();
    builder.Services.AddScoped<IScanCacheInvalidationPort, PostgresScanCachePort>();
    builder.Services.AddScoped<IAmbiguousScanRepository, PostgresAmbiguousScanRepository>();

    var maintenanceConnectionString = builder.Configuration.GetConnectionString("PostgresAdmin");
    if (!string.IsNullOrWhiteSpace(maintenanceConnectionString))
    {
        builder.Services.AddSingleton<IScanCacheMaintenance>(
            new ScanCachePurger(maintenanceConnectionString));
        builder.Services.AddHostedService<ScanCachePurgeService>();
    }
}
else
{
    if (builder.Environment.IsDevelopment() || builder.Environment.IsEnvironment("Testing"))
        builder.Services.AddSingleton<IAmbiguousScanRepository, InMemoryAmbiguousScanRepository>();
    else
        builder.Services.AddSingleton<IAmbiguousScanRepository, UnconfiguredAmbiguousScanRepository>();

    // Development / contract-test wiring: no database required.
    builder.Services.AddSingleton<InMemoryCollectionStore>();
    builder.Services.AddScoped<ICollectionRepository, InMemoryCollectionRepository>();
    builder.Services.AddScoped<IIdempotencyStore, InMemoryIdempotencyStore>();
    builder.Services.AddSingleton<IScanCacheInvalidationPort, NoOpScanCacheInvalidation>();
}

// Validation
builder.Services.AddScoped<IValidator<ScanRequest>, ScanRequestValidator>();
builder.Services.AddSingleton<IPostgresReadinessProbe, NpgsqlPostgresReadinessProbe>();
builder.Services.AddHealthChecks()
    .AddCheck("self", () => Microsoft.Extensions.Diagnostics.HealthChecks.HealthCheckResult.Healthy(), ["live"])
    .AddCheck<PostgresReadinessHealthCheck>("postgres", tags: ["ready"]);

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
// Uses ConnectionStrings:PostgresAdmin (database owner / Azure admin) so the
// runner has DDL rights. The runtime application connection (ConnectionStrings:Postgres)
// will be a least-privilege login granted the deja_app role by IaC provisioning.
// An empty admin connection string skips migration — used by HTTP-only contract
// tests that exercise the API shape without a real database.
var adminConnectionString = app.Configuration.GetConnectionString("PostgresAdmin");
if (!string.IsNullOrWhiteSpace(adminConnectionString))
{
    var migrationLogger = app.Services
        .GetRequiredService<ILoggerFactory>()
        .CreateLogger<MigrationRunner>();
    await new MigrationRunner(adminConnectionString, migrationLogger).ApplyAsync();
}

app.UseMiddleware<RequestIdMiddleware>();
app.UseMiddleware<ExceptionHandlingMiddleware>();
app.UseStatusCodePages(async statusCodeContext =>
{
    var response = statusCodeContext.HttpContext.Response;
    if (response.HasStarted ||
        response.ContentLength is > 0 ||
        !string.IsNullOrWhiteSpace(response.ContentType))
    {
        return;
    }

    await ApiErrorResponseWriter.WriteAsync(
        statusCodeContext.HttpContext,
        ApiErrorCatalog.FromStatusCode(response.StatusCode));
});
app.UseAuthentication();
app.UseAuthorization();

app.MapHealthChecks("/health", new HealthCheckOptions
{
    AllowCachingResponses = false,
    ResultStatusCodes =
    {
        [Microsoft.Extensions.Diagnostics.HealthChecks.HealthStatus.Healthy] = StatusCodes.Status200OK,
        [Microsoft.Extensions.Diagnostics.HealthChecks.HealthStatus.Degraded] = StatusCodes.Status503ServiceUnavailable,
        [Microsoft.Extensions.Diagnostics.HealthChecks.HealthStatus.Unhealthy] = StatusCodes.Status503ServiceUnavailable
    },
    Predicate = registration => registration.Tags.Contains("ready"),
    ResponseWriter = HealthEndpointResponseWriter.WriteAsync
}).AllowAnonymous();
app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    AllowCachingResponses = false,
    Predicate = registration => registration.Tags.Contains("live"),
    ResponseWriter = HealthEndpointResponseWriter.WriteAsync
}).AllowAnonymous();
app.MapControllers();

app.Run();

// Expose Program for WebApplicationFactory in integration tests
public partial class Program { }
