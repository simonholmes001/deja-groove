import assert from "node:assert/strict";
import test from "node:test";
import { parseRecognitionOutput } from "../src/openaiRecognition.js";

test("parseRecognitionOutput accepts the scan contract", () => {
  const result = parseRecognitionOutput(JSON.stringify({
    status: "safe_to_buy",
    confidence: 0.91,
    album: {
      mbid: null,
      discogs_release_id: "123",
      title: "Blue Train",
      artist: "John Coltrane",
      year: 1958,
      first_release_year: 1958,
      release_year: 1958,
      format: "LP",
      label: "Blue Note",
      catalog_number: "BLP 1577",
      country: "US",
      back_cover_text: null,
      release_notes: "Hard bop album"
    },
    candidates: []
  }));

  assert.equal(result.album?.title, "Blue Train");
  assert.equal(result.confidence, 0.91);
});

test("parseRecognitionOutput rejects incomplete album records", () => {
  assert.throws(
    () => parseRecognitionOutput(JSON.stringify({
      status: "safe_to_buy",
      confidence: 0.91,
      album: { title: "Blue Train" },
      candidates: []
    })),
    /recognition contract/
  );
});
