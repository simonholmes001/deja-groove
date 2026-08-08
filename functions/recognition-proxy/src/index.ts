import { app } from "@azure/functions";
import { ArtworkFallbackAlbumEnrichment } from "./artworkFallback.js";
import { DiscogsAlbumEnrichment, NoopAlbumEnrichment } from "./discogs.js";
import { OpenAIAlbumRecognition } from "./openaiRecognition.js";
import { createScanHandler } from "./scan.js";
import { health } from "./health.js";

const apiKey = process.env.OPENAI_KEY;
if (!apiKey) {
  throw new Error("OPENAI_KEY app setting is required.");
}

const recognition = new OpenAIAlbumRecognition({
  apiKey,
  model: process.env.OPENAI_MODEL || "gpt-5-mini"
});

const enrichment = process.env.DISCOGS_TOKEN
  ? new ArtworkFallbackAlbumEnrichment({
      primary: new DiscogsAlbumEnrichment({ token: process.env.DISCOGS_TOKEN })
    })
  : new ArtworkFallbackAlbumEnrichment({
      primary: new NoopAlbumEnrichment()
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
    enrichmentTimeoutMs: Number.parseInt(process.env.SCAN_ENRICHMENT_TIMEOUT_MS || "1500", 10)
  })
});
