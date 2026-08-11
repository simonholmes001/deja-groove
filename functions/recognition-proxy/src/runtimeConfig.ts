import { defaultEnrichmentTimeoutMs } from "./scan.js";

export function scanEnrichmentTimeoutMs(value = process.env.SCAN_ENRICHMENT_TIMEOUT_MS): number {
  if (value === undefined || value.trim() === "") {
    return defaultEnrichmentTimeoutMs;
  }

  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : defaultEnrichmentTimeoutMs;
}
