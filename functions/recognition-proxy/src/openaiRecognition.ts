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
  "Identify the vinyl record album shown in this cover image.",
  "Return only JSON matching this schema:",
  "{",
  "  \"status\": \"safe_to_buy\" | \"ambiguous\" | \"no_match\",",
  "  \"confidence\": number,",
  "  \"album\": {",
  "    \"title\": string, \"artist\": string, \"year\": number|null,",
  "    \"first_release_year\": number|null, \"release_year\": number|null,",
  "    \"format\": string|null, \"label\": string|null, \"catalog_number\": string|null,",
  "    \"country\": string|null, \"back_cover_text\": string|null, \"release_notes\": string|null,",
  "    \"mbid\": string|null, \"discogs_release_id\": string|null",
  "  } | null,",
  "  \"candidates\": [same album shape]",
  "}",
  "Use status safe_to_buy for one strong match, ambiguous for multiple plausible matches, and no_match when the cover is not recognizable.",
  "Use year as the best available release year, first_release_year for the album's original first release, and release_year for this visible pressing/version.",
  "Only transcribe back_cover_text when the provided image actually shows readable back-cover text; otherwise return null.",
  "Do not invent MBID or Discogs IDs; use null unless you are certain."
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
  const parsed = JSON.parse(outputText) as unknown;
  if (!isRecognitionResult(parsed)) {
    throw new Error("OpenAI response did not match the recognition contract.");
  }
  return parsed;
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
    && optionalString(value.back_cover_text)
    && optionalString(value.release_notes)
    && optionalString(value.mbid)
    && optionalString(value.discogs_release_id);
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

const albumSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    mbid: { type: ["string", "null"] },
    discogs_release_id: { type: ["string", "null"] },
    title: { type: "string" },
    artist: { type: "string" },
    year: { type: ["number", "null"] },
    first_release_year: { type: ["number", "null"] },
    release_year: { type: ["number", "null"] },
    format: { type: ["string", "null"] },
    label: { type: ["string", "null"] },
    catalog_number: { type: ["string", "null"] },
    country: { type: ["string", "null"] },
    back_cover_text: { type: ["string", "null"] },
    release_notes: { type: ["string", "null"] }
  },
  required: [
    "mbid",
    "discogs_release_id",
    "title",
    "artist",
    "year",
    "first_release_year",
    "release_year",
    "format",
    "label",
    "catalog_number",
    "country",
    "back_cover_text",
    "release_notes"
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
