export type Album = {
  mbid?: string | null;
  discogs_release_id?: string | null;
  discogs_master_id?: string | null;
  discogs_url?: string | null;
  discogs_resource_url?: string | null;
  title: string;
  artist: string;
  year?: number | null;
  first_release_year?: number | null;
  release_year?: number | null;
  first_release_date?: string | null;
  release_date?: string | null;
  format?: string | null;
  label?: string | null;
  catalog_number?: string | null;
  country?: string | null;
  barcode?: string | null;
  cover_image_url?: string | null;
  thumbnail_url?: string | null;
  back_cover_image_url?: string | null;
  back_cover_text?: string | null;
  release_notes?: string | null;
  genres?: string[];
  styles?: string[];
  companies?: string[];
  tracklist?: Track[];
  identifiers?: ReleaseIdentifier[];
  discogs_data_quality?: string | null;
};

export type Track = {
  position?: string | null;
  title: string;
  duration?: string | null;
};

export type ReleaseIdentifier = {
  type: string;
  value?: string | null;
  description?: string | null;
};

export type ScanResponse = {
  status: "safe_to_buy" | "ambiguous" | "no_match";
  confidence: number;
  album: Album | null;
  candidates: Album[];
  request_id: string;
};

export type ApiError = {
  error: {
    code: string;
    message: string;
    retryable: boolean;
    request_id: string;
  };
};

export type RecognitionCandidate = Album & {
  confidence?: number | null;
};

export type RecognitionResult = {
  status: "safe_to_buy" | "ambiguous" | "no_match";
  confidence: number;
  album?: Album | null;
  candidates?: RecognitionCandidate[];
};
