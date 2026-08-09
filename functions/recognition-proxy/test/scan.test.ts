import assert from "node:assert/strict";
import test from "node:test";
import { createScanHandler, toScanResponse } from "../src/scan.js";
import type { HttpRequest, InvocationContext } from "@azure/functions";
import type { Album, RecognitionResult } from "../src/contracts.js";

test("toScanResponse returns one album for strong matches", () => {
  const response = toScanResponse({
    status: "safe_to_buy",
    confidence: 1.2,
    album: {
      mbid: null,
      discogs_release_id: null,
      title: "Kind of Blue",
      artist: "Miles Davis",
      year: 1959,
      first_release_year: 1959,
      release_year: 1959,
      format: "LP",
      label: null,
      catalog_number: null,
      country: null,
      back_cover_text: null,
      release_notes: null
    },
    candidates: []
  }, "00000000-0000-4000-8000-000000000001");

  assert.equal(response.status, "safe_to_buy");
  assert.equal(response.confidence, 1);
  assert.equal(response.album?.artist, "Miles Davis");
  assert.deepEqual(response.candidates, []);
});

test("toScanResponse returns candidates for ambiguous matches", () => {
  const response = toScanResponse({
    status: "ambiguous",
    confidence: -0.2,
    album: null,
    candidates: [
      {
        mbid: null,
        discogs_release_id: null,
        title: "Unknown Pleasures",
        artist: "Joy Division",
        year: 1979,
        first_release_year: 1979,
        release_year: 1979,
        format: "LP",
        label: null,
        catalog_number: null,
        country: null,
        back_cover_text: null,
        release_notes: null
      }
    ]
  }, "00000000-0000-4000-8000-000000000002");

  assert.equal(response.status, "ambiguous");
  assert.equal(response.confidence, 0);
  assert.equal(response.album, null);
  assert.equal(response.candidates.length, 1);
});

test("scan handler returns recognition-only result when enrichment times out", async () => {
  const warnings: unknown[] = [];
  const handler = createScanHandler(
    new StubRecognition(baseResult()),
    {
      enrich: async () => await new Promise<Album>(() => {})
    },
    { enrichmentTimeoutMs: 1, includeTimings: true });

  const response = await handler(fakeMultipartRequest(), fakeContext(warnings));

  assert.equal(response.status, 200);
  assert.equal(response.jsonBody?.album?.label, null);
  assert.equal(response.jsonBody?.timings?.image_bytes, 3);
  assert.equal(response.jsonBody?.timings?.enrichment_timed_out, true);
  assert.equal(typeof response.jsonBody?.timings?.total_ms, "number");
  assert.match(String(warnings[0]), /enrichment exceeded 1ms/);
});

test("scan handler aborts enrichment provider work when enrichment times out", async () => {
  let abortObserved = false;
  const handler = createScanHandler(
    new StubRecognition(baseResult()),
    {
      enrich: async (_album, options) => await new Promise<Album>((_resolve, reject) => {
        options?.signal?.addEventListener("abort", () => {
          abortObserved = true;
          reject(options.signal?.reason ?? new Error("aborted"));
        });
      })
    },
    { enrichmentTimeoutMs: 1, includeTimings: true });

  const response = await handler(fakeMultipartRequest(), fakeContext([]));

  assert.equal(response.status, 200);
  assert.equal(response.jsonBody?.timings?.enrichment_timed_out, true);
  assert.equal(abortObserved, true);
});

test("scan handler returns enriched result within enrichment budget", async () => {
  const handler = createScanHandler(
    new StubRecognition(baseResult()),
    {
      enrich: async (album) => ({ ...album, label: "Impulse!" })
    },
    { enrichmentTimeoutMs: 100, includeTimings: true });

  const response = await handler(fakeMultipartRequest(), fakeContext([]));

  assert.equal(response.status, 200);
  assert.equal(response.jsonBody?.album?.label, "Impulse!");
  assert.equal(response.jsonBody?.timings?.enrichment_timed_out, false);
});

test("scan handler omits timings unless diagnostics are enabled", async () => {
  const handler = createScanHandler(
    new StubRecognition(baseResult()),
    {
      enrich: async (album) => ({ ...album, label: "Impulse!" })
    },
    { enrichmentTimeoutMs: 100 });

  const response = await handler(fakeMultipartRequest(), fakeContext([]));

  assert.equal(response.status, 200);
  assert.equal(response.jsonBody?.timings, undefined);
});

test("scan handler logs recognition failures with request diagnostics", async () => {
  const errors: unknown[] = [];
  const handler = createScanHandler(
    {
      recognize: async () => {
        throw new Error("OpenAI request failed");
      }
    },
    undefined);

  const response = await handler(fakeMultipartRequest(), fakeContext([], errors));

  assert.equal(response.status, 502);
  assert.equal(response.jsonBody?.error?.code, "recognition_failed");
  assert.match(String(errors[0]), /Album recognition failed/);
  assert.match(String(errors[0]), /OpenAI request failed/);
  assert.match(String(errors[0]), /requestId/);
});

class StubRecognition {
  constructor(private readonly result: RecognitionResult) {}

  async recognize(): Promise<RecognitionResult> {
    return this.result;
  }
}

function baseResult(): RecognitionResult {
  return {
    status: "safe_to_buy",
    confidence: 0.9,
    album: {
      mbid: null,
      discogs_release_id: null,
      title: "Cosmic Music",
      artist: "John Coltrane & Alice Coltrane",
      year: 1968,
      first_release_year: null,
      release_year: null,
      format: "Vinyl",
      label: null,
      catalog_number: null,
      country: null,
      back_cover_text: null,
      release_notes: null
    },
    candidates: []
  };
}

function fakeMultipartRequest(): HttpRequest {
  return {
    headers: new Headers({ "content-type": "multipart/form-data; boundary=test" }),
    formData: async () => {
      const form = new FormData();
      form.set("image", new File([new Uint8Array([0xFF, 0xD8, 0xFF])], "scan.jpg", { type: "image/jpeg" }));
      return form;
    }
  } as HttpRequest;
}

function fakeContext(warnings: unknown[], errors: unknown[] = []): InvocationContext {
  return {
    log: () => {},
    warn: (...args: unknown[]) => warnings.push(args.join(" ")),
    error: (...args: unknown[]) => errors.push(args.map((arg) => JSON.stringify(arg)).join(" "))
  } as unknown as InvocationContext;
}
