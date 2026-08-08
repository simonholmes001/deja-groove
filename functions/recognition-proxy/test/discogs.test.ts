import assert from "node:assert/strict";
import test from "node:test";
import { DiscogsAlbumEnrichment } from "../src/discogs.js";

test("DiscogsAlbumEnrichment maps search and release metadata", async () => {
  const requests: string[] = [];
  const enrichment = new DiscogsAlbumEnrichment({
    token: "token",
    baseURL: "https://discogs.test",
    fetchImpl: async (input) => {
      requests.push(String(input));
      if (String(input).includes("/database/search")) {
        return jsonResponse({
          results: [{
            id: 249504,
            master_id: 52245,
            title: "Miles Davis - Kind Of Blue",
            country: "US",
            year: "1959",
            format: ["LP", "Album", "Mono"],
            label: ["Columbia"],
            catno: "CL 1355",
            barcode: ["074646493525"],
            genre: ["Jazz"],
            style: ["Modal"],
            thumb: "https://img.discogs.test/thumb.jpg",
            cover_image: "https://img.discogs.test/front.jpg",
            resource_url: "https://api.discogs.test/releases/249504",
            uri: "https://www.discogs.com/release/249504"
          }]
        });
      }

      return jsonResponse({
        id: 249504,
        master_id: 52245,
        resource_url: "https://api.discogs.test/releases/249504",
        uri: "https://www.discogs.com/release/249504",
        title: "Kind Of Blue (Mono Variant)",
        country: "US",
        year: 1959,
        released: "1959-08-17",
        notes: "Original six-eye labels.",
        data_quality: "Correct",
        artists: [{ name: "Miles Davis" }],
        labels: [{ name: "Columbia", catno: "CL 1355" }],
        formats: [{ name: "Vinyl", qty: "1", descriptions: ["LP", "Album", "Mono"] }],
        genres: ["Jazz"],
        styles: ["Modal"],
        identifiers: [
          { type: "Barcode", value: "074646493525" },
          { type: "Matrix / Runout", value: "XLP47324-1A", description: "Side A" }
        ],
        companies: [
          { entity_type_name: "Record Company", name: "Columbia Records", catno: "CL 1355" }
        ],
        images: [
          { type: "primary", uri: "https://img.discogs.test/front-full.jpg", uri150: "https://img.discogs.test/front-thumb.jpg" },
          { type: "secondary", uri: "https://img.discogs.test/back-full.jpg" }
        ],
        tracklist: [
          { position: "A1", title: "So What", duration: "9:22", type_: "track" },
          { position: "A2", title: "Freddie Freeloader", duration: "9:46", type_: "track" }
        ]
      });
    }
  });

  const album = await enrichment.enrich({
    mbid: null,
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
    back_cover_text: null,
    release_notes: null
  });

  assert.equal(requests.length, 2);
  assert.match(requests[0], /database\/search/);
  assert.match(requests[1], /releases\/249504/);
  assert.equal(album.discogs_release_id, "249504");
  assert.equal(album.discogs_master_id, "52245");
  assert.equal(album.discogs_url, "https://www.discogs.com/release/249504");
  assert.equal(album.discogs_resource_url, "https://api.discogs.test/releases/249504");
  assert.equal(album.title, "Kind of Blue");
  assert.equal(album.artist, "Miles Davis");
  assert.equal(album.release_date, "1959-08-17");
  assert.equal(album.release_year, 1959);
  assert.equal(album.label, "Columbia");
  assert.equal(album.catalog_number, "CL 1355");
  assert.equal(album.barcode, "074646493525");
  assert.equal(album.cover_image_url, "https://img.discogs.test/front-full.jpg");
  assert.equal(album.thumbnail_url, "https://img.discogs.test/front-thumb.jpg");
  assert.equal(album.back_cover_image_url, "https://img.discogs.test/back-full.jpg");
  assert.deepEqual(album.genres, ["Jazz"]);
  assert.deepEqual(album.styles, ["Modal"]);
  assert.deepEqual(album.companies, ["Record Company: Columbia Records - CL 1355"]);
  assert.equal(album.tracklist?.[0]?.title, "So What");
  assert.equal(album.identifiers?.[1]?.description, "Side A");
  assert.equal(album.discogs_data_quality, "Correct");
});

function jsonResponse(body: unknown): Response {
  return {
    ok: true,
    status: 200,
    json: async () => body
  } as Response;
}
