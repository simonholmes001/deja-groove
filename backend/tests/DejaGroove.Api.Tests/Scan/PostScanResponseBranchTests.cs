using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using DejaGroove.Api.Responses;
using DejaGroove.Application.Commands;
using DejaGroove.Application.UseCases;
using DejaGroove.Domain.Scanning;
using DejaGroove.Domain.Shared;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;

namespace DejaGroove.Api.Tests.Scan;

public sealed class PostScanResponseBranchTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly WebApplicationFactory<Program> _factory;

    private static readonly byte[] ValidJpegBytes = [
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
        0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9
    ];

    public PostScanResponseBranchTests(WebApplicationFactory<Program> factory)
    {
        _factory = factory;
    }

    [Fact]
    public async Task PostScan_WhenUseCaseReturnsNoMatch_MapsNullAlbumAndEmptyCandidates()
    {
        var client = CreateClientReturning(ScanResult.NoMatch());
        var response = await client.PostAsync("/v1/scan", BuildValidRequest());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await DeserializeAsync<ScanResponse>(response);
        Assert.Equal("no_match", body.Status);
        Assert.Null(body.Album);
        Assert.Empty(body.Candidates);
    }

    [Fact]
    public async Task PostScan_WhenUseCaseReturnsAmbiguous_MapsCandidates()
    {
        var c1 = AlbumIdentity.Create("mbid-1", null, "A", "ArtistA", 2001);
        var c2 = AlbumIdentity.Create("mbid-2", null, "B", "ArtistB", 2002);
        var client = CreateClientReturning(ScanResult.Ambiguous([c1, c2], 0.61f));

        var response = await client.PostAsync("/v1/scan", BuildValidRequest());

        Assert.Equal(HttpStatusCode.OK, response.StatusCode);
        var body = await DeserializeAsync<ScanResponse>(response);
        Assert.Equal("ambiguous", body.Status);
        Assert.Null(body.Album);
        Assert.Equal(2, body.Candidates.Count);
        Assert.Equal("mbid-1", body.Candidates[0].Mbid);
        Assert.Equal("mbid-2", body.Candidates[1].Mbid);
    }

    private HttpClient CreateClientReturning(ScanResult result)
    {
        var useCase = new FixedScanWorkflowUseCase(result);
        var factory = _factory.WithWebHostBuilder(builder =>
        {
            builder.ConfigureServices(services =>
            {
                services.RemoveAll<IScanWorkflowUseCase>();
                services.AddSingleton<IScanWorkflowUseCase>(useCase);
            });
        });

        return factory.CreateClient();
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

    private sealed class FixedScanWorkflowUseCase(ScanResult result) : IScanWorkflowUseCase
    {
        public Task<ScanResult> ExecuteAsync(ScanCommand command, CancellationToken ct = default) => Task.FromResult(result);
    }
}
