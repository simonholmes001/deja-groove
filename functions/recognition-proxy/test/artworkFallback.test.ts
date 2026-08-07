import assert from "node:assert/strict";
import test from "node:test";
import { ArtworkFallbackAlbumEnrichment } from "../src/artworkFallback.js";
import type { Album } from "../src/contracts.js";
import type { AlbumEnrichmentPort } from "../src/discogs.js";

test("ArtworkFallbackAlbumEnrichment preserves complete primary artwork", async () => {
  const requests: string[] = [];
  const enrichment = new ArtworkFallbackAlbumEnrichment({
    primary: new StubEnrichment({
      cover_image_url: "https://discogs.test/front.jpg",
      thumbnail_url: "https://discogs.test/thumb.jpg",
      back_cover_image_url: "https://discogs.test/back.jpg"
    }),
    fetchImpl: async (input) => {
      requests.push(String(input));
      return jsonResponse({});
    }
  });

  const album = await enrichment.enrich(baseAlbum());

  assert.equal(album.cover_image_url, "https://discogs.test/front.jpg");
  assert.equal(album.thumbnail_url, "https://discogs.test/thumb.jpg");
  assert.equal(album.back_cover_image_url, "https://discogs.test/back.jpg");
  assert.deepEqual(requests, []);
});

test("ArtworkFallbackAlbumEnrichment fills missing front and back artwork from Cover Art Archive", async () => {
  const requests: string[] = [];
  const enrichment = new ArtworkFallbackAlbumEnrichment({
    primary: new StubEnrichment({}),
    coverArtArchiveBaseURL: "https://cover-art.test",
    fetchImpl: async (input) => {
      requests.push(String(input));
      return jsonResponse({
        images: [
          {
            front: true,
            approved: true,
            image: "https://cover-art.test/release/front.jpg",
            thumbnails: {
              "500": "https://cover-art.test/release/front-500.jpg",
              small: "https://cover-art.test/release/front-small.jpg"
            }
          },
          {
            back: true,
            approved: true,
            image: "https://cover-art.test/release/back.jpg"
          }
        ]
      });
    }
  });

  const album = await enrichment.enrich(baseAlbum());

  assert.equal(requests.length, 1);
  assert.match(requests[0], /cover-art\.test\/release\/mbid-1$/);
  assert.equal(album.cover_image_url, "https://cover-art.test/release/front.jpg");
  assert.equal(album.thumbnail_url, "https://cover-art.test/release/front-500.jpg");
  assert.equal(album.back_cover_image_url, "https://cover-art.test/release/back.jpg");
});

test("ArtworkFallbackAlbumEnrichment falls back to iTunes when front artwork is still missing", async () => {
  const requests: string[] = [];
  const enrichment = new ArtworkFallbackAlbumEnrichment({
    primary: new StubEnrichment({ mbid: null }),
    itunesBaseURL: "https://itunes.test",
    fetchImpl: async (input) => {
      requests.push(String(input));
      return jsonResponse({
        results: [
          {
            artistName: "Someone Else",
            collectionName: "Other Album",
            artworkUrl100: "https://is1-ssl.mzstatic.com/image/thumb/Music/xx/source/100x100bb.jpg"
          },
          {
            artistName: "Sonny Rollins",
            collectionName: "The Bridge",
            artworkUrl100: "https://is1-ssl.mzstatic.com/image/thumb/Music/yy/source/100x100bb.jpg"
          }
        ]
      });
    }
  });

  const album = await enrichment.enrich({
    ...baseAlbum(),
    mbid: null,
    title: "The Bridge",
    artist: "Sonny Rollins"
  });

  assert.equal(requests.length, 1);
  assert.match(requests[0], /itunes\.test\/search\?/);
  assert.equal(album.cover_image_url, "https://is1-ssl.mzstatic.com/image/thumb/Music/yy/source/600x600bb.jpg");
  assert.equal(album.thumbnail_url, "https://is1-ssl.mzstatic.com/image/thumb/Music/yy/source/100x100bb.jpg");
  assert.equal(album.back_cover_image_url, null);
});

test("ArtworkFallbackAlbumEnrichment tries release-group artwork after release artwork is missing", async () => {
  const requests: string[] = [];
  const enrichment = new ArtworkFallbackAlbumEnrichment({
    primary: new StubEnrichment({}),
    coverArtArchiveBaseURL: "https://cover-art.test",
    fetchImpl: async (input) => {
      requests.push(String(input));
      if (String(input).includes("/release/")) {
        return {
          ok: false,
          status: 404,
          json: async () => ({})
        } as Response;
      }
      return jsonResponse({
        images: [{ types: ["Front"], image: "https://cover-art.test/release-group/front.jpg" }]
      });
    }
  });

  const album = await enrichment.enrich(baseAlbum());

  assert.equal(requests.length, 2);
  assert.match(requests[0], /cover-art\.test\/release\/mbid-1$/);
  assert.match(requests[1], /cover-art\.test\/release-group\/mbid-1$/);
  assert.equal(album.cover_image_url, "https://cover-art.test/release-group/front.jpg");
});

test("ArtworkFallbackAlbumEnrichment keeps primary enrichment when fallback provider fails", async () => {
  const enrichment = new ArtworkFallbackAlbumEnrichment({
    primary: new StubEnrichment({
      label: "Bluebird",
      cover_image_url: null,
      thumbnail_url: null,
      back_cover_image_url: null
    }),
    fetchImpl: async () => {
      throw new Error("network down");
    }
  });

  const album = await enrichment.enrich(baseAlbum());

  assert.equal(album.label, "Bluebird");
  assert.equal(album.cover_image_url, null);
  assert.equal(album.back_cover_image_url, null);
});

class StubEnrichment implements AlbumEnrichmentPort {
  constructor(private readonly patch: Partial<Album>) {}

  async enrich(album: Album): Promise<Album> {
    return { ...album, ...this.patch };
  }
}

function baseAlbum(): Album {
  return {
    mbid: "mbid-1",
    discogs_release_id: null,
    title: "Kind of Blue",
    artist: "Miles Davis",
    year: null,
    first_release_year: null,
    release_year: null,
    format: "LP",
    label: null,
    catalog_number: null,
    country: null,
    cover_image_url: null,
    thumbnail_url: null,
    back_cover_image_url: null,
    back_cover_text: null,
    release_notes: null
  };
}

function jsonResponse(body: unknown): Response {
  return {
    ok: true,
    status: 200,
    json: async () => body
  } as Response;
}
