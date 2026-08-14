import { app } from "@azure/functions";
import { ArtworkFallbackAlbumEnrichment } from "./artworkFallback.js";
import { CachedAlbumEnrichment } from "./cachedEnrichment.js";
import { DiscogsAlbumEnrichment } from "./discogs.js";
import { createAlbumEnrichHandler } from "./enrich.js";
import { OpenAIAlbumRecognition } from "./openaiRecognition.js";
import { createScanHandler } from "./scan.js";
import { health } from "./health.js";
import { scanEnrichmentTimeoutMs } from "./runtimeConfig.js";

const apiKey = process.env.OPENAI_KEY;
if (!apiKey) {
  throw new Error("OPENAI_KEY app setting is required.");
}
const discogsToken = process.env.DISCOGS_TOKEN;
if (!discogsToken) {
  throw new Error("DISCOGS_TOKEN app setting is required for Discogs metadata enrichment.");
}

const recognition = new OpenAIAlbumRecognition({
  apiKey,
  model: process.env.OPENAI_MODEL || "gpt-5-mini"
});

const enrichmentChain = new ArtworkFallbackAlbumEnrichment({
  primary: new DiscogsAlbumEnrichment({ token: discogsToken })
});
const enrichment = new CachedAlbumEnrichment({
  inner: enrichmentChain,
  ttlMs: Number.parseInt(process.env.ENRICHMENT_CACHE_TTL_MS || "86400000", 10),
  maxEntries: Number.parseInt(process.env.ENRICHMENT_CACHE_MAX_ENTRIES || "500", 10)
});

app.http("health", {
  methods: ["GET"],
  authLevel: "anonymous",
  route: "health",
  handler: health
});

app.http("scan", {
  methods: ["POST"],
  authLevel: "function",
  route: "v1/scan",
  handler: createScanHandler(recognition, enrichment, {
    enrichmentTimeoutMs: scanEnrichmentTimeoutMs(),
    includeTimings: process.env.SCAN_INCLUDE_TIMINGS === "true",
    includeDebugDetails: process.env.SCAN_INCLUDE_DEBUG === "true"
  })
});

app.http("enrichAlbum", {
  methods: ["POST"],
  authLevel: "function",
  route: "v1/enrich",
  handler: createAlbumEnrichHandler(enrichment)
});
