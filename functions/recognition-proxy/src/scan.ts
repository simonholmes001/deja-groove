import { randomUUID } from "node:crypto";
import { performance } from "node:perf_hooks";
import type { HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import { readScanImage, RequestError } from "./http.js";
import type { AlbumEnrichmentPort } from "./discogs.js";
import { RecognitionOutputError } from "./openaiRecognition.js";
import type { RecognitionPort } from "./openaiRecognition.js";
import { elapsedSince, runScanPipeline } from "./scanPipeline.js";
import { errorResponse, noStoreHeaders, toScanResponse } from "./scanResponse.js";

export { toScanResponse } from "./scanResponse.js";

type ScanHandlerOptions = {
  enrichmentTimeoutMs?: number;
  includeTimings?: boolean;
  includeDebugDetails?: boolean;
};

export const defaultEnrichmentTimeoutMs = 12000;

export function createScanHandler(
  recognition: RecognitionPort,
  enrichment?: AlbumEnrichmentPort,
  options: ScanHandlerOptions = {}
) {
  const enrichmentTimeoutMs = validTimeoutMs(options.enrichmentTimeoutMs, defaultEnrichmentTimeoutMs);
  const includeTimings = options.includeTimings === true;
  const includeDebugDetails = options.includeDebugDetails === true;
  return async function scan(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
    const requestId = randomUUID();
    const scanStartedAt = performance.now();

    try {
      const imageReadStartedAt = performance.now();
      const image = await readScanImage(request);
      const imageReadMs = elapsedSince(imageReadStartedAt);
      const pipeline = await runScanPipeline(image, recognition, enrichment, context, enrichmentTimeoutMs, scanStartedAt);
      const timings = { ...pipeline.timings, image_read_ms: imageReadMs };

      context.log("Album scan completed.", {
        requestId,
        status: pipeline.result.status,
        timings
      });

      return {
        status: 200,
        jsonBody: toScanResponse(pipeline.result, requestId, includeTimings ? timings : undefined),
        headers: noStoreHeaders()
      };
    } catch (error) {
      if (error instanceof RequestError) {
        return errorResponse(error.status, error.code, error.message, error.retryable, requestId);
      }

      context.error("Album recognition failed.", errorDetails(error, requestId, includeDebugDetails));
      return errorResponse(
        502,
        "recognition_failed",
        "Album recognition failed. Try again later.",
        true,
        requestId);
    }
  };
}

function validTimeoutMs(value: number | undefined, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) ? value : fallback;
}

function errorDetails(error: unknown, requestId: string, includeDebugDetails: boolean): Record<string, unknown> {
  if (error instanceof RecognitionOutputError) {
    return {
      requestId,
      name: error.name,
      message: error.message,
      outputLength: error.outputLength
    };
  }

  if (error instanceof Error) {
    return {
      requestId,
      name: error.name,
      message: error.message,
      ...(includeDebugDetails ? { stack: error.stack } : {})
    };
  }

  return {
    requestId,
    message: String(error)
  };
}
