import type { Album } from "./contracts.js";
import type { AlbumEnrichmentOptions, AlbumEnrichmentPort } from "./discogs.js";

type ArtworkFallbackConfig = {
  primary: AlbumEnrichmentPort;
  fetchImpl?: typeof fetch;
  coverArtArchiveBaseURL?: string;
  itunesBaseURL?: string;
};

type CoverArtArchiveResponse = {
  images?: CoverArtArchiveImage[];
};

type CoverArtArchiveImage = {
  image?: string;
  thumbnails?: Record<string, string | undefined>;
  front?: boolean;
  back?: boolean;
  types?: string[];
  approved?: boolean;
};

type ITunesSearchResponse = {
  results?: ITunesAlbumResult[];
};

type ITunesAlbumResult = {
  artistName?: string;
  collectionName?: string;
  collectionId?: number;
  collectionViewUrl?: string;
  artworkUrl100?: string;
  releaseDate?: string;
};

type ArtworkCandidate = {
  front: string | null;
  thumbnail: string | null;
  back: string | null;
};

export class ArtworkFallbackAlbumEnrichment implements AlbumEnrichmentPort {
  private readonly primary: AlbumEnrichmentPort;
  private readonly fetchImpl: typeof fetch;
  private readonly coverArtArchiveBaseURL: string;
  private readonly itunesBaseURL: string;

  constructor(config: ArtworkFallbackConfig) {
    this.primary = config.primary;
    this.fetchImpl = config.fetchImpl || fetch;
    this.coverArtArchiveBaseURL = config.coverArtArchiveBaseURL || "https://coverartarchive.org";
    this.itunesBaseURL = config.itunesBaseURL || "https://itunes.apple.com";
  }

  async enrich(album: Album, options: AlbumEnrichmentOptions = {}): Promise<Album> {
    const enriched = await this.primary.enrich(album, options);
    if (hasCompleteArtwork(enriched) && hasListeningLink(enriched)) return enriched;

    const withCoverArtArchive = await this.tryApplyCoverArtArchive(enriched, options);
    if (hasFrontArtwork(withCoverArtArchive) && hasBackArtwork(withCoverArtArchive) && hasListeningLink(withCoverArtArchive)) {
      return withCoverArtArchive;
    }

    return await this.tryApplyITunes(withCoverArtArchive, options);
  }

  private async tryApplyCoverArtArchive(album: Album, options: AlbumEnrichmentOptions): Promise<Album> {
    try {
      return await this.applyCoverArtArchive(album, options);
    } catch (error) {
      logFallbackFailure("Cover Art Archive", error, options);
      return album;
    }
  }

  private async tryApplyITunes(album: Album, options: AlbumEnrichmentOptions): Promise<Album> {
    try {
      return await this.applyITunes(album, options);
    } catch (error) {
      logFallbackFailure("iTunes Search", error, options);
      return album;
    }
  }

  private async applyCoverArtArchive(album: Album, options: AlbumEnrichmentOptions): Promise<Album> {
    if (!album.mbid || hasCompleteArtwork(album)) return album;

    const artwork = await this.fetchCoverArtArchiveArtwork(album.mbid, options);
    if (!artwork) return album;

    return {
      ...album,
      cover_image_url: album.cover_image_url || artwork.front,
      thumbnail_url: album.thumbnail_url || artwork.thumbnail || artwork.front,
      back_cover_image_url: album.back_cover_image_url || artwork.back
    };
  }

  private async fetchCoverArtArchiveArtwork(mbid: string, options: AlbumEnrichmentOptions): Promise<ArtworkCandidate | null> {
    const releaseArtwork = await this.fetchCoverArtArchivePath(`/release/${encodeURIComponent(mbid)}`, options);
    if (releaseArtwork) return releaseArtwork;
    return await this.fetchCoverArtArchivePath(`/release-group/${encodeURIComponent(mbid)}`, options);
  }

  private async fetchCoverArtArchivePath(path: string, options: AlbumEnrichmentOptions): Promise<ArtworkCandidate | null> {
    const response = await this.fetchImpl(`${this.coverArtArchiveBaseURL}${path}`, {
      signal: options.signal,
      headers: { "Accept": "application/json" }
    });
    if (response.status === 404) return null;
    if (!response.ok) {
      logFallbackNonOkResponse("Cover Art Archive", response.status, options);
      return null;
    }

    const body = await response.json() as CoverArtArchiveResponse;
    const images = body.images || [];
    const front = selectImage(images, "front");
    const back = selectImage(images, "back");
    if (!front && !back) return null;
    return {
      front: bestOriginal(front),
      thumbnail: bestThumbnail(front),
      back: bestOriginal(back)
    };
  }

  private async applyITunes(album: Album, options: AlbumEnrichmentOptions): Promise<Album> {
    const result = await this.fetchITunesAlbum(album, options);
    if (!result) return album;

    const artwork = clean(result.artworkUrl100);
    const listeningLink = clean(result.collectionViewUrl);
    const currentLinks = album.listening_links || [];

    return {
      ...album,
      cover_image_url: album.cover_image_url || (artwork ? resizeITunesArtwork(artwork, 600) : null),
      thumbnail_url: album.thumbnail_url || (artwork ? resizeITunesArtwork(artwork, 100) : null),
      listening_links: currentLinks.length > 0 || !listeningLink
        ? currentLinks
        : [{
            provider: "Apple Music",
            url: listeningLink,
            catalog_id: result.collectionId?.toString() || null
          }]
    };
  }

  private async fetchITunesAlbum(album: Album, options: AlbumEnrichmentOptions): Promise<ITunesAlbumResult | null> {
    const term = [album.artist, album.title].filter(Boolean).join(" ");
    const params = new URLSearchParams({
      term,
      media: "music",
      entity: "album",
      limit: "10"
    });
    const response = await this.fetchImpl(`${this.itunesBaseURL}/search?${params.toString()}`, {
      signal: options.signal,
      headers: { "Accept": "application/json" }
    });
    if (!response.ok) {
      logFallbackNonOkResponse("iTunes Search", response.status, options);
      return null;
    }

    const body = await response.json() as ITunesSearchResponse;
    const results = body.results || [];
    return bestITunesMatch(album, results);
  }
}

function hasCompleteArtwork(album: Album): boolean {
  return hasFrontArtwork(album) && hasBackArtwork(album);
}

function hasFrontArtwork(album: Album): boolean {
  return Boolean(clean(album.cover_image_url) || clean(album.thumbnail_url));
}

function hasBackArtwork(album: Album): boolean {
  return Boolean(clean(album.back_cover_image_url));
}

function hasListeningLink(album: Album): boolean {
  return (album.listening_links || []).some((link) => clean(link.url));
}

function selectImage(images: CoverArtArchiveImage[], kind: "front" | "back"): CoverArtArchiveImage | null {
  return images.find((image) => isKind(image, kind) && image.approved !== false)
    ?? images.find((image) => isKind(image, kind))
    ?? null;
}

function isKind(image: CoverArtArchiveImage, kind: "front" | "back"): boolean {
  if (kind === "front" && image.front) return true;
  if (kind === "back" && image.back) return true;
  return image.types?.some((type) => type.toLowerCase() === kind) ?? false;
}

function bestOriginal(image: CoverArtArchiveImage | null): string | null {
  if (!image) return null;
  return clean(image.image) || bestThumbnail(image);
}

function bestThumbnail(image: CoverArtArchiveImage | null): string | null {
  if (!image) return null;
  return clean(image.thumbnails?.["500"])
    || clean(image.thumbnails?.large)
    || clean(image.thumbnails?.["250"])
    || clean(image.thumbnails?.small)
    || clean(image.image);
}

function bestITunesMatch(album: Album, results: ITunesAlbumResult[]): ITunesAlbumResult | null {
  const normalizedTitle = normalize(album.title);
  const normalizedArtist = normalize(album.artist);
  return results.find((result) =>
    normalize(result.collectionName) === normalizedTitle
      && normalize(result.artistName) === normalizedArtist)
    ?? results.find((result) => normalize(result.collectionName) === normalizedTitle)
    ?? results[0]
    ?? null;
}

function resizeITunesArtwork(url: string, size: number): string {
  return url.replace(/\/\d+x\d+[^/]*\.(jpg|jpeg|png)$/i, `/${size}x${size}bb.$1`);
}

function normalize(value: string | undefined | null): string {
  return (value || "")
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^\p{L}\p{N}]+/gu, " ")
    .trim()
    .toLowerCase();
}

function clean(value: string | undefined | null): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function logFallbackFailure(provider: string, error: unknown, options: AlbumEnrichmentOptions): void {
  const message = error instanceof Error ? error.message : String(error);
  options.logger?.warn(`Artwork fallback provider ${provider} failed: ${message}`);
}

function logFallbackNonOkResponse(provider: string, status: number, options: AlbumEnrichmentOptions): void {
  options.logger?.warn(`Artwork fallback provider ${provider} returned HTTP ${status}.`);
}
