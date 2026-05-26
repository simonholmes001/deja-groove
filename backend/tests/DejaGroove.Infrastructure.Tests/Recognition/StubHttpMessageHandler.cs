using System.Net;

namespace DejaGroove.Infrastructure.Tests.Recognition;

/// <summary>
/// Test double for the HTTP boundary. Replays a queued sequence of responses
/// (so retry behaviour is exercisable) and records every request for contract
/// assertions. A response factory may throw to simulate transport faults or
/// delay to simulate a slow upstream (the delay honours cancellation, so the
/// resilience timeout can cut it short).
/// </summary>
public sealed class StubHttpMessageHandler : HttpMessageHandler
{
    private readonly Queue<Func<CancellationToken, Task<HttpResponseMessage>>> _responses = new();

    public List<HttpRequestMessage> Requests { get; } = [];
    public List<string> RequestBodies { get; } = [];

    public StubHttpMessageHandler EnqueueJson(string json, HttpStatusCode status = HttpStatusCode.OK)
        => Enqueue(_ => Task.FromResult(new HttpResponseMessage(status)
        {
            Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json"),
        }));

    public StubHttpMessageHandler EnqueueStatus(HttpStatusCode status)
        => Enqueue(_ => Task.FromResult(new HttpResponseMessage(status)));

    public StubHttpMessageHandler EnqueueThrow(Exception ex)
        => Enqueue(_ => throw ex);

    public StubHttpMessageHandler EnqueueDelay(TimeSpan delay)
        => Enqueue(async ct =>
        {
            await Task.Delay(delay, ct);
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("""{ "candidates": [] }""",
                    System.Text.Encoding.UTF8, "application/json"),
            };
        });

    public StubHttpMessageHandler EnqueueDelayedJson(TimeSpan delay, string json, HttpStatusCode status = HttpStatusCode.OK)
        => Enqueue(async ct =>
        {
            await Task.Delay(delay, ct);
            return new HttpResponseMessage(status)
            {
                Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json"),
            };
        });

    private StubHttpMessageHandler Enqueue(Func<CancellationToken, Task<HttpResponseMessage>> factory)
    {
        _responses.Enqueue(factory);
        return this;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        RequestBodies.Add(request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken));

        if (_responses.Count == 0)
            throw new InvalidOperationException("StubHttpMessageHandler received an unexpected request.");

        return await _responses.Dequeue()(cancellationToken);
    }
}
