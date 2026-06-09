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
using DejaGroove.Infrastructure.Recognition;
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
var isTesting = builder.Environment.IsEnvironment("Testing");
var configuredScanFeatures = builder.Configuration
    .GetSection(ScanFeaturesOptions.SectionName)
    .Get<ScanFeaturesOptions>() ?? new ScanFeaturesOptions();
var effectiveScanFeatures = new ScanFeaturesOptions
{
    UseStubScanRuntime = isTesting || configuredScanFeatures.UseStubScanRuntime,
    EnableResolveEndpoint = isTesting || configuredScanFeatures.EnableResolveEndpoint
};
if (!isTesting && effectiveScanFeatures.UseStubScanRuntime)
{
    throw new InvalidOperationException(
        "Stub scan runtime is only allowed in the Testing environment. Deploy real scan infrastructure instead of setting ScanFeatures__UseStubScanRuntime=true.");
}
builder.Services.AddSingleton<IOptions<ScanFeaturesOptions>>(Options.Create(effectiveScanFeatures));
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

var openAiKey = builder.Configuration["OPENAI_KEY"];
var hasOpenAiKey = !string.IsNullOrWhiteSpace(openAiKey);
if (effectiveScanFeatures.UseStubScanRuntime)
{
    builder.Services.AddSingleton<IImageValidationPort, StubImageValidationPort>();
    builder.Services.AddSingleton<IPerceptualHashPort, StubPerceptualHashPort>();
}
else
{
    builder.Services.AddSingleton<IImageValidationPort, ImageHeaderValidationPort>();
    builder.Services.AddSingleton<IPerceptualHashPort, Sha256PerceptualHashPort>();
}

if (hasOpenAiKey)
{
    builder.Services.AddSingleton<IValidateOptions<OpenAiOptions>, ValidateOpenAiOptions>();
    builder.Services.AddOptions<OpenAiOptions>()
        .Bind(builder.Configuration.GetSection(OpenAiOptions.SectionName))
        .Configure(o => o.ApiKey = openAiKey!)
        .ValidateOnStart();
    builder.Services.AddHttpClient<IAlbumMatchingPort, OpenAiAlbumMatchingPort>(client =>
        {
            client.Timeout = TimeSpan.FromSeconds(30);
        })
        .SetHandlerLifetime(TimeSpan.FromMinutes(5));
}
else
{
    builder.Services.AddSingleton<IAlbumMatchingPort, UnconfiguredAlbumMatchingPort>();
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
    builder.Services.AddScoped<IScanCachePort, PostgresScanCachePort>();
    builder.Services.AddScoped<IScanCacheInvalidationPort, PostgresScanCachePort>();
    builder.Services.AddScoped<IAmbiguousScanRepository, PostgresAmbiguousScanRepository>();
    builder.Services.AddScoped<ICollectionOwnershipPort, PostgresCollectionOwnershipPort>();
    builder.Services.AddScoped<IScanEventRepository, PostgresScanEventRepository>();

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
    if (effectiveScanFeatures.UseStubScanRuntime)
    {
        builder.Services.AddSingleton<IScanCachePort, InMemoryScanCachePort>();
        builder.Services.AddSingleton<IAmbiguousScanRepository, InMemoryAmbiguousScanRepository>();
        builder.Services.AddSingleton<ICollectionOwnershipPort, StubCollectionOwnershipPort>();
        builder.Services.AddSingleton<IScanEventRepository, InMemoryScanEventRepository>();
    }
    else
    {
        builder.Services.AddSingleton<IScanCachePort, UnconfiguredScanCachePort>();
        builder.Services.AddSingleton<IAmbiguousScanRepository, UnconfiguredAmbiguousScanRepository>();
        builder.Services.AddSingleton<ICollectionOwnershipPort, UnconfiguredCollectionOwnershipPort>();
        builder.Services.AddSingleton<IScanEventRepository, UnconfiguredScanEventRepository>();
    }

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
// Uses ConnectionStrings:PostgresAdmin so the runner has DDL rights. In the
// current Azure deployment, ConnectionStrings:Postgres and :PostgresAdmin are
// both wired to the same PostgreSQL login; migrations grant that login
// membership in deja_app so runtime requests can SET LOCAL ROLE deja_app.
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

if (hasOpenAiKey && !isTesting)
{
    using var scope = app.Services.CreateScope();
    var services = scope.ServiceProvider;
    if (services.GetRequiredService<IScanCachePort>() is UnconfiguredScanCachePort ||
        services.GetRequiredService<ICollectionOwnershipPort>() is UnconfiguredCollectionOwnershipPort ||
        services.GetRequiredService<IScanEventRepository>() is UnconfiguredScanEventRepository ||
        services.GetRequiredService<IAmbiguousScanRepository>() is UnconfiguredAmbiguousScanRepository)
    {
        throw new InvalidOperationException(
            "OPENAI_KEY is configured but PostgreSQL-backed scan cache, scan events, ownership, or ambiguity persistence is not wired for the deployed environment.");
    }
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
