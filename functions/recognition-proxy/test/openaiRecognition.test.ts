import assert from "node:assert/strict";
import test from "node:test";
import { parseRecognitionOutput, RecognitionOutputError } from "../src/openaiRecognition.js";

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
      first_release_date: null,
      release_date: "1958",
      format: "LP",
      label: "Blue Note",
      catalog_number: "BLP 1577",
      country: "US",
      barcode: null,
      cover_image_url: null,
      thumbnail_url: null,
      back_cover_image_url: null,
      back_cover_text: null,
      release_notes: "Hard bop album",
      genres: ["Jazz"],
      styles: ["Hard Bop"],
      companies: ["Recorded At: Van Gelder Studio"],
      tracklist: [
        { position: "A1", title: "Blue Train", duration: "10:43" }
      ],
      identifiers: [
        { type: "Matrix / Runout", value: "BN-LP-1577-A", description: "Side A" }
      ],
      discogs_data_quality: null,
      discogs_master_id: "456",
      discogs_url: "https://www.discogs.com/release/123",
      discogs_resource_url: "https://api.discogs.com/releases/123"
    },
    candidates: []
  }));

  assert.equal(result.album?.title, "Blue Train");
  assert.equal(result.confidence, 0.91);
});

test("parseRecognitionOutput accepts the reduced scan-time recognition contract", () => {
  const result = parseRecognitionOutput(JSON.stringify({
    status: "safe_to_buy",
    confidence: 0.93,
    album: {
      title: "A Love Supreme",
      artist: "John Coltrane",
      year: 1965,
      format: "Vinyl",
      label: "Impulse!",
      catalog_number: "AS-77",
      country: "US",
      barcode: null,
      visible_title: "A Love Supreme",
      visible_artist: "John Coltrane",
      visible_spine_text: "AS-77 John Coltrane A Love Supreme",
      visible_text: "Impulse! AS-77 Stereo",
      media_type_hint: "Vinyl"
    },
    candidates: []
  }));

  assert.equal(result.album?.title, "A Love Supreme");
  assert.equal(result.album?.artist, "John Coltrane");
  assert.equal(result.album?.label, "Impulse!");
  assert.equal(result.album?.visible_spine_text, "AS-77 John Coltrane A Love Supreme");
  assert.equal(result.album?.tracklist, undefined);
});

test("parseRecognitionOutput rejects incomplete album records", () => {
  const error = captureRecognitionOutputError(() => parseRecognitionOutput(JSON.stringify({
    status: "safe_to_buy",
    confidence: 0.91,
    album: { title: "Blue Train" },
    candidates: []
  })));

  assert.match(error.message, /recognition contract/);
  assert.equal(error.outputLength > 0, true);
});

test("parseRecognitionOutput reports invalid JSON without logging payload content", () => {
  const error = captureRecognitionOutputError(() => parseRecognitionOutput("{"));

  assert.match(error.message, /not valid JSON/);
  assert.equal(error.outputLength, 1);
});

function captureRecognitionOutputError(action: () => void): RecognitionOutputError {
  try {
    action();
  } catch (error) {
    assert.ok(error instanceof RecognitionOutputError);
    return error;
  }

  assert.fail("Expected RecognitionOutputError.");
}
