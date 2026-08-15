import type { HttpRequest, HttpResponseInit, InvocationContext } from "@azure/functions";
import crypto from "node:crypto";
import type { Album } from "./contracts.js";
import type { AlbumEnrichmentPort } from "./discogs.js";
import { errorResponse, noStoreHeaders } from "./scanResponse.js";

type AlbumEnrichmentRequest = {
  album?: Album;
};

type AlbumEnrichmentResponse = {
  album: Album;
  request_id: string;
};

export function createAlbumEnrichHandler(enrichment: AlbumEnrichmentPort) {
  return async function enrichAlbum(request: HttpRequest, context: InvocationContext): Promise<HttpResponseInit> {
    const requestId = crypto.randomUUID();
    try {
      const body = await request.json() as AlbumEnrichmentRequest;
      if (!isAlbum(body.album)) {
        return errorResponse(400, "invalid_enrichment_request", "An album with artist and title is required.", false, requestId);
      }

      const album = await enrichment.enrich(body.album, { logger: context });
      context.log(
        "Album enrichment completed.",
        `discogsReleaseId=${present(album.discogs_release_id)}`,
        `listeningLinkCount=${album.listening_links?.length || 0}`,
        enrichmentSummary(album));
      const response: AlbumEnrichmentResponse = { album, request_id: requestId };
      return {
        status: 200,
        headers: noStoreHeaders(),
        jsonBody: response
      };
    } catch (error) {
      context.warn("Album enrichment failed.", {
        requestId,
        error: error instanceof Error ? error.message : String(error)
      });
      return errorResponse(502, "album_enrichment_failed", "Album enrichment failed.", true, requestId);
    }
  };
}

function isAlbum(album: unknown): album is Album {
  if (!album || typeof album !== "object") return false;
  const candidate = album as Partial<Album>;
  return hasText(candidate.artist) && hasText(candidate.title);
}

function hasText(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function enrichmentSummary(album: Album): Record<string, unknown> {
  return {
    discogsReleaseIdPresent: Boolean(album.discogs_release_id),
    discogsMasterIdPresent: Boolean(album.discogs_master_id),
    labelPresent: Boolean(album.label),
    catalogNumberPresent: Boolean(album.catalog_number),
    countryPresent: Boolean(album.country),
    barcodePresent: Boolean(album.barcode),
    releaseDatePresent: Boolean(album.release_date || album.release_year || album.year),
    genreCount: album.genres?.length || 0,
    styleCount: album.styles?.length || 0,
    trackCount: album.tracklist?.length || 0,
    identifierCount: album.identifiers?.length || 0,
    listeningLinkCount: album.listening_links?.length || 0
  };
}

function present(value: string | undefined | null): string {
  return value && value.trim() ? "present" : "missing";
}
