import type { HttpRequest } from "@azure/functions";

const maxImageBytes = 8 * 1024 * 1024;

export type ScanImage = {
  data: Buffer;
  mimeType: "image/jpeg" | "image/png" | "image/webp";
};

export async function readScanImage(request: HttpRequest): Promise<ScanImage> {
  const contentType = request.headers.get("content-type") ?? "";
  if (!contentType.toLowerCase().includes("multipart/form-data")) {
    throw new RequestError(415, "unsupported_media_type", "Use multipart/form-data with an image file.");
  }

  const form = await request.formData();
  const value = form.get("image");
  if (!(value instanceof File)) {
    throw new RequestError(400, "missing_image", "Multipart field 'image' is required.");
  }

  const mimeType = normalizeMimeType(value.type);
  const bytes = Buffer.from(await value.arrayBuffer());
  if (bytes.length === 0) {
    throw new RequestError(400, "empty_image", "Image file must not be empty.");
  }
  if (bytes.length > maxImageBytes) {
    throw new RequestError(413, "image_too_large", "Image file must be 8 MB or smaller.");
  }

  return { data: bytes, mimeType };
}

function normalizeMimeType(mimeType: string): ScanImage["mimeType"] {
  switch (mimeType.toLowerCase()) {
    case "image/jpeg":
    case "image/jpg":
      return "image/jpeg";
    case "image/png":
      return "image/png";
    case "image/webp":
      return "image/webp";
    default:
      throw new RequestError(415, "unsupported_image_type", "Image must be JPEG, PNG, or WEBP.");
  }
}

export class RequestError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
    readonly retryable = false
  ) {
    super(message);
  }
}
