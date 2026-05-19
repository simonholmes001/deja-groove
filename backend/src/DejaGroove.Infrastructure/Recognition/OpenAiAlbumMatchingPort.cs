using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using DejaGroove.Application.Ports;
using DejaGroove.Domain.Scanning;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Polly;
using Polly.Retry;
using Polly.Timeout;

namespace DejaGroove.Infrastructure.Recognition;

/// <summary>
/// Issue #141: identifies an album cover via the OpenAI vision chat-completions
/// API. Sends the image inline (base64 data URL) with the pinned, versioned
/// recognition prompt (#38) and maps the model's ranked candidates to a
/// <see cref="ScanResult"/> via the confidence policy (#40).
/// </summary>
/// <remarks>
/// Resilience: a per-attempt timeout (bounded by the scan budget) wrapped by a
/// jittered exponential retry over transient faults only. Timeouts surface as
/// <see cref="TimeoutException"/> so <c>ScanWorkflowUseCase</c> treats them as
/// transient. Non-transient faults (4xx, unparseable model output) fail fast.
/// </remarks>
public sealed class OpenAiAlbumMatchingPort : IAlbumMatchingPort
{
    private readonly HttpClient _httpClient;
    private readonly OpenAiOptions _options;
    private readonly ILogger<OpenAiAlbumMatchingPort> _logger;
    private readonly ResiliencePipeline _pipeline;
    private readonly RecognitionPrompt _prompt;

    public OpenAiAlbumMatchingPort(
        HttpClient httpClient,
        IOptions<OpenAiOptions> options,
        ILogger<OpenAiAlbumMatchingPort> logger)
    {
        _httpClient = httpClient;
        _options = options.Value;
        _logger = logger;
        _prompt = RecognitionPromptRegistry.Get(_options.PromptVersion);
        _pipeline = BuildPipeline(_options, logger);
    }

    public async Task<ScanResult> IdentifyAsync(Stream imageStream, CancellationToken ct = default)
    {
        var base64Image = Convert.ToBase64String(await ReadAllBytesAsync(imageStream, ct));

        try
        {
            return await _pipeline.ExecuteAsync(
                async token => await CallModelAsync(base64Image, token),
                ct);
        }
        catch (TimeoutRejectedException ex)
        {
            throw new TimeoutException("OpenAI recognition timed out.", ex);
        }
        catch (TaskCanceledException ex) when (!ct.IsCancellationRequested)
        {
            throw new TimeoutException("OpenAI recognition timed out.", ex);
        }
    }

    private async Task<ScanResult> CallModelAsync(string base64Image, CancellationToken ct)
    {
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"{_options.BaseUrl.TrimEnd('/')}/chat/completions");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _options.ApiKey);
        request.Content = new StringContent(BuildRequestBody(base64Image), Encoding.UTF8, "application/json");

        using var response = await _httpClient.SendAsync(request, ct);

        if (IsTransientStatus(response.StatusCode))
            throw new TransientRecognitionException(
                $"OpenAI returned transient status {(int)response.StatusCode}.");

        if (!response.IsSuccessStatusCode)
            throw new OpenAiRecognitionException(
                $"OpenAI returned non-success status {(int)response.StatusCode}.");

        var payload = await response.Content.ReadAsStringAsync(ct);
        var candidates = ParseCandidates(payload);

        _logger.LogDebug(
            "OpenAI recognition returned {Count} candidate(s) using prompt {PromptVersion}.",
            candidates.Count, _prompt.Version);

        return RecognitionResultMapper.Map(candidates);
    }

    private string BuildRequestBody(string base64Image)
    {
        var payload = new
        {
            model = _options.Model,
            temperature = 0,
            response_format = new { type = "json_object" },
            messages = new object[]
            {
                new { role = "system", content = _prompt.Text },
                new
                {
                    role = "user",
                    content = new object[]
                    {
                        new { type = "text", text = "Identify the album from this cover image." },
                        new
                        {
                            type = "image_url",
                            image_url = new { url = $"data:image/jpeg;base64,{base64Image}" },
                        },
                    },
                },
            },
        };

        return JsonSerializer.Serialize(payload);
    }

    private static IReadOnlyList<RecognitionCandidate> ParseCandidates(string responsePayload)
    {
        string content;
        try
        {
            using var envelope = JsonDocument.Parse(responsePayload);
            content = envelope.RootElement
                .GetProperty("choices")[0]
                .GetProperty("message")
                .GetProperty("content")
                .GetString() ?? "";
        }
        catch (Exception ex) when (ex is JsonException or KeyNotFoundException or IndexOutOfRangeException or InvalidOperationException)
        {
            throw new OpenAiRecognitionException("OpenAI response envelope was not in the expected shape.", ex);
        }

        try
        {
            using var model = JsonDocument.Parse(content);
            if (!model.RootElement.TryGetProperty("candidates", out var array) ||
                array.ValueKind != JsonValueKind.Array)
                return [];

            var candidates = new List<RecognitionCandidate>();
            foreach (var element in array.EnumerateArray())
            {
                candidates.Add(new RecognitionCandidate(
                    Title: ReadString(element, "title"),
                    Artist: ReadString(element, "artist"),
                    Year: ReadNullableInt(element, "year"),
                    Confidence: ReadFloat(element, "confidence")));
            }

            return candidates;
        }
        catch (JsonException ex)
        {
            throw new OpenAiRecognitionException("OpenAI model output was not valid JSON.", ex);
        }
    }

    private static string? ReadString(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String
            ? value.GetString()
            : null;

    private static int? ReadNullableInt(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number
            ? value.GetInt32()
            : null;

    private static float ReadFloat(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number
            ? value.GetSingle()
            : 0f;

    private static bool IsTransientStatus(HttpStatusCode status) =>
        (int)status >= 500 ||
        status is HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests;

    private static async Task<byte[]> ReadAllBytesAsync(Stream stream, CancellationToken ct)
    {
        using var buffer = new MemoryStream();
        await stream.CopyToAsync(buffer, ct);
        return buffer.ToArray();
    }

    private static ResiliencePipeline BuildPipeline(OpenAiOptions options, ILogger logger) =>
        new ResiliencePipelineBuilder()
            .AddRetry(new RetryStrategyOptions
            {
                ShouldHandle = new PredicateBuilder()
                    .Handle<TransientRecognitionException>()
                    .Handle<HttpRequestException>()
                    .Handle<TimeoutRejectedException>()
                    .Handle<TaskCanceledException>(),
                MaxRetryAttempts = options.MaxRetryAttempts,
                Delay = TimeSpan.FromMilliseconds(200),
                BackoffType = DelayBackoffType.Exponential,
                UseJitter = true,
                OnRetry = args =>
                {
                    logger.LogWarning(
                        args.Outcome.Exception,
                        "OpenAI recognition transient failure; retrying (attempt {Attempt}).",
                        args.AttemptNumber + 1);
                    return ValueTask.CompletedTask;
                },
            })
            .AddTimeout(new TimeoutStrategyOptions
            {
                Timeout = TimeSpan.FromSeconds(options.TimeoutSeconds),
            })
            .Build();
}
