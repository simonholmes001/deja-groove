---
"deja-groove": minor
---

Add the production OpenAI vision album-matching adapter (#141): `OpenAiAlbumMatchingPort` calls the chat-completions vision endpoint with an inline base64 image, parses ranked candidates, and maps them to `ScanResult` via a pure confidence policy (#40, `RecognitionResultMapper`) keyed on `ConfidenceThreshold.Minimum`. Recognition prompts are now versioned via a pinned, rollback-able `RecognitionPromptRegistry` (#38). Resilience: per-attempt Polly timeout + jittered exponential retry over provider-side transients only, with caller cancellation propagating unchanged, exhausted transient/transport failures mapped to `ServiceUnavailableException` (controlled API 503), and an `HttpClient.Timeout` backstop. The API key is sourced from the `OPENAI_KEY` environment variable; default model `gpt-5.4`. Wired in `Program.cs` behind config presence; falls back to `UnconfiguredAlbumMatchingPort` when unset.
