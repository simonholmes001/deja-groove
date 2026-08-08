import { randomUUID } from "node:crypto";
import type { HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import type { ApiError, RecognitionResult, ScanResponse } from "./contracts.js";
import { readScanImage, RequestError } from "./http.js";
import type { AlbumEnrichmentPort } from "./discogs.js";
import type { RecognitionPort } from "./openaiRecognition.js";

export function createScanHandler(recognition: RecognitionPort, enrichment?: AlbumEnrichmentPort) {
  return async function scan(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
    const requestId = randomUUID();

    try {
      const image = await readScanImage(request);
      const result = await recognition.recognize(image);
      const enriched = enrichment
        ? await enrichRecognitionResult(result, enrichment, context)
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

async function enrichRecognitionResult(
  result: RecognitionResult,
  enrichment: AlbumEnrichmentPort,
  context: InvocationContext
): Promise<RecognitionResult> {
  try {
    return {
      ...result,
      album: result.album ? await enrichment.enrich(result.album) : result.album,
      candidates: result.candidates
        ? await Promise.all(result.candidates.map((candidate) => enrichment.enrich(candidate)))
        : result.candidates
    };
  } catch (error) {
    context.warn("Album metadata enrichment failed; returning recognition-only result.", error);
    return result;
  }
}

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
