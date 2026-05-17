using DejaGroove.Api.Middleware;
using DejaGroove.Api.Ports;
using DejaGroove.Api.Requests;
using DejaGroove.Api.Validation;
using DejaGroove.Application.Ports;
using DejaGroove.Application.UseCases;
using FluentValidation;
using Microsoft.AspNetCore.Mvc;

var builder = WebApplication.CreateBuilder(args);

builder.Services.AddControllers();

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

app.MapControllers();

app.Run();

// Expose Program for WebApplicationFactory in integration tests
public partial class Program { }
