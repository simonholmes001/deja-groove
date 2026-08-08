import { randomUUID } from "node:crypto";
import type { HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import type { ApiError, RecognitionResult, ScanResponse, ScanTimings } from "./contracts.js";
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
    const scanStartedAt = Date.now();

    try {
      const imageReadStartedAt = Date.now();
      const image = await readScanImage(request);
      const imageReadMs = elapsedSince(imageReadStartedAt);

      const recognitionStartedAt = Date.now();
      const result = await recognition.recognize(image);
      const recognitionMs = elapsedSince(recognitionStartedAt);

      const enrichmentStartedAt = Date.now();
      const enrichmentResult = enrichment
        ? await enrichRecognitionResult(result, enrichment, context, enrichmentTimeoutMs)
        : { result, timedOut: false };
      const enrichmentMs = elapsedSince(enrichmentStartedAt);
      const timings: ScanTimings = {
        total_ms: elapsedSince(scanStartedAt),
        image_read_ms: imageReadMs,
        recognition_ms: recognitionMs,
        enrichment_ms: enrichmentMs,
        image_bytes: image.data.length,
        enrichment_timed_out: enrichmentResult.timedOut
      };

      context.log("Album scan completed.", {
        requestId,
        status: enrichmentResult.result.status,
        timings
      });

      return {
        status: 200,
        jsonBody: toScanResponse(enrichmentResult.result, requestId, timings),
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

function elapsedSince(startedAt: number): number {
  return Date.now() - startedAt;
}

async function enrichRecognitionResult(
  result: RecognitionResult,
  enrichment: AlbumEnrichmentPort,
  context: InvocationContext,
  timeoutMs: number
): Promise<{ result: RecognitionResult; timedOut: boolean }> {
  try {
    const enriched = await withTimeout(
      async (): Promise<RecognitionResult> => ({
        ...result,
        album: result.album ? await enrichment.enrich(result.album) : result.album,
        candidates: result.candidates
          ? await Promise.all(result.candidates.map((candidate) => enrichment.enrich(candidate)))
          : result.candidates
      }),
      timeoutMs);
    return { result: enriched, timedOut: false };
  } catch (error) {
    if (error instanceof EnrichmentTimeoutError) {
      context.warn(`Album metadata enrichment exceeded ${timeoutMs}ms; returning recognition-only result.`);
      return { result, timedOut: true };
    }
    context.warn("Album metadata enrichment failed; returning recognition-only result.", error);
    return { result, timedOut: false };
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

export function toScanResponse(result: RecognitionResult, requestId: string, timings?: ScanTimings): ScanResponse {
  return {
    status: result.status,
    confidence: clampConfidence(result.confidence),
    album: result.status === "safe_to_buy" ? result.album ?? null : null,
    candidates: result.status === "ambiguous" ? result.candidates ?? [] : [],
    timings,
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
