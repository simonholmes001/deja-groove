import type { Album, ReleaseIdentifier, Track } from "./contracts.js";

export interface AlbumEnrichmentPort {
  enrich(album: Album): Promise<Album>;
}

type DiscogsConfig = {
  token: string;
  userAgent?: string;
  baseURL?: string;
  fetchImpl?: typeof fetch;
};

type DiscogsSearchResponse = {
  results?: DiscogsSearchResult[];
};

type DiscogsSearchResult = {
  id?: number;
  master_id?: number;
  title?: string;
  country?: string;
  year?: string | number;
  format?: string[];
  label?: string[];
  catno?: string;
  barcode?: string[];
  genre?: string[];
  style?: string[];
  thumb?: string;
  cover_image?: string;
  resource_url?: string;
  uri?: string;
};

type DiscogsRelease = {
  id?: number;
  master_id?: number;
  resource_url?: string;
  uri?: string;
  title?: string;
  country?: string;
  year?: number;
  released?: string;
  released_formatted?: string;
  notes?: string;
  data_quality?: string;
  artists?: Array<{ name?: string; anv?: string }>;
  labels?: Array<{ name?: string; catno?: string }>;
  formats?: Array<{ name?: string; qty?: string; descriptions?: string[]; text?: string }>;
  genres?: string[];
  styles?: string[];
  tracklist?: Array<{ position?: string; title?: string; duration?: string; type_?: string }>;
  identifiers?: Array<{ type?: string; value?: string; description?: string }>;
  companies?: Array<{ name?: string; entity_type_name?: string; catno?: string }>;
  images?: Array<{ type?: string; uri?: string; resource_url?: string; uri150?: string }>;
};

export class DiscogsAlbumEnrichment implements AlbumEnrichmentPort {
  private readonly token: string;
  private readonly userAgent: string;
  private readonly baseURL: string;
  private readonly fetchImpl: typeof fetch;

  constructor(config: DiscogsConfig) {
    this.token = config.token;
    this.userAgent = config.userAgent || "DejaGroove/0.1 +https://github.com/simonholmes001/deja-groove";
    this.baseURL = config.baseURL || "https://api.discogs.com";
    this.fetchImpl = config.fetchImpl || fetch;
  }

  async enrich(album: Album): Promise<Album> {
    const searchResult = album.discogs_release_id
      ? null
      : await this.search(album);
    const releaseId = album.discogs_release_id || searchResult?.id?.toString();
    if (!releaseId) {
      return searchResult ? mergeSearchResult(album, searchResult) : album;
    }

    const release = await this.getRelease(releaseId);
    return mergeRelease(mergeSearchResult(album, searchResult), release);
  }

  private async search(album: Album): Promise<DiscogsSearchResult | null> {
    const params = new URLSearchParams({
      type: "release",
      per_page: "5"
    });
    append(params, "artist", album.artist);
    append(params, "release_title", album.title);
    append(params, "format", album.format);
    append(params, "country", album.country);
    append(params, "year", album.release_year?.toString() || album.year?.toString());
    append(params, "label", album.label);
    append(params, "catno", album.catalog_number);
    append(params, "barcode", album.barcode);

    const response = await this.request<DiscogsSearchResponse>(`/database/search?${params.toString()}`);
    return response.results?.find((result) => result.id) ?? null;
  }

  private async getRelease(releaseId: string): Promise<DiscogsRelease> {
    return this.request<DiscogsRelease>(`/releases/${encodeURIComponent(releaseId)}`);
  }

  private async request<T>(path: string): Promise<T> {
    const response = await this.fetchImpl(`${this.baseURL}${path}`, {
      headers: {
        "Authorization": `Discogs token=${this.token}`,
        "User-Agent": this.userAgent,
        "Accept": "application/json"
      }
    });

    if (!response.ok) {
      throw new Error(`Discogs request failed with HTTP ${response.status}.`);
    }
    return await response.json() as T;
  }
}

export class NoopAlbumEnrichment implements AlbumEnrichmentPort {
  async enrich(album: Album): Promise<Album> {
    return album;
  }
}

function mergeSearchResult(album: Album, result: DiscogsSearchResult | null): Album {
  if (!result) return album;
  return {
    ...album,
    discogs_release_id: album.discogs_release_id || result.id?.toString() || null,
    discogs_master_id: album.discogs_master_id || result.master_id?.toString() || null,
    discogs_url: album.discogs_url || result.uri || null,
    discogs_resource_url: album.discogs_resource_url || result.resource_url || null,
    year: album.year ?? parseYear(result.year),
    release_year: album.release_year ?? parseYear(result.year),
    format: album.format || joinList(result.format),
    label: album.label || joinList(result.label),
    catalog_number: album.catalog_number || clean(result.catno),
    country: album.country || clean(result.country),
    barcode: album.barcode || firstNonEmpty(result.barcode),
    cover_image_url: album.cover_image_url || clean(result.cover_image),
    thumbnail_url: album.thumbnail_url || clean(result.thumb),
    genres: preferNonEmpty(album.genres, result.genre),
    styles: preferNonEmpty(album.styles, result.style)
  };
}

function mergeRelease(album: Album, release: DiscogsRelease): Album {
  const labelInfo = firstLabel(release.labels);
  const dates = releaseDates(release);
  const coverImages = releaseImages(release.images);
  return {
    ...album,
    discogs_release_id: release.id?.toString() || album.discogs_release_id || null,
    discogs_master_id: release.master_id?.toString() || album.discogs_master_id || null,
    discogs_url: clean(release.uri) || album.discogs_url || null,
    discogs_resource_url: clean(release.resource_url) || album.discogs_resource_url || null,
    title: clean(album.title) || clean(release.title) || album.title,
    artist: clean(album.artist) || joinArtists(release.artists) || album.artist,
    year: album.year ?? release.year ?? null,
    release_year: release.year ?? album.release_year ?? album.year ?? null,
    release_date: dates.releaseDate || album.release_date || null,
    format: formatSummary(release.formats) || album.format || null,
    label: labelInfo.label || album.label || null,
    catalog_number: labelInfo.catalogNumber || album.catalog_number || null,
    country: clean(release.country) || album.country || null,
    barcode: barcode(release.identifiers) || album.barcode || null,
    cover_image_url: coverImages.front || album.cover_image_url || null,
    thumbnail_url: coverImages.thumbnail || album.thumbnail_url || null,
    back_cover_image_url: coverImages.back || album.back_cover_image_url || null,
    release_notes: clean(release.notes) || album.release_notes || null,
    genres: preferNonEmpty(release.genres, album.genres),
    styles: preferNonEmpty(release.styles, album.styles),
    companies: preferNonEmpty(companies(release.companies), album.companies),
    tracklist: tracklist(release.tracklist),
    identifiers: identifiers(release.identifiers),
    discogs_data_quality: clean(release.data_quality) || album.discogs_data_quality || null
  };
}

function append(params: URLSearchParams, key: string, value: string | undefined | null): void {
  const cleanValue = clean(value);
  if (cleanValue) params.set(key, cleanValue);
}

function clean(value: string | undefined | null): string | null {
  const trimmed = value?.trim();
  return trimmed ? trimmed : null;
}

function firstNonEmpty(values: string[] | undefined): string | null {
  return values?.map(clean).find((value): value is string => Boolean(value)) || null;
}

function joinList(values: string[] | undefined): string | null {
  const cleaned = values?.map(clean).filter((value): value is string => Boolean(value)) || [];
  return cleaned.length > 0 ? cleaned.join(", ") : null;
}

function parseYear(value: string | number | undefined): number | null {
  if (typeof value === "number" && Number.isInteger(value)) return value;
  if (typeof value !== "string") return null;
  const match = value.match(/\b(\d{4})\b/);
  return match ? Number.parseInt(match[1], 10) : null;
}

function preferNonEmpty(preferred: string[] | undefined, fallback: string[] | undefined): string[] {
  if (preferred && preferred.length > 0) return preferred;
  return fallback || [];
}

function firstLabel(labels: DiscogsRelease["labels"]): { label: string | null; catalogNumber: string | null } {
  const first = labels?.find((label) => clean(label.name) || clean(label.catno));
  return {
    label: clean(first?.name),
    catalogNumber: clean(first?.catno)
  };
}

function releaseDates(release: DiscogsRelease): { releaseDate: string | null } {
  return {
    releaseDate: clean(release.released) || clean(release.released_formatted) || release.year?.toString() || null
  };
}

function releaseImages(images: DiscogsRelease["images"]): { front: string | null; back: string | null; thumbnail: string | null } {
  const primary = images?.find((image) => image.type?.toLowerCase() === "primary") ?? images?.[0];
  const secondary = images?.find((image) => image.type?.toLowerCase() === "secondary");
  return {
    front: clean(primary?.uri) || clean(primary?.resource_url),
    back: clean(secondary?.uri) || clean(secondary?.resource_url),
    thumbnail: clean(primary?.uri150) || clean(primary?.uri) || clean(primary?.resource_url)
  };
}

function joinArtists(artists: DiscogsRelease["artists"]): string | null {
  const names = artists?.map((artist) => clean(artist.anv) || clean(artist.name)).filter((name): name is string => Boolean(name)) || [];
  return names.length > 0 ? names.join(", ") : null;
}

function formatSummary(formats: DiscogsRelease["formats"]): string | null {
  const values = formats?.map((format) => {
    const parts = [
      clean(format.name),
      format.descriptions?.map(clean).filter((value): value is string => Boolean(value)).join(", "),
      clean(format.text)
    ].filter((value): value is string => Boolean(value));
    return parts.join(" - ");
  }).filter(Boolean) || [];
  return values.length > 0 ? values.join("; ") : null;
}

function barcode(identifiers: DiscogsRelease["identifiers"]): string | null {
  return identifiers
    ?.filter((identifier) => identifier.type?.toLowerCase() === "barcode")
    .map((identifier) => clean(identifier.value))
    .find((value): value is string => Boolean(value)) || null;
}

function identifiers(values: DiscogsRelease["identifiers"]): ReleaseIdentifier[] {
  return values?.map((identifier) => ({
    type: clean(identifier.type) || "Identifier",
    value: clean(identifier.value),
    description: clean(identifier.description)
  })).filter((identifier) => identifier.value || identifier.description) || [];
}

function companies(values: DiscogsRelease["companies"]): string[] {
  return values?.map((company) => {
    const name = clean(company.name);
    if (!name) return null;
    const role = clean(company.entity_type_name);
    const catno = clean(company.catno);
    return [
      role ? `${role}: ${name}` : name,
      catno
    ].filter(Boolean).join(" - ");
  }).filter((value): value is string => Boolean(value)) || [];
}

function tracklist(values: DiscogsRelease["tracklist"]): Track[] {
  return values
    ?.filter((track) => track.type_ === undefined || track.type_ === "track")
    .map((track) => ({
      position: clean(track.position),
      title: clean(track.title) || "Untitled",
      duration: clean(track.duration)
    })) || [];
}
