using System.Net;

namespace DejaGroove.Infrastructure.Tests.Recognition;

/// <summary>
/// Test double for the HTTP boundary. Replays a queued sequence of responses
/// (so retry behaviour is exercisable) and records every request for contract
/// assertions. A response factory may throw to simulate transport faults.
/// </summary>
public sealed class StubHttpMessageHandler : HttpMessageHandler
{
    private readonly Queue<Func<HttpRequestMessage, HttpResponseMessage>> _responses = new();

    public List<HttpRequestMessage> Requests { get; } = [];
    public List<string> RequestBodies { get; } = [];

    public StubHttpMessageHandler EnqueueJson(string json, HttpStatusCode status = HttpStatusCode.OK)
    {
        _responses.Enqueue(_ => new HttpResponseMessage(status)
        {
            Content = new StringContent(json, System.Text.Encoding.UTF8, "application/json"),
        });
        return this;
    }

    public StubHttpMessageHandler EnqueueStatus(HttpStatusCode status)
    {
        _responses.Enqueue(_ => new HttpResponseMessage(status));
        return this;
    }

    public StubHttpMessageHandler EnqueueThrow(Exception ex)
    {
        _responses.Enqueue(_ => throw ex);
        return this;
    }

    protected override async Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request, CancellationToken cancellationToken)
    {
        Requests.Add(request);
        RequestBodies.Add(request.Content is null ? "" : await request.Content.ReadAsStringAsync(cancellationToken));

        if (_responses.Count == 0)
            throw new InvalidOperationException("StubHttpMessageHandler received an unexpected request.");

        return _responses.Dequeue()(request);
    }
}
