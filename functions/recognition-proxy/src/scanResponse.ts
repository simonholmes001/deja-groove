import type { HttpResponseInit } from "@azure/functions";
import type { ApiError, RecognitionResult, ScanResponse, ScanTimings } from "./contracts.js";

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

export function errorResponse(
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

export function noStoreHeaders(): Record<string, string> {
  return {
    "Cache-Control": "no-store"
  };
}

function clampConfidence(confidence: number): number {
  if (Number.isNaN(confidence)) return 0;
  return Math.max(0, Math.min(1, confidence));
}
