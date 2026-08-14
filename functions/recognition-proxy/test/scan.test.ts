import assert from "node:assert/strict";
import test from "node:test";
import { createScanHandler, defaultEnrichmentTimeoutMs, toScanResponse } from "../src/scan.js";
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

test("toScanResponse preserves enriched album metadata for the app contract", () => {
  const response = toScanResponse({
    status: "safe_to_buy",
    confidence: 0.96,
    album: {
      mbid: "mbid-1",
      discogs_release_id: "249504",
      discogs_master_id: "38276",
      discogs_url: "https://www.discogs.com/release/249504",
      discogs_resource_url: "https://api.discogs.com/releases/249504",
      title: "Cosmic Music",
      artist: "John Coltrane & Alice Coltrane",
      year: 1968,
      first_release_year: 1968,
      release_year: 1968,
      first_release_date: "1968",
      release_date: "1968",
      format: "Vinyl, LP",
      label: "Impulse!",
      catalog_number: "AS-9148",
      country: "US",
      barcode: "0123456789",
      cover_image_url: "https://example.com/front.jpg",
      thumbnail_url: "https://example.com/thumb.jpg",
      back_cover_image_url: "https://example.com/back.jpg",
      back_cover_text: "Recorded in New York.",
      release_notes: "Gatefold pressing.",
      genres: ["Jazz"],
      styles: ["Free Jazz"],
      companies: ["ABC Records"],
      tracklist: [{ position: "A1", title: "Manifestation", duration: "11:37" }],
      identifiers: [{ type: "Matrix / Runout", value: "AS-9148-A", description: "Side A" }],
      discogs_data_quality: "Correct",
      listening_links: [{
        provider: "Apple Music",
        url: "https://music.apple.com/album/1",
        catalog_id: "1",
        preview_url: "https://example.com/preview.m4a"
      }]
    },
    candidates: []
  }, "00000000-0000-4000-8000-000000000003");

  assert.equal(response.album?.label, "Impulse!");
  assert.equal(response.album?.catalog_number, "AS-9148");
  assert.equal(response.album?.country, "US");
  assert.equal(response.album?.release_notes, "Gatefold pressing.");
  assert.deepEqual(response.album?.genres, ["Jazz"]);
  assert.equal(response.album?.tracklist?.[0]?.title, "Manifestation");
  assert.equal(response.album?.identifiers?.[0]?.type, "Matrix / Runout");
  assert.equal(response.album?.listening_links?.[0]?.provider, "Apple Music");
});

test("toScanResponse adds Apple Music search links to recognition-only albums", () => {
  const response = toScanResponse({
    status: "safe_to_buy",
    confidence: 0.9,
    album: {
      ...baseResult().album!,
      artist: "Iron Maiden",
      title: "Powerslave",
      listening_links: []
    },
    candidates: []
  }, "00000000-0000-4000-8000-000000000004");

  assert.equal(response.album?.listening_links?.[0]?.provider, "Apple Music");
  assert.equal(response.album?.listening_links?.[0]?.url, "https://music.apple.com/search?term=Iron+Maiden+Powerslave");
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

test("scan handler default enrichment budget allows richer Discogs metadata", async () => {
  assert.equal(defaultEnrichmentTimeoutMs, 12000);

  const handler = createScanHandler(
    new StubRecognition(baseResult()),
    {
      enrich: async (album) => ({
        ...album,
        label: "Impulse!",
        catalog_number: "AS-9148",
        country: "US",
        genres: ["Jazz"],
        styles: ["Free Jazz"],
        tracklist: [{ position: "A1", title: "Manifestation", duration: "11:37" }]
      })
    },
    { includeTimings: true });

  const response = await handler(fakeMultipartRequest(), fakeContext([]));

  assert.equal(response.status, 200);
  assert.equal(response.jsonBody?.album?.label, "Impulse!");
  assert.equal(response.jsonBody?.album?.catalog_number, "AS-9148");
  assert.deepEqual(response.jsonBody?.album?.genres, ["Jazz"]);
  assert.equal(response.jsonBody?.album?.tracklist?.[0]?.title, "Manifestation");
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
  assert.doesNotMatch(String(errors[0]), /stack/);
});

test("scan handler includes stack traces only when debug diagnostics are enabled", async () => {
  const errors: unknown[] = [];
  const handler = createScanHandler(
    {
      recognize: async () => {
        throw new Error("OpenAI request failed");
      }
    },
    undefined,
    { includeDebugDetails: true });

  const response = await handler(fakeMultipartRequest(), fakeContext([], errors));

  assert.equal(response.status, 502);
  assert.match(String(errors[0]), /stack/);
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
