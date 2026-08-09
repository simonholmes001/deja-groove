import fs from "node:fs";
import path from "node:path";

const [, , imagePath, outputPath = "/tmp/openai-direct-full-schema-request.json"] = process.argv;

if (!imagePath) {
  console.error("Usage: node scripts/build-openai-direct-request.mjs <image-path> [output-json-path]");
  process.exit(2);
}

if (!fs.existsSync(imagePath)) {
  console.error(`Image file does not exist: ${imagePath}`);
  process.exit(2);
}

const sourcePath = path.resolve("functions/recognition-proxy/src/openaiRecognition.ts");
const source = fs.readFileSync(sourcePath, "utf8");
const schemaBlock = source.match(
  /const albumSchema = ([\s\S]*?) as const;\n\nconst recognitionSchema = ([\s\S]*?) as const;/
);

if (!schemaBlock) {
  throw new Error("Could not extract recognition schema.");
}

const albumSchema = Function(`return (${schemaBlock[1]});`)();
const recognitionSchema = Function("albumSchema", `return (${schemaBlock[2]});`)(albumSchema);
const imageBase64 = fs.readFileSync(imagePath).toString("base64");

const body = {
  model: "gpt-5.6-terra",
  input: [
    {
      role: "user",
      content: [
        {
          type: "input_text",
          text: [
            "Identify the vinyl record album from the cover image.",
            "Return JSON only, using the supplied schema.",
            "Set safe_to_buy for one strong match, ambiguous for multiple plausible matches, or no_match if unrecognizable.",
            "Prefer exact visible cover evidence over general music knowledge.",
            "Transcribe exact visible title, artist, label, catalog number, spine text, format/media type, country/language hints, and barcode if present.",
            "Use null for unknown years, labels, catalog numbers, countries, formats, barcodes, or visible text.",
            "Do not return Discogs, MusicBrainz, artwork, tracklist, identifier, or release-note metadata.",
            "Only identify the likely album; external enrichment will fill detailed release metadata."
          ].join("\n")
        },
        {
          type: "input_image",
          image_url: `data:image/jpeg;base64,${imageBase64}`,
          detail: "low"
        }
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
};

fs.writeFileSync(outputPath, JSON.stringify(body));
console.log(`Wrote ${outputPath}`);
