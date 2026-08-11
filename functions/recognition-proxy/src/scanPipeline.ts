import { performance } from "node:perf_hooks";
import type { InvocationContext } from "@azure/functions";
import type { RecognitionResult, ScanTimings } from "./contracts.js";
import type { ScanImage } from "./http.js";
import type { AlbumEnrichmentPort } from "./discogs.js";
import type { RecognitionPort } from "./openaiRecognition.js";

export type ScanPipelineResult = {
  result: RecognitionResult;
  timings: ScanTimings;
};

export async function runScanPipeline(
  image: ScanImage,
  recognition: RecognitionPort,
  enrichment: AlbumEnrichmentPort | undefined,
  context: InvocationContext,
  enrichmentTimeoutMs: number,
  startedAt: number
): Promise<ScanPipelineResult> {
  const recognitionStartedAt = performance.now();
  const result = await recognition.recognize(image);
  const recognitionMs = elapsedSince(recognitionStartedAt);

  const enrichmentStartedAt = performance.now();
  const enrichmentResult = enrichment
    ? await enrichRecognitionResult(result, enrichment, context, enrichmentTimeoutMs)
    : { result, timedOut: false };
  const enrichmentMs = elapsedSince(enrichmentStartedAt);

  return {
    result: enrichmentResult.result,
    timings: {
      total_ms: elapsedSince(startedAt),
      image_read_ms: 0,
      recognition_ms: recognitionMs,
      enrichment_ms: enrichmentMs,
      image_bytes: image.data.length,
      enrichment_timed_out: enrichmentResult.timedOut
    }
  };
}

export function elapsedSince(startedAt: number): number {
  return Math.round(performance.now() - startedAt);
}

async function enrichRecognitionResult(
  result: RecognitionResult,
  enrichment: AlbumEnrichmentPort,
  context: InvocationContext,
  timeoutMs: number
): Promise<{ result: RecognitionResult; timedOut: boolean }> {
  try {
    const enriched = await withTimeout(
      async (signal): Promise<RecognitionResult> => ({
        ...result,
        album: result.album ? await enrichment.enrich(result.album, { signal, logger: context }) : result.album,
        candidates: result.candidates
          ? await Promise.all(result.candidates.map((candidate) => enrichment.enrich(candidate, { signal, logger: context })))
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

async function withTimeout<T>(operation: (signal: AbortSignal) => Promise<T>, timeoutMs: number): Promise<T> {
  const controller = new AbortController();
  if (timeoutMs <= 0) return await operation(controller.signal);

  let timeout: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      operation(controller.signal),
      new Promise<T>((_, reject) => {
        timeout = setTimeout(() => {
          controller.abort();
          reject(new EnrichmentTimeoutError());
        }, timeoutMs);
      })
    ]);
  } finally {
    if (timeout) clearTimeout(timeout);
  }
}

class EnrichmentTimeoutError extends Error {}
