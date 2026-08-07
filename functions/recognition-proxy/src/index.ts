import { app } from "@azure/functions";
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
  handler: createScanHandler(recognition)
});
