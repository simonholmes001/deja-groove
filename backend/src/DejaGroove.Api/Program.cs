using DejaGroove.Api.Middleware;
using DejaGroove.Api.Requests;
using DejaGroove.Api.Validation;
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

// Application layer — stub replaced by real orchestration in #12
builder.Services.AddScoped<IScanWorkflowUseCase, StubScanWorkflowUseCase>();

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
