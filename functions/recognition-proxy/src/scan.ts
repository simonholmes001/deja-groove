import { randomUUID } from "node:crypto";
import type { HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import type { ApiError, RecognitionResult, ScanResponse } from "./contracts.js";
import { readScanImage, RequestError } from "./http.js";
import type { AlbumEnrichmentPort } from "./discogs.js";
import type { RecognitionPort } from "./openaiRecognition.js";

type ScanHandlerOptions = {
  enrichmentTimeoutMs?: number;
};

const defaultEnrichmentTimeoutMs = 1500;

export function createScanHandler(
  recognition: RecognitionPort,
  enrichment?: AlbumEnrichmentPort,
  options: ScanHandlerOptions = {}
) {
  const enrichmentTimeoutMs = validTimeoutMs(options.enrichmentTimeoutMs, defaultEnrichmentTimeoutMs);
  return async function scan(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
    const requestId = randomUUID();

    try {
      const image = await readScanImage(request);
      const result = await recognition.recognize(image);
      const enriched = enrichment
        ? await enrichRecognitionResult(result, enrichment, context, enrichmentTimeoutMs)
        : result;
      return {
        status: 200,
        jsonBody: toScanResponse(enriched, requestId),
        headers: noStoreHeaders()
      };
    } catch (error) {
      if (error instanceof RequestError) {
        return errorResponse(error.status, error.code, error.message, error.retryable, requestId);
      }

      context.error("Album recognition failed.", error);
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

async function enrichRecognitionResult(
  result: RecognitionResult,
  enrichment: AlbumEnrichmentPort,
  context: InvocationContext,
  timeoutMs: number
): Promise<RecognitionResult> {
  try {
    return await withTimeout(
      async () => ({
        ...result,
        album: result.album ? await enrichment.enrich(result.album) : result.album,
        candidates: result.candidates
          ? await Promise.all(result.candidates.map((candidate) => enrichment.enrich(candidate)))
          : result.candidates
      }),
      timeoutMs);
  } catch (error) {
    if (error instanceof EnrichmentTimeoutError) {
      context.warn(`Album metadata enrichment exceeded ${timeoutMs}ms; returning recognition-only result.`);
      return result;
    }
    context.warn("Album metadata enrichment failed; returning recognition-only result.", error);
    return result;
  }
}

async function withTimeout<T>(operation: () => Promise<T>, timeoutMs: number): Promise<T> {
  if (timeoutMs <= 0) return await operation();

  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      operation(),
      new Promise<T>((_, reject) => {
        timeout = setTimeout(() => reject(new EnrichmentTimeoutError()), timeoutMs);
      })
    ]);
  } finally {
    if (timeout) clearTimeout(timeout);
  }
}

class EnrichmentTimeoutError extends Error {}

export function toScanResponse(result: RecognitionResult, requestId: string): ScanResponse {
  return {
    status: result.status,
    confidence: clampConfidence(result.confidence),
    album: result.status === "safe_to_buy" ? result.album ?? null : null,
    candidates: result.status === "ambiguous" ? result.candidates ?? [] : [],
    request_id: requestId
  };
}

function clampConfidence(confidence: number): number {
  if (Number.isNaN(confidence)) return 0;
  return Math.max(0, Math.min(1, confidence));
}

function errorResponse(
  status: number,
  code: string,
  message: string,
  retryable: boolean,
  requestId: string
): HttpResponseInit {
  const body: ApiError = {
    error: {
      code,
      message,
      retryable,
      request_id: requestId
    }
  };

  return {
    status,
    jsonBody: body,
    headers: noStoreHeaders()
  };
}

function noStoreHeaders(): Record<string, string> {
  return {
    "Cache-Control": "no-store"
  };
}
