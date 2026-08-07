export type Album = {
  mbid?: string | null;
  discogs_release_id?: string | null;
  title: string;
  artist: string;
  year?: number | null;
  first_release_year?: number | null;
  release_year?: number | null;
  format?: string | null;
  label?: string | null;
  catalog_number?: string | null;
  country?: string | null;
  back_cover_text?: string | null;
  release_notes?: string | null;
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
