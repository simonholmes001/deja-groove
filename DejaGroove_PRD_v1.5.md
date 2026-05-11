# 🎵 Déjà Groove

**Product Requirements Document**
Version 1.5 · May 2026 · CONFIDENTIAL  
iOS · Azure Cloud · GPT-5.4 Vision (OpenAI)

---

## 1. Scope of v1.5 Update

This document is a focused revision of v1.4. Product scope remains unchanged. v1.5 resolves architectural and requirements ambiguities and adds missing API contract detail for implementation readiness.

---

## 2. Key Changes from v1.4

### 2.1 Unified Latency + Timeout Policy

Replaced conflicting timeout values with one policy:

- **End-to-end UX target:** P95 scan-to-result under **3.0 s** on typical 4G/Wi-Fi.
- **Client request timeout:** **6.0 s hard timeout** per scan request.
- **Server orchestration budget:** **5.0 s internal budget** (leaves transport/UI margin).
- **Retry behavior:** one automatic retry only for transient network failures; no retry on deterministic model failures.
- **User-facing failure state:** if timeout budget is exceeded, show non-blocking error toast with explicit retry action.

### 2.2 Scan Payload Strategy (Performance)

v1.4 used base64 JSON payloads only. v1.5 defines preferred transport:

- **Preferred:** `multipart/form-data` binary JPEG upload to scan endpoint.
- **Fallback:** base64 JSON accepted only for backward compatibility during migration.
- **Capture target:** 1080p JPEG with quality tuned to keep payload typically below 1.5 MB.
- **Reason:** lower overhead than base64, improved latency and lower bandwidth cost.

### 2.3 AI Accuracy Expectation Reframed

v1.4 goal wording implied universal reliability. v1.5 reframes to measurable behavior:

- Replace “identify any album cover reliably” with:
  - “Identify common retail/reissue covers with high reliability under normal lighting.”
- Add acceptance test sets:
  - Clean frontal covers
  - Angled covers
  - Partial occlusion
  - Worn/aged sleeves
  - Glare/low light
- Ship gate: accuracy target must be met per test set, not only in aggregate.

### 2.4 Spotify Data Field Clarification

v1.5 clarifies enrichment fields:

- Spotify is used for **genres, popularity, related artists, cover art variants**.
- “Album bio” is not assumed as a guaranteed Spotify field.
- If biography-style text is shown, source must be explicit and nullable.

### 2.5 Identity Platform Decision Note

v1.5 adds a risk checkpoint before full implementation lock:

- Confirm long-term identity provider path (Azure AD B2C successor posture and migration path) before M2 freeze.
- Keep auth abstraction in client/backend to avoid hard-coupling to one provider.

### 2.6 Explicit API Contracts Added

v1.5 introduces concrete contract section (below) with endpoints, response schema, and idempotency.

---

## 3. API Contracts (New)

All endpoints are under API Management and require bearer JWT unless marked otherwise.

### 3.1 `POST /v1/scan`

Scans one cover image and returns match outcome.

Request:

- Content-Type: `multipart/form-data`
- Fields:
  - `image`: JPEG binary (required)
  - `client_scan_id`: UUID (required, idempotency key)
  - `captured_at`: ISO-8601 timestamp (optional)

Response `200`:

```json
{
  "status": "owned|safe_to_buy|ambiguous|no_match",
  "confidence": 0.0,
  "album": {
    "mbid": "string|null",
    "discogs_release_id": "string|null",
    "title": "string",
    "artist": "string",
    "label": "string|null",
    "year": 1970
  },
  "owned_record": {
    "collection_album_id": "uuid",
    "format": "vinyl|cd|cassette|other",
    "date_added": "2026-05-10T10:00:00Z"
  },
  "candidates": [
    {
      "mbid": "string",
      "title": "string",
      "artist": "string",
      "year": 1970,
      "cover_art_url": "https://..."
    }
  ],
  "request_id": "uuid"
}
```

Rules:

- `owned`: definitive duplicate.
- `safe_to_buy`: definitive not-owned.
- `ambiguous`: confidence below threshold; populate `candidates` (top 3).
- `no_match`: no viable candidate.

Errors:

- `400` invalid payload/image
- `401` unauthorized
- `413` image too large
- `429` rate limited
- `500/502/503` transient server/dependency failure
- `504` processing timeout

### 3.2 `POST /v1/collection`

Adds an album to user collection.

Request body:

```json
{
  "mbid": "string|null",
  "discogs_release_id": "string|null",
  "title": "string",
  "artist": "string",
  "format": "vinyl|cd|cassette|other",
  "add_anyway": false,
  "idempotency_key": "uuid"
}
```

Behavior:

- Idempotent on `idempotency_key` + `user_id`.
- Returns existing record on replay.
- If duplicate exists and `add_anyway=false`, return `409 duplicate_detected` with existing record reference.

### 3.3 `GET /v1/collection`

Returns paginated collection for grid/search/filter.

Query params:

- `cursor` optional
- `limit` default 50, max 200
- `search` optional
- `format`, `decade`, `genre`, `sort` optional

Response includes `next_cursor` for pagination.

### 3.4 `DELETE /v1/account`

Hard-deletes user account and all related collection rows.

- Returns `202 accepted` with `request_id`.
- Deletion completion event logged for audit.

---

## 4. Error Schema (New)

All non-2xx responses use:

```json
{
  "error": {
    "code": "string_snake_case",
    "message": "human readable summary",
    "retryable": true,
    "request_id": "uuid"
  }
}
```

---

## 5. Observability Additions

Add mandatory telemetry fields on every scan:

- `request_id`
- `client_scan_id`
- `user_id` (hashed in logs)
- `payload_size_bytes`
- `model_latency_ms`
- `external_api_latency_ms` (per provider)
- `cache_hit` (boolean)
- `result_status` (`owned|safe_to_buy|ambiguous|no_match|error`)

---

## 6. Updated Acceptance Criteria

v1.5 requires all below before launch readiness:

- Latency SLO met: P95 < 3.0 s and P99 < 6.0 s.
- Timeout behavior matches policy in Section 2.1.
- `POST /v1/scan` and `POST /v1/collection` idempotency verified.
- Accessibility checks pass (VoiceOver, Dynamic Type, non-color-only badges).
- Privacy deletion path validated end-to-end.

---

## 7. Decision Log (v1.5)

- Keep PostgreSQL as system of record.
- Keep GPT-5.4 as sole model for v1.
- Keep scanning online-only in v1.
- Introduce binary upload transport as default.
- Add explicit API and error contracts to remove implementation ambiguity.

---

*Déjà Groove — Never buy the same album twice.*
