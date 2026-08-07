import assert from "node:assert/strict";
import test from "node:test";
import { toScanResponse } from "../src/scan.js";

test("toScanResponse returns one album for strong matches", () => {
  const response = toScanResponse({
    status: "safe_to_buy",
    confidence: 1.2,
    album: {
      mbid: null,
      discogs_release_id: null,
      title: "Kind of Blue",
      artist: "Miles Davis",
      year: 1959,
      first_release_year: 1959,
      release_year: 1959,
      format: "LP",
      label: null,
      catalog_number: null,
      country: null,
      back_cover_text: null,
      release_notes: null
    },
    candidates: []
  }, "00000000-0000-4000-8000-000000000001");

  assert.equal(response.status, "safe_to_buy");
  assert.equal(response.confidence, 1);
  assert.equal(response.album?.artist, "Miles Davis");
  assert.deepEqual(response.candidates, []);
});

test("toScanResponse returns candidates for ambiguous matches", () => {
  const response = toScanResponse({
    status: "ambiguous",
    confidence: -0.2,
    album: null,
    candidates: [
      {
        mbid: null,
        discogs_release_id: null,
        title: "Unknown Pleasures",
        artist: "Joy Division",
        year: 1979,
        first_release_year: 1979,
        release_year: 1979,
        format: "LP",
        label: null,
        catalog_number: null,
        country: null,
        back_cover_text: null,
        release_notes: null
      }
    ]
  }, "00000000-0000-4000-8000-000000000002");

  assert.equal(response.status, "ambiguous");
  assert.equal(response.confidence, 0);
  assert.equal(response.album, null);
  assert.equal(response.candidates.length, 1);
});
