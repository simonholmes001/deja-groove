import assert from "node:assert/strict";
import test from "node:test";
import { CachedAlbumEnrichment } from "../src/cachedEnrichment.js";
import type { Album } from "../src/contracts.js";
import type { AlbumEnrichmentPort } from "../src/discogs.js";

test("CachedAlbumEnrichment reuses successful enrichment for the same album identity", async () => {
  const inner = new CountingEnrichment((album) => ({ ...album, label: "Impulse!" }));
  const enrichment = new CachedAlbumEnrichment({
    inner,
    now: () => 1000,
    ttlMs: 60_000
  });

  const first = await enrichment.enrich(baseAlbum());
  const second = await enrichment.enrich({
    ...baseAlbum(),
    format: "Vinyl LP"
  });

  assert.equal(first.label, "Impulse!");
  assert.equal(second.label, "Impulse!");
  assert.equal(inner.calls, 1);
});

test("CachedAlbumEnrichment deduplicates concurrent enrichment for the same key", async () => {
  let resolve: ((album: Album) => void) | undefined;
  const inner = new CountingEnrichment((album) => new Promise<Album>((done) => {
    resolve = done;
  }).then(() => ({ ...album, label: "Blue Note" })));
  const enrichment = new CachedAlbumEnrichment({
    inner,
    now: () => 1000,
    ttlMs: 60_000
  });

  const first = enrichment.enrich(baseAlbum());
  const second = enrichment.enrich(baseAlbum());
  resolve?.(baseAlbum());

  const [firstAlbum, secondAlbum] = await Promise.all([first, second]);

  assert.equal(firstAlbum.label, "Blue Note");
  assert.equal(secondAlbum.label, "Blue Note");
  assert.equal(inner.calls, 1);
});

test("CachedAlbumEnrichment refreshes expired entries", async () => {
  let now = 1000;
  let labelIndex = 0;
  const inner = new CountingEnrichment((album) => {
    labelIndex += 1;
    return { ...album, label: `call-${labelIndex}` };
  });
  const enrichment = new CachedAlbumEnrichment({
    inner,
    now: () => now,
    ttlMs: 10
  });

  const first = await enrichment.enrich(baseAlbum());
  now = 1011;
  const second = await enrichment.enrich(baseAlbum());

  assert.equal(first.label, "call-1");
  assert.equal(second.label, "call-2");
  assert.equal(inner.calls, 2);
});

test("CachedAlbumEnrichment does not cache failed enrichment", async () => {
  const inner = new CountingEnrichment((album) => {
    if (inner.calls === 1) throw new Error("provider unavailable");
    return { ...album, label: "ECM" };
  });
  const enrichment = new CachedAlbumEnrichment({
    inner,
    now: () => 1000,
    ttlMs: 60_000
  });

  await assert.rejects(() => enrichment.enrich(baseAlbum()), /provider unavailable/);
  const album = await enrichment.enrich(baseAlbum());

  assert.equal(album.label, "ECM");
  assert.equal(inner.calls, 2);
});

class CountingEnrichment implements AlbumEnrichmentPort {
  calls = 0;

  constructor(private readonly enrichImpl: (album: Album) => Album | Promise<Album>) {}

  async enrich(album: Album): Promise<Album> {
    this.calls += 1;
    return await this.enrichImpl(album);
  }
}

function baseAlbum(): Album {
  return {
    mbid: null,
    discogs_release_id: "release-1",
    title: "Journey In Satchidananda",
    artist: "Alice Coltrane",
    year: 1971,
    first_release_year: null,
    release_year: null,
    format: "LP",
    label: null,
    catalog_number: null,
    country: null,
    back_cover_text: null,
    release_notes: null
  };
}
