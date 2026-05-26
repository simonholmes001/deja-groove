using System.Diagnostics;
using System.Net;
using System.Text;
using DejaGroove.Application.Exceptions;
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
        Model = "gpt-5.4",
        BaseUrl = "https://api.openai.test/v1",
        TimeoutSeconds = timeoutSeconds,
        MaxRetryAttempts = retries,
        MaxConcurrentRequests = 8,
        CircuitBreakerFailureThresholdPercent = 50,
        CircuitBreakerMinimumThroughput = 4,
        CircuitBreakerSamplingSeconds = 30,
        CircuitBreakerBreakSeconds = 20,
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
        Assert.Contains("gpt-5.4", body);
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
    public async Task PersistentServerError_ThrowsServiceUnavailable_AfterRetriesExhausted()
    {
        var handler = new StubHttpMessageHandler()
            .EnqueueStatus(HttpStatusCode.BadGateway)
            .EnqueueStatus(HttpStatusCode.BadGateway);

        // Controlled 503-mapping exception, not a leaked infrastructure type.
        await Assert.ThrowsAsync<ServiceUnavailableException>(
            () => Port(handler, Options(retries: 1)).IdentifyAsync(Image()));
        Assert.Equal(2, handler.Requests.Count);
    }

    [Fact]
    public async Task PersistentTransportFailure_ThrowsServiceUnavailable()
    {
        var handler = new StubHttpMessageHandler()
            .EnqueueThrow(new HttpRequestException("connection reset"))
            .EnqueueThrow(new HttpRequestException("connection reset"));

        await Assert.ThrowsAsync<ServiceUnavailableException>(
            () => Port(handler, Options(retries: 1)).IdentifyAsync(Image()));
    }

    [Fact]
    public async Task ClientError_IsNotRetried_AndThrowsRecognitionException()
    {
        var handler = new StubHttpMessageHandler().EnqueueStatus(HttpStatusCode.Unauthorized);

        await Assert.ThrowsAsync<OpenAiRecognitionException>(
            () => Port(handler, Options(retries: 3)).IdentifyAsync(Image()));

        Assert.Single(handler.Requests); // 401 must not burn retry budget
    }

    [Fact]
    public async Task CallerCancellation_PropagatesWithoutRetryOrTimeoutMapping()
    {
        // The caller's own cancellation is not a transient fault and is not a
        // timeout: it must propagate as OperationCanceledException without
        // burning the retry budget and without being mapped to TimeoutException
        // (which would trigger ScanWorkflowUseCase's transient retry).
        var handler = new StubHttpMessageHandler().EnqueueDelay(TimeSpan.FromSeconds(30));
        using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));

        var thrown = await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => Port(handler, Options(retries: 2, timeoutSeconds: 10)).IdentifyAsync(Image(), cts.Token));

        Assert.IsNotType<TimeoutException>(thrown);
        Assert.Single(handler.Requests);
    }

    [Fact]
    public async Task PollyTimeout_IsTranslatedToTimeoutException()
    {
        // Per-attempt timeout fires (Polly AddTimeout → TimeoutRejectedException);
        // the adapter must surface TimeoutException so ScanWorkflowUseCase
        // treats it as transient. Must NOT block for the full upstream delay.
        var handler = new StubHttpMessageHandler().EnqueueDelay(TimeSpan.FromSeconds(30));
        var sw = Stopwatch.StartNew();

        await Assert.ThrowsAsync<TimeoutException>(
            () => Port(handler, Options(retries: 0, timeoutSeconds: 1)).IdentifyAsync(Image()));

        Assert.True(sw.Elapsed < TimeSpan.FromSeconds(10), $"timed out too slowly: {sw.Elapsed}");
    }

    [Fact]
    public async Task ResponseExceedingSizeCap_ThrowsRecognitionException_AndIsNotRetried()
    {
        // A *valid* but oversized response: without the cap this parses
        // cleanly to SafeToBuy, so the test only passes once the read is
        // bounded and rejected.
        var padding = new string('a', 2 * 1024 * 1024);
        var handler = new StubHttpMessageHandler().EnqueueJson(ChatResponse(
            $$"""{ "candidates": [ { "title": "Big", "artist": "A", "year": 2000, "confidence": 0.95, "note": "{{padding}}" } ] }"""));

        await Assert.ThrowsAsync<OpenAiRecognitionException>(
            () => Port(handler, Options(retries: 3)).IdentifyAsync(Image()));
        Assert.Single(handler.Requests);
    }

    [Fact]
    public async Task DeeplyNestedModelJson_ThrowsRecognitionException()
    {
        var nested = string.Concat(Enumerable.Repeat("[", 200)) + string.Concat(Enumerable.Repeat("]", 200));
        var handler = new StubHttpMessageHandler().EnqueueJson(ChatResponse(nested));

        await Assert.ThrowsAsync<OpenAiRecognitionException>(
            () => Port(handler).IdentifyAsync(Image()));
    }

    [Fact]
    public async Task ExcessiveCandidates_AreBounded_AndTopStillResolves()
    {
        var many = string.Join(",", Enumerable.Range(0, 500)
            .Select(i => $$"""{ "title": "T{{i}}", "artist": "A", "year": 2000, "confidence": 0.10 }"""));
        var handler = new StubHttpMessageHandler().EnqueueJson(ChatResponse(
            $$"""{ "candidates": [ { "title": "Winner", "artist": "A", "year": 1990, "confidence": 0.97 }, {{many}} ] }"""));

        var result = await Port(handler).IdentifyAsync(Image());

        Assert.Equal(ScanStatus.SafeToBuy, result.Status);
        Assert.Equal("Winner", result.AlbumIdentity!.Title);
    }

    [Fact]
    public async Task MalformedModelJson_ThrowsRecognitionException()
    {
        var handler = new StubHttpMessageHandler().EnqueueJson(ChatResponse("not-json-at-all"));

        await Assert.ThrowsAsync<OpenAiRecognitionException>(() => Port(handler).IdentifyAsync(Image()));
    }

    [Fact]
    public async Task TransportTimeout_IsTranslatedToTimeoutException_WithoutRetry()
    {
        // A raw TaskCanceledException from the transport (e.g. the HttpClient
        // backstop timeout firing — not caller cancellation, not Polly's own
        // timeout strategy) is mapped to TimeoutException so ScanWorkflowUseCase
        // treats it as transient. It is NOT retried at this layer — Polly only
        // retries provider-side transients (5xx) and its own timeout, not raw
        // cancellation.
        var handler = new StubHttpMessageHandler()
            .EnqueueThrow(new TaskCanceledException("timed out"));

        await Assert.ThrowsAsync<TimeoutException>(
            () => Port(handler, Options(retries: 1)).IdentifyAsync(Image()));
        Assert.Single(handler.Requests);
    }

    [Fact]
    public async Task CircuitBreaker_OpensAfterThreshold_AndShortCircuitsSubsequentCalls()
    {
        var handler = new StubHttpMessageHandler()
            .EnqueueStatus(HttpStatusCode.BadGateway)
            .EnqueueStatus(HttpStatusCode.BadGateway);

        var options = Options(retries: 0) with
        {
            CircuitBreakerMinimumThroughput = 2,
            CircuitBreakerFailureThresholdPercent = 50,
            CircuitBreakerSamplingSeconds = 30,
            CircuitBreakerBreakSeconds = 30,
        };
        var port = Port(handler, options);

        await Assert.ThrowsAsync<ServiceUnavailableException>(() => port.IdentifyAsync(Image()));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => port.IdentifyAsync(Image()));
        await Assert.ThrowsAsync<ServiceUnavailableException>(() => port.IdentifyAsync(Image()));

        Assert.Equal(2, handler.Requests.Count);
    }

    [Fact]
    public async Task ConcurrencyLimiter_RejectsSecondConcurrentCall_AsServiceUnavailable()
    {
        var handler = new StubHttpMessageHandler()
            .EnqueueDelayedJson(TimeSpan.FromMilliseconds(400), ChatResponse("""{ "candidates": [] }"""))
            .EnqueueJson(ChatResponse("""{ "candidates": [] }"""));

        var options = Options(retries: 0) with { MaxConcurrentRequests = 1 };
        var port = Port(handler, options);

        var first = port.IdentifyAsync(Image());
        await Task.Delay(50);
        var second = port.IdentifyAsync(Image());

        var secondEx = await Assert.ThrowsAsync<ServiceUnavailableException>(async () => await second);
        var firstResult = await first;

        Assert.Equal("scan_provider_unavailable", secondEx.Code);
        Assert.Equal(ScanStatus.NoMatch, firstResult.Status);
    }
}
