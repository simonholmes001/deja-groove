import type { Album } from "./contracts.js";
import type { AlbumEnrichmentPort } from "./discogs.js";

type CachedAlbumEnrichmentConfig = {
  inner: AlbumEnrichmentPort;
  ttlMs?: number;
  maxEntries?: number;
  now?: () => number;
};

type CacheEntry = {
  expiresAt: number;
  album: Album;
};

const defaultTtlMs = 24 * 60 * 60 * 1000;
const defaultMaxEntries = 500;

export class CachedAlbumEnrichment implements AlbumEnrichmentPort {
  private readonly inner: AlbumEnrichmentPort;
  private readonly ttlMs: number;
  private readonly maxEntries: number;
  private readonly now: () => number;
  private readonly cache = new Map<string, CacheEntry>();
  private readonly pending = new Map<string, Promise<Album>>();

  constructor(config: CachedAlbumEnrichmentConfig) {
    this.inner = config.inner;
    this.ttlMs = positiveInteger(config.ttlMs, defaultTtlMs);
    this.maxEntries = positiveInteger(config.maxEntries, defaultMaxEntries);
    this.now = config.now || Date.now;
  }

  async enrich(album: Album): Promise<Album> {
    const key = cacheKey(album);
    if (!key || this.ttlMs <= 0 || this.maxEntries <= 0) {
      return await this.inner.enrich(album);
    }

    const cached = this.get(key);
    if (cached) return cached;

    const existing = this.pending.get(key);
    if (existing) return await existing;

    const operation = this.inner.enrich(album)
      .then((enriched) => {
        this.set(key, enriched);
        return enriched;
      })
      .finally(() => {
        this.pending.delete(key);
      });
    this.pending.set(key, operation);
    return await operation;
  }

  private get(key: string): Album | null {
    const entry = this.cache.get(key);
    if (!entry) return null;
    if (entry.expiresAt <= this.now()) {
      this.cache.delete(key);
      return null;
    }

    this.cache.delete(key);
    this.cache.set(key, entry);
    return entry.album;
  }

  private set(key: string, album: Album): void {
    this.cache.set(key, {
      album,
      expiresAt: this.now() + this.ttlMs
    });
    while (this.cache.size > this.maxEntries) {
      const oldestKey = this.cache.keys().next().value as string | undefined;
      if (!oldestKey) break;
      this.cache.delete(oldestKey);
    }
  }
}

function cacheKey(album: Album): string | null {
  if (clean(album.discogs_release_id)) return `discogs:${clean(album.discogs_release_id)}`;
  if (clean(album.mbid)) return `mbid:${clean(album.mbid)}`;

  const identity = [
    normalize(album.artist),
    normalize(album.title),
    album.release_year?.toString() || album.year?.toString() || "",
    normalize(album.format),
    normalize(album.catalog_number)
  ];
  if (!identity[0] || !identity[1]) return null;
  return `identity:${identity.join("|")}`;
}

function positiveInteger(value: number | undefined, fallback: number): number {
  return typeof value === "number" && Number.isFinite(value) && value >= 0
    ? Math.floor(value)
    : fallback;
}

function clean(value: string | undefined | null): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function normalize(value: string | undefined | null): string {
  return (value || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .toLowerCase();
}
