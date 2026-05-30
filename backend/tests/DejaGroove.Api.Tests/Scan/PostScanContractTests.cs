using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using DejaGroove.Api.Ports;
using DejaGroove.Api.Responses;
using DejaGroove.Application.Ports;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Xunit;

namespace DejaGroove.Api.Tests.Scan;

public class PostScanContractTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    // Minimal 1×1 JPEG bytes (valid JPEG magic bytes FF D8 FF)
    private static readonly byte[] ValidJpegBytes = [
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9
    ];

    public PostScanContractTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<IAlbumMatchingPort>();
                services.AddSingleton<IAlbumMatchingPort, StubAlbumMatchingPort>();
            });
        }).CreateClient();
    }

    private static MultipartFormDataContent BuildValidRequest(
        byte[]? imageBytes = null,
        string? contentType = "image/jpeg",
        string? clientScanId = null,
        string? capturedAt = null)
    {
        var form = new MultipartFormDataContent();

        var imageContent = new ByteArrayContent(imageBytes ?? ValidJpegBytes);
        if (contentType != null)
            imageContent.Headers.ContentType = new MediaTypeHeaderValue(contentType);
        form.Add(imageContent, "image", "cover.jpg");

        form.Add(new StringContent(clientScanId ?? Guid.NewGuid().ToString()), "clientScanId");

        if (capturedAt != null)
            form.Add(new StringContent(capturedAt), "capturedAt");

        return form;
    }

    private static async Task<T> DeserializeAsync<T>(HttpResponseMessage response)
    {
        var json = await response.Content.ReadAsStringAsync();
        return JsonSerializer.Deserialize<T>(json)!;
    }

    // ── Happy path ────────────────────────────────────────────────────────────

    [Fact]
    public async Task ValidRequest_Returns200WithScanResponse()
    {
        var response = await _client.PostAsync("/v1/scan", BuildValidRequest());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await DeserializeAsync<ScanResponse>(response);
        Assert.NotEqual(Guid.Empty, body.RequestId);
        Assert.Equal("safe_to_buy", body.Status);
    }

    [Fact]
    public async Task ValidRequest_ResponseContainsRequestId()
    {
        var response = await _client.PostAsync("/v1/scan", BuildValidRequest());
        var body = await DeserializeAsync<ScanResponse>(response);
        Assert.NotEqual(Guid.Empty, body.RequestId);
    }

    [Fact]
    public async Task ValidRequest_RequestIdHeaderPresent()
    {
        var response = await _client.PostAsync("/v1/scan", BuildValidRequest());
        Assert.True(response.Headers.Contains("X-Request-Id"));
    }

    // ── Validation errors ─────────────────────────────────────────────────────

    [Fact]
    public async Task MissingImage_Returns400()
    {
        var form = new MultipartFormDataContent();
        form.Add(new StringContent(Guid.NewGuid().ToString()), "clientScanId");

        var response = await _client.PostAsync("/v1/scan", form);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var body = await DeserializeAsync<ErrorResponse>(response);
        Assert.Equal("validation_error", body.Error.Code);
        Assert.NotEqual(Guid.Empty, body.Error.RequestId);
        Assert.False(body.Error.Retryable);
    }

    [Fact]
    public async Task MissingClientScanId_Returns400()
    {
        var form = new MultipartFormDataContent();
        var imageContent = new ByteArrayContent(ValidJpegBytes);
        imageContent.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
        form.Add(imageContent, "image", "cover.jpg");

        var response = await _client.PostAsync("/v1/scan", form);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var body = await DeserializeAsync<ErrorResponse>(response);
        Assert.Equal("validation_error", body.Error.Code);
        Assert.NotEqual(Guid.Empty, body.Error.RequestId);
    }

    [Fact]
    public async Task InvalidClientScanId_NotAUuid_Returns400()
    {
        var response = await _client.PostAsync("/v1/scan",
            BuildValidRequest(clientScanId: "not-a-uuid"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var body = await DeserializeAsync<ErrorResponse>(response);
        Assert.Equal("validation_error", body.Error.Code);
    }

    [Fact]
    public async Task NonJpegContentType_Returns400()
    {
        var response = await _client.PostAsync("/v1/scan",
            BuildValidRequest(contentType: "image/png"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var body = await DeserializeAsync<ErrorResponse>(response);
        Assert.Equal("validation_error", body.Error.Code);
    }

    [Fact]
    public async Task JpegContentTypeMislabelledNonJpegBytes_Returns400()
    {
        // PNG magic bytes labelled as image/jpeg — should fail content inspection
        byte[] pngBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

        var response = await _client.PostAsync("/v1/scan",
            BuildValidRequest(imageBytes: pngBytes, contentType: "image/jpeg"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var body = await DeserializeAsync<ErrorResponse>(response);
        Assert.Equal("validation_error", body.Error.Code);
    }

    [Fact]
    public async Task InvalidCapturedAt_NotIso8601_Returns400()
    {
        var response = await _client.PostAsync("/v1/scan",
            BuildValidRequest(capturedAt: "not-a-date"));

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        var body = await DeserializeAsync<ErrorResponse>(response);
        Assert.Equal("validation_error", body.Error.Code);
    }

    [Fact]
    public async Task ValidCapturedAt_Iso8601_Returns200()
    {
        var response = await _client.PostAsync("/v1/scan",
            BuildValidRequest(capturedAt: "2026-05-13T07:00:00Z"));

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
    }

    // ── Payload size ──────────────────────────────────────────────────────────

    [Fact]
    public async Task OversizedPayload_Returns413()
    {
        var oversized = new byte[11 * 1024 * 1024]; // 11 MB
        oversized[0] = 0xFF; oversized[1] = 0xD8; // JPEG magic

        var response = await _client.PostAsync("/v1/scan",
            BuildValidRequest(imageBytes: oversized));

        Assert.Equal(HttpStatusCode.RequestEntityTooLarge, response.StatusCode);
        var body = await DeserializeAsync<ErrorResponse>(response);
        Assert.Equal("image_too_large", body.Error.Code);
        Assert.False(body.Error.Retryable);
        Assert.NotEqual(Guid.Empty, body.Error.RequestId);
    }

    // ── Error envelope on all failure codes ──────────────────────────────────

    [Fact]
    public async Task AllErrorResponses_ContainRequestId()
    {
        var form = new MultipartFormDataContent();
        form.Add(new StringContent(Guid.NewGuid().ToString()), "clientScanId");

        var response = await _client.PostAsync("/v1/scan", form);
        var body = await DeserializeAsync<ErrorResponse>(response);

        Assert.NotEqual(Guid.Empty, body.Error.RequestId);
    }

    [Fact]
    public async Task ErrorResponses_UseIncomingCorrelationIdAsRequestId()
    {
        var correlationId = Guid.NewGuid();
        var form = new MultipartFormDataContent();
        form.Add(new StringContent(Guid.NewGuid().ToString()), "clientScanId");

        using var request = new HttpRequestMessage(HttpMethod.Post, "/v1/scan")
        {
            Content = form
        };
        request.Headers.Add("X-Correlation-Id", correlationId.ToString());

        var response = await _client.SendAsync(request);
        var body = await DeserializeAsync<ErrorResponse>(response);

        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        Assert.Equal(correlationId, body.Error.RequestId);
    }
}

public sealed class PostScanProviderConfigurationTests
{
    // Minimal 1×1 JPEG bytes (valid JPEG magic bytes FF D8 FF)
    private static readonly byte[] ValidJpegBytes = [
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9
    ];

    [Fact]
    public async Task ValidRequest_WithoutOpenAiKey_Returns503ConfigurationError()
    {
        using var factory = new WebApplicationFactory<Program>();
        using var client = factory.CreateClient();

        var response = await client.PostAsync("/v1/scan", BuildValidRequest());

        Assert.Equal(HttpStatusCode.ServiceUnavailable, response.StatusCode);
        var body = await DeserializeAsync<ErrorResponse>(response);
        Assert.Equal("scan_dependencies_unconfigured", body.Error.Code);
        Assert.True(body.Error.Retryable);
    }

    private static MultipartFormDataContent BuildValidRequest()
    {
        var form = new MultipartFormDataContent();
        var imageContent = new ByteArrayContent(ValidJpegBytes);
        imageContent.Headers.ContentType = new MediaTypeHeaderValue("image/jpeg");
        form.Add(imageContent, "image", "cover.jpg");
        form.Add(new StringContent(Guid.NewGuid().ToString()), "clientScanId");
        return form;
    }

    private static async Task<T> DeserializeAsync<T>(HttpResponseMessage response)
    {
        var json = await response.Content.ReadAsStringAsync();
        return JsonSerializer.Deserialize<T>(json)!;
    }
}
