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
