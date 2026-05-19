using System.Net;
using System.Text;
using DejaGroove.Domain.Scanning;
using DejaGroove.Infrastructure.Recognition;
using Microsoft.Extensions.Logging.Abstractions;
using Microsoft.Extensions.Options;

namespace DejaGroove.Infrastructure.Tests.Recognition;

/// <summary>
/// Issue #141: the OpenAI vision adapter. Exercised against a stub HTTP handler
/// so request contract, response mapping, retry and fault translation are
/// deterministic and offline.
/// </summary>
public sealed class OpenAiAlbumMatchingPortTests
{
    private static OpenAiOptions Options(int retries = 1, int timeoutSeconds = 5) => new()
    {
        ApiKey = "sk-test-123",
        Model = "gpt-5.4-mini",
        BaseUrl = "https://api.openai.test/v1",
        TimeoutSeconds = timeoutSeconds,
        MaxRetryAttempts = retries,
        PromptVersion = RecognitionPromptRegistry.CurrentVersion,
    };

    private static OpenAiAlbumMatchingPort Port(StubHttpMessageHandler handler, OpenAiOptions? options = null)
    {
        var client = new HttpClient(handler);
        return new OpenAiAlbumMatchingPort(
            client,
            new OptionsWrapper<OpenAiOptions>(options ?? Options()),
            NullLogger<OpenAiAlbumMatchingPort>.Instance);
    }

    private static string ChatResponse(string modelJson)
    {
        var escaped = System.Text.Json.JsonSerializer.Serialize(modelJson);
        return $$"""{ "choices": [ { "message": { "content": {{escaped}} } } ] }""";
    }

    private static MemoryStream Image() => new(Encoding.UTF8.GetBytes("fake-jpeg-bytes"));

    [Fact]
    public async Task ConfidentSingleMatch_ReturnsSafeToBuy()
    {
        var handler = new StubHttpMessageHandler().EnqueueJson(ChatResponse(
            """{ "candidates": [ { "title": "Remain in Light", "artist": "Talking Heads", "year": 1980, "confidence": 0.94 } ] }"""));

        var result = await Port(handler).IdentifyAsync(Image());

        Assert.Equal(ScanStatus.SafeToBuy, result.Status);
        Assert.Equal("Remain in Light", result.AlbumIdentity!.Title);
        Assert.Equal("Talking Heads", result.AlbumIdentity.Artist);
    }

    [Fact]
    public async Task MultipleCloseCandidates_ReturnsAmbiguous()
    {
        var handler = new StubHttpMessageHandler().EnqueueJson(ChatResponse(
            """{ "candidates": [ { "title": "Greatest Hits", "artist": "Queen", "year": 1981, "confidence": 0.61 }, { "title": "Greatest Hits II", "artist": "Queen", "year": 1991, "confidence": 0.57 } ] }"""));

        var result = await Port(handler).IdentifyAsync(Image());

        Assert.Equal(ScanStatus.Ambiguous, result.Status);
        Assert.Equal(2, result.Candidates.Count);
    }

    [Fact]
    public async Task EmptyCandidates_ReturnsNoMatch()
    {
        var handler = new StubHttpMessageHandler().EnqueueJson(ChatResponse("""{ "candidates": [] }"""));

        var result = await Port(handler).IdentifyAsync(Image());

        Assert.Equal(ScanStatus.NoMatch, result.Status);
    }

    [Fact]
    public async Task Request_CarriesAuthModelPromptAndBase64Image()
    {
        var handler = new StubHttpMessageHandler().EnqueueJson(ChatResponse("""{ "candidates": [] }"""));

        await Port(handler).IdentifyAsync(Image());

        var request = handler.Requests.Single();
        Assert.Equal(HttpMethod.Post, request.Method);
        Assert.Equal("https://api.openai.test/v1/chat/completions", request.RequestUri!.ToString());
        Assert.Equal("Bearer", request.Headers.Authorization!.Scheme);
        Assert.Equal("sk-test-123", request.Headers.Authorization.Parameter);

        var body = handler.RequestBodies.Single();
        Assert.Contains("gpt-5.4-mini", body);
        Assert.Contains(Convert.ToBase64String(Encoding.UTF8.GetBytes("fake-jpeg-bytes")), body);
        Assert.Contains("STRICT JSON", body); // prompt text from the pinned registry version
    }

    [Fact]
    public async Task TransientServerError_IsRetriedThenSucceeds()
    {
        var handler = new StubHttpMessageHandler()
            .EnqueueStatus(HttpStatusCode.InternalServerError)
            .EnqueueJson(ChatResponse(
                """{ "candidates": [ { "title": "Blue", "artist": "Joni Mitchell", "year": 1971, "confidence": 0.96 } ] }"""));

        var result = await Port(handler, Options(retries: 2)).IdentifyAsync(Image());

        Assert.Equal(ScanStatus.SafeToBuy, result.Status);
        Assert.Equal(2, handler.Requests.Count);
    }

    [Fact]
    public async Task PersistentServerError_ThrowsAfterRetriesExhausted()
    {
        var handler = new StubHttpMessageHandler()
            .EnqueueStatus(HttpStatusCode.BadGateway)
            .EnqueueStatus(HttpStatusCode.BadGateway);

        await Assert.ThrowsAnyAsync<Exception>(() => Port(handler, Options(retries: 1)).IdentifyAsync(Image()));
    }

    [Fact]
    public async Task ClientError_IsNotRetried()
    {
        var handler = new StubHttpMessageHandler().EnqueueStatus(HttpStatusCode.Unauthorized);

        await Assert.ThrowsAnyAsync<Exception>(() => Port(handler, Options(retries: 3)).IdentifyAsync(Image()));

        Assert.Single(handler.Requests); // 401 must not burn retry budget
    }

    [Fact]
    public async Task MalformedModelJson_ThrowsRecognitionException()
    {
        var handler = new StubHttpMessageHandler().EnqueueJson(ChatResponse("not-json-at-all"));

        await Assert.ThrowsAsync<OpenAiRecognitionException>(() => Port(handler).IdentifyAsync(Image()));
    }

    [Fact]
    public async Task TransportTimeout_IsTranslatedToTimeoutException()
    {
        // Surfaced as TimeoutException so ScanWorkflowUseCase treats it as transient.
        var handler = new StubHttpMessageHandler()
            .EnqueueThrow(new TaskCanceledException("timed out"))
            .EnqueueThrow(new TaskCanceledException("timed out"));

        await Assert.ThrowsAsync<TimeoutException>(() => Port(handler, Options(retries: 1)).IdentifyAsync(Image()));
    }
}
