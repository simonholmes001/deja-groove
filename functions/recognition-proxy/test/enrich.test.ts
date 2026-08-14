import assert from "node:assert/strict";
import test from "node:test";
import { createAlbumEnrichHandler } from "../src/enrich.js";
import type { Album } from "../src/contracts.js";
import type { AlbumEnrichmentPort } from "../src/discogs.js";

test("album enrich handler returns shared enriched album metadata", async () => {
  const logs: string[] = [];
  const handler = createAlbumEnrichHandler(new StubEnrichment({
    discogs_release_id: "123456",
    label: "Cellar Music",
    catalog_number: "CM-123",
    country: "US",
    genres: ["Jazz"],
    styles: ["Contemporary Jazz"],
    tracklist: [{ position: "A1", title: "Indigo", duration: "4:12" }]
  }));

  const response = await handler(jsonRequest({
    album: {
      title: "Indigo",
      artist: "Miki Yamanaka",
      listening_links: [{
        provider: "Apple Music",
        url: "https://music.apple.com/album/indigo"
      }]
    }
  }), context(logs));

  assert.equal(response.status, 200);
  assert.equal(response.jsonBody.album.discogs_release_id, "123456");
  assert.equal(response.jsonBody.album.label, "Cellar Music");
  assert.equal(response.jsonBody.album.catalog_number, "CM-123");
  assert.equal(response.jsonBody.album.country, "US");
  assert.deepEqual(response.jsonBody.album.genres, ["Jazz"]);
  assert.equal(response.jsonBody.album.tracklist[0].title, "Indigo");
  assert.equal(response.jsonBody.album.listening_links[0].provider, "Apple Music");
  assert.match(logs.join("\n"), /Album enrichment completed/);
  assert.match(logs.join("\n"), /discogsReleaseId/);
  assert.match(logs.join("\n"), /listeningLinkCount/);
});

test("album enrich handler rejects requests without an album title and artist", async () => {
  const handler = createAlbumEnrichHandler(new StubEnrichment({}));

  const response = await handler(jsonRequest({ album: { title: "Missing Artist" } }), context());

  assert.equal(response.status, 400);
  assert.equal(response.jsonBody.error.code, "invalid_enrichment_request");
});

class StubEnrichment implements AlbumEnrichmentPort {
  constructor(private readonly patch: Partial<Album>) {}

  async enrich(album: Album): Promise<Album> {
    return { ...album, ...this.patch };
  }
}

function jsonRequest(body: unknown) {
  return {
    json: async () => body
  } as never;
}

function context(logs: string[] = []) {
  return {
    log: (...args: unknown[]) => logs.push(args.map(String).join(" ")),
    warn: (...args: unknown[]) => logs.push(args.map(String).join(" "))
  } as never;
}
