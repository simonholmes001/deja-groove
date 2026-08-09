import OpenAI from "openai";
import type { Album, RecognitionResult } from "./contracts.js";
import type { ScanImage } from "./http.js";

export interface RecognitionPort {
  recognize(image: ScanImage): Promise<RecognitionResult>;
}

type OpenAIConfig = {
  apiKey: string;
  model: string;
};

const defaultPrompt = [
  "Identify the vinyl record album from the cover image.",
  "Return JSON only, using the supplied schema.",
  "Set safe_to_buy for one strong match, ambiguous for multiple plausible matches, or no_match if unrecognizable.",
  "Prefer exact visible cover evidence over general music knowledge.",
  "Transcribe exact visible title, artist, label, catalog number, spine text, format/media type, country/language hints, and barcode if present.",
  "Use null for unknown years, labels, catalog numbers, countries, formats, barcodes, or visible text.",
  "Do not return Discogs, MusicBrainz, artwork, tracklist, identifier, or release-note metadata.",
  "Only identify the likely album; external enrichment will fill detailed release metadata."
].join("\n");

export class OpenAIAlbumRecognition implements RecognitionPort {
  private readonly client: OpenAI;
  private readonly model: string;

  constructor(config: OpenAIConfig) {
    this.client = new OpenAI({ apiKey: config.apiKey });
    this.model = config.model;
  }

  async recognize(image: ScanImage): Promise<RecognitionResult> {
    const imageUrl = `data:${image.mimeType};base64,${image.data.toString("base64")}`;
    const response = await this.client.responses.create({
      model: this.model,
      input: [
        {
          role: "user",
          content: [
            { type: "input_text", text: defaultPrompt },
            { type: "input_image", image_url: imageUrl, detail: "low" }
          ]
        }
      ],
      text: {
        format: {
          type: "json_schema",
          name: "album_recognition",
          schema: recognitionSchema,
          strict: true
        }
      }
    });

    return parseRecognitionOutput(response.output_text);
  }
}

export function parseRecognitionOutput(outputText: string): RecognitionResult {
  let parsed: unknown;
  try {
    parsed = JSON.parse(outputText) as unknown;
  } catch (error) {
    throw new RecognitionOutputError(
      "OpenAI response was not valid JSON.",
      outputText.length,
      error);
  }

  if (!isRecognitionResult(parsed)) {
    throw new RecognitionOutputError(
      "OpenAI response did not match the recognition contract.",
      outputText.length);
  }
  return parsed;
}

export class RecognitionOutputError extends Error {
  constructor(
    message: string,
    readonly outputLength: number,
    cause?: unknown
  ) {
    super(message, { cause });
    this.name = "RecognitionOutputError";
  }
}

function isRecognitionResult(value: unknown): value is RecognitionResult {
  if (!isRecord(value)) return false;
  if (!["safe_to_buy", "ambiguous", "no_match"].includes(String(value.status))) return false;
  if (typeof value.confidence !== "number") return false;
  if (value.album !== null && value.album !== undefined && !isAlbum(value.album)) return false;
  if (!Array.isArray(value.candidates) || !value.candidates.every(isAlbum)) return false;
  return true;
}

function isAlbum(value: unknown): value is Album {
  return isRecord(value)
    && typeof value.title === "string"
    && typeof value.artist === "string"
    && optionalNumber(value.year)
    && optionalNumber(value.first_release_year)
    && optionalNumber(value.release_year)
    && optionalString(value.format)
    && optionalString(value.label)
    && optionalString(value.catalog_number)
    && optionalString(value.country)
    && optionalString(value.visible_title)
    && optionalString(value.visible_artist)
    && optionalString(value.visible_spine_text)
    && optionalString(value.visible_text)
    && optionalString(value.media_type_hint)
    && optionalString(value.back_cover_text)
    && optionalString(value.release_notes)
    && optionalString(value.mbid)
    && optionalString(value.discogs_release_id)
    && optionalString(value.discogs_master_id)
    && optionalString(value.discogs_url)
    && optionalString(value.discogs_resource_url)
    && optionalString(value.first_release_date)
    && optionalString(value.release_date)
    && optionalString(value.barcode)
    && optionalString(value.cover_image_url)
    && optionalString(value.thumbnail_url)
    && optionalString(value.back_cover_image_url)
    && optionalString(value.discogs_data_quality)
    && optionalStringArray(value.genres)
    && optionalStringArray(value.styles)
    && optionalStringArray(value.companies)
    && optionalTrackArray(value.tracklist)
    && optionalIdentifierArray(value.identifiers);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function optionalString(value: unknown): boolean {
  return value === undefined || value === null || typeof value === "string";
}

function optionalNumber(value: unknown): boolean {
  return value === undefined || value === null || typeof value === "number";
}

function optionalStringArray(value: unknown): boolean {
  return value === undefined
    || (Array.isArray(value) && value.every((item) => typeof item === "string"));
}

function optionalTrackArray(value: unknown): boolean {
  return value === undefined
    || (Array.isArray(value) && value.every((track) => isRecord(track)
      && optionalString(track.position)
      && typeof track.title === "string"
      && optionalString(track.duration)));
}

function optionalIdentifierArray(value: unknown): boolean {
  return value === undefined
    || (Array.isArray(value) && value.every((identifier) => isRecord(identifier)
      && typeof identifier.type === "string"
      && optionalString(identifier.value)
      && optionalString(identifier.description)));
}

const albumSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    title: { type: "string" },
    artist: { type: "string" },
    year: { type: ["number", "null"] },
    format: { type: ["string", "null"] },
    label: { type: ["string", "null"] },
    catalog_number: { type: ["string", "null"] },
    country: { type: ["string", "null"] },
    barcode: { type: ["string", "null"] },
    visible_title: { type: ["string", "null"] },
    visible_artist: { type: ["string", "null"] },
    visible_spine_text: { type: ["string", "null"] },
    visible_text: { type: ["string", "null"] },
    media_type_hint: { type: ["string", "null"] }
  },
  required: [
    "title",
    "artist",
    "year",
    "format",
    "label",
    "catalog_number",
    "country",
    "barcode",
    "visible_title",
    "visible_artist",
    "visible_spine_text",
    "visible_text",
    "media_type_hint"
  ]
} as const;

const recognitionSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    status: { type: "string", enum: ["safe_to_buy", "ambiguous", "no_match"] },
    confidence: { type: "number", minimum: 0, maximum: 1 },
    album: {
      anyOf: [
        albumSchema,
        { type: "null" }
      ]
    },
    candidates: {
      type: "array",
      items: albumSchema,
      maxItems: 5
    }
  },
  required: ["status", "confidence", "album", "candidates"]
} as const;
