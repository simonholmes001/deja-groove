import type { HttpResponseInit } from "@azure/functions";
import type { Album, ApiError, RecognitionResult, ScanResponse, ScanTimings } from "./contracts.js";

export function toScanResponse(result: RecognitionResult, requestId: string, timings?: ScanTimings): ScanResponse {
  return {
    status: result.status,
    confidence: clampConfidence(result.confidence),
    album: result.status === "safe_to_buy" ? withAppleMusicFallback(result.album) : null,
    candidates: result.status === "ambiguous" ? (result.candidates ?? []).map(withRequiredAppleMusicFallback) : [],
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

function withAppleMusicFallback(album: Album | null | undefined): Album | null {
  if (!album) return null;
  return withRequiredAppleMusicFallback(album);
}

function withRequiredAppleMusicFallback(album: Album): Album {
  if ((album.listening_links || []).some((link) => clean(link.url))) return album;

  return {
    ...album,
    listening_links: [{
      provider: "Apple Music",
      url: appleMusicSearchUrl(album),
      catalog_id: null
    }]
  };
}

function appleMusicSearchUrl(album: Album): string {
  const term = [album.artist, album.title].filter(Boolean).join(" ");
  const params = new URLSearchParams({ term });
  return `https://music.apple.com/search?${params.toString()}`;
}

function clean(value: string | undefined | null): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}
