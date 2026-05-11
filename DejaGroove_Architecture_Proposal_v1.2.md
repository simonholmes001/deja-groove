# Déjà Groove Architecture Proposal (v1.2)

Status: Draft  
Date: 2026-05-11  
Supersedes: v1.1 (2026-05-10)

---

## Changes from v1.1

| # | Area | Change |
|---|---|---|
| N1 | Modules | `Collection` module: added `ICollectionQuotaPolicy` port (monetisation seam for v2). |
| N2 | Modules | `MetadataEnrichment` module: added `MetadataMerger` domain service description and Polly circuit breaker pattern per provider. |
| N3 | Modules | `AccountLifecycle`: clarified GDPR export as future paid-feature foundation. |
| N4 | API | Added `GET /v1/collection?since={iso8601_timestamp}` incremental sync endpoint. |
| N5 | API | Added `GET /v1/account/export` GDPR data export endpoint. |
| N6 | API | Added Section 5.6: scan pipeline latency budget (simplified — no enrichment in critical path). |
| N7 | API | Added Section 5.7: metadata conflict resolution policy (`MetadataMerger` field-by-field rules). |
| N8 | API | Added Section 5.8: offline / degraded mode data contract (iOS Core Data sync strategy). |
| N9 | ADR-005 | Enhanced: JWT stored in iOS Keychain; refresh token expiry 90 days; `user_id` as partition key. |
| N10 | ADR-011 | New: Monetisation seam — `ICollectionQuotaPolicy` port. |
| N11 | Risks | R5 enhanced: token-bucket rate limiter for MusicBrainz; Polly circuit breakers per adapter. |

---

## Changes from v1.0 (carried forward from v1.1)

| # | Area | Change |
|---|---|---|
| C1 | Compute | Replaced Azure Functions with **Azure Container Apps** (Consumption + min 1 replica). Eliminates cold-start SLO risk at a fraction of Functions Premium cost. |
| C2 | AI Provider | Locked to **OpenAI.com** (not Azure OpenAI Service). Trade-offs documented; accepted for v1. |
| C3 | API Ingress | Replaced APIM Standard/Premium with **APIM Consumption tier**. No base fee; JWT validation and rate limiting retained. Hub-and-spoke + Azure Firewall removed — cost-prohibitive ($1,000+/month for Firewall alone). |
| C4 | Scan SLO | **Enrichment removed from scan critical path.** Scan response returns identity + ownership status only. Metadata retrieved on-demand via separate endpoint. |
| C5 | Identity | Locked to **Entra External ID** (Microsoft's successor to Azure AD B2C for consumer apps). Free under 50,000 MAU. |
| H1 | Architecture | Added **`ScanWorkflowUseCase`** as explicit orchestrator. Removed orchestration responsibility from `Scanning` module. |
| H2 | Domain Model | Added full domain model: entities, value objects, invariants. |
| H3 | API | Added **`POST /v1/scan/{request_id}/resolve`** endpoint for ambiguous result resolution. |
| H4 | Networking | Added **CIDR address plan**. Replaced hub-and-spoke with single-VNet topology. |
| H7/H9 | Cache | **Redis removed.** Replaced with `scan_results_cache` table in PostgreSQL (pHash-keyed). Saves ~$30–$50/month. |
| H8 | PostgreSQL | Locked to **Flexible Server** (Single Server retired March 2025). |
| M1 | ADRs | All backlog ADRs written. |
| M3 | Tagging | Mandatory resource tagging strategy defined. |
| M4 | Service tiers | APIM Consumption, Container Apps, PostgreSQL Flexible Server tiers all specified. |
| M5 | 12-Factor | Config management (Factor III) made explicit. |
| NEW | Cost | Estimated monthly cost section added. |

---

## 1. Executive Summary

This proposal recommends a **modular monolith with hexagonal boundaries** for Déjà Groove v1, deployed on Azure using managed PaaS components at an indie-developer budget of approximately **$60–$85/month**.

The v1.2 revision adds enrichment module internals (MetadataMerger, Polly), a monetisation seam, incremental sync API, a full scan latency budget, a metadata merge policy, and an offline data contract — all carried from the parallel v1 iteration without conflicting with v1.1 platform decisions.

The core architectural philosophy is unchanged: single latency-critical workflow, modular boundaries, clean ports/adapters, cost-conscious platform choices.

---

## 2. Architecture Decision

### 2.1 Selected Pattern

- **Primary**: Modular Monolith + Hexagonal (Ports/Adapters)
- **Deployment shape**: Single containerised backend on Azure Container Apps, with strict internal module boundaries
- **API style**: REST `/v1` with explicit contracts and idempotency
- **AI provider**: OpenAI.com (direct) — see ADR-009

### 2.2 Why Not Microservices for v1

Microservices are deferred for v1. Each independently deployed service adds infrastructure overhead (separate container images, networking, monitoring) not justified at current scale. Additional cost dimension: per-service Container App environments multiply the base compute cost.

### 2.3 Evolution Triggers (When to Extract Services)

Extract services only when these observable signals appear:

1. Independent scaling pressure by capability (e.g. enrichment saturates independently of scan)
2. Distinct SLO/availability needs by module
3. Team topology changes with clear ownership boundaries
4. Release bottlenecks caused by shared deployment cadence

---

## 3. Target-State Logical Architecture

### 3.1 Client and Edge

- iOS app (SwiftUI, offline collection cache via Core Data — see Section 5.8)
- Azure API Management (Consumption tier) as single public ingress
- JWT validation at gateway via Entra External ID JWKS
- Rate limiting policy at APIM (per-subscription, per-user)
- Request correlation header injected at APIM

### 3.2 Backend Runtime

- **Azure Container Apps** (Consumption + Dedicated profile)
- Single container running .NET 9 ASP.NET Core Web API
- Minimum 1 replica always running (eliminates cold-start risk)
- Modular monolith composition with explicit internal contracts

### 3.3 Internal Modules

1. `Scanning` — Image intake and quality validation only. No orchestration.
2. `Matching` — AI cover identification via OpenAI.com, confidence policy, ambiguity routing.
3. `Collection` — Ownership checks, add/update/list, duplicate policy. Exposes `ICollectionQuotaPolicy` port; v1 implementation is `NoLimit`. v2 can swap in `FreemiumLimit(200)` or `ProUnlimited` without touching use case logic.
4. `MetadataEnrichment` — MusicBrainz/Discogs/Spotify adapters. **Not in scan critical path.** Contains `MetadataMerger` domain service — single deterministic merge point (see Section 5.7). Parallel fan-out via `Task.WhenAll` with per-provider Polly circuit breakers.
5. `IdentityAccess` — Authenticated user context propagation and query-level authorisation.
6. `AccountLifecycle` — Privacy deletion and GDPR export workflows. The export endpoint is the foundation for a potential future paid bulk-export feature.

**Application layer** contains `ScanWorkflowUseCase` which orchestrates modules 1–3 only. See Section 4.4.

### 3.4 Data and Integration

- **System of record**: Azure Database for PostgreSQL Flexible Server (Burstable B1ms for v1)
- **Scan result cache**: `scan_results_cache` table in PostgreSQL, indexed on `(user_id, perceptual_hash)`. Redis removed — see ADR-010.
- **Secrets**: Azure Key Vault + Managed Identity only. No connection strings in config files or environment variables.
- **AI**: OpenAI.com API (HTTPS, key in Key Vault). See ADR-009.
- **Enrichment providers**: MusicBrainz, Discogs, Spotify. Called on-demand only, not in scan response path.

### 3.5 Observability

- App Insights + Azure Monitor + Log Analytics
- Correlated `request_id` / `client_scan_id` across APIM, Container App, database, external APIs
- Mandatory telemetry fields on every scan (per PRD Section 5):
  - `request_id`, `client_scan_id`, `user_id` (hashed), `payload_size_bytes`
  - `model_latency_ms`, `external_api_latency_ms` (per provider)
  - `cache_hit` (boolean), `result_status`

---

## 4. Clean Architecture Structure

### 4.1 Layers

- **Domain**: Core entities, value objects, invariants (Section 4.3)
- **Application**: Use cases / interactors, including `ScanWorkflowUseCase` (Section 4.4)
- **Ports**: Interfaces for persistence, AI, metadata providers, cache, time, events
- **Adapters**: HTTP endpoints, database repositories, OpenAI client, metadata API clients

### 4.2 Dependency Rule

- Dependencies point inward only (toward policy)
- Framework, cloud SDK, DB, and vendor APIs remain outside core policy
- Core use cases are executable with test doubles (no framework boot required)
- Module-level: no cross-module direct type dependencies; modules communicate via port interfaces only

### 4.3 Domain Model

#### Entities

**`CollectionRecord`** (aggregate root)
- Identity: `collection_album_id` (UUID, system-generated)
- Fields: `user_id`, `album_identity`, `format`, `date_added`, `notes`
- Invariant: A user may not hold two `CollectionRecord` instances with the same `AlbumIdentity` unless `add_anyway = true` was explicitly passed at creation time.

**`ScanEvent`** (entity, append-only log)
- Identity: `scan_event_id` (UUID)
- Fields: `user_id`, `client_scan_id`, `result_status`, `confidence`, `album_identity`, `captured_at`, `created_at`
- Invariant: Once created, `ScanEvent` is immutable.

#### Value Objects

**`AlbumIdentity`**
- Fields: `mbid` (nullable), `discogs_release_id` (nullable), `title`, `artist`, `year` (nullable)
- Invariant: At least one of `mbid` or `discogs_release_id` must be non-null, **or** both `title` and `artist` must be non-null. A fully null identity is rejected.
- Equality: `mbid` takes precedence when non-null. Falls back to `discogs_release_id`, then `(title, artist)` normalised pair.

**`ScanResult`**
- Fields: `status` (`owned | safe_to_buy | ambiguous | no_match`), `confidence` (0.0–1.0), `album_identity` (nullable), `candidates` (list, max 3)
- Invariant: `status = ambiguous` requires `candidates` to be non-empty. `status = owned` requires `collection_record_id` to be non-null.
- Domain constant: `ConfidenceThreshold.Minimum = 0.75` (value owned by domain, not by any adapter)

**`PerceptualHash`**
- Wraps a 64-bit pHash value as a typed value object
- Used as cache key for scan result reuse

#### Aggregate Boundaries

- `CollectionRecord`: owned by `Collection` module
- `ScanEvent`: owned by `Scanning` module
- No cross-aggregate references by value; reference by identity only

### 4.4 ScanWorkflow Use Case

`ScanWorkflowUseCase` lives in the Application layer and is the sole orchestrator of the scan pipeline. No individual module performs orchestration.

```
ScanWorkflowUseCase.Execute(command: ScanCommand) → ScanResult

  1. ImageValidationPort.Validate(image) → ValidationResult
     └─ Reject on format/size failure → return error

  2. PerceptualHashPort.Compute(image) → PerceptualHash

  3. ScanCachePort.TryGet(userId, hash) → ScanResult?
     └─ Cache HIT → return cached result (skip steps 4–6)

  4. AlbumMatchingPort.Identify(image) → MatchingResult
     └─ no_match / low confidence → return ScanResult(no_match | ambiguous)

  5. CollectionOwnershipPort.Check(userId, albumIdentity) → OwnershipResult
     └─ owned → return ScanResult(owned, collectionRecordId)
     └─ not owned → return ScanResult(safe_to_buy)

  6. ScanCachePort.Store(userId, hash, result, ttl: 15min)

  7. ScanEventRepository.Append(scanEvent)

  8. return ScanResult
```

Each port is an interface in the Application layer. Concrete adapters (OpenAI HTTP client, PostgreSQL repository, etc.) are injected at composition root. No module imports another module's types directly.

---

## 5. API Architecture (v1)

### 5.1 Core Endpoints

- `POST /v1/scan` — Scan and deduplicate (returns ownership status only; no enrichment)
- `POST /v1/scan/{request_id}/resolve` — Resolve ambiguous result by selecting a candidate
- `POST /v1/collection` — Add album to collection
- `GET /v1/collection` — Paginated collection list with search/filter/sort
- `GET /v1/collection?since={iso8601_timestamp}` — Incremental diff; returns only records changed or deleted since the given timestamp. Used by the iOS client for offline sync (see Section 5.8).
- `GET /v1/collection/{id}` — Single collection record with on-demand enrichment
- `PATCH /v1/collection/{id}` — Update format, notes
- `DELETE /v1/account` — Hard-delete account and all collection data
- `GET /v1/account/export` — GDPR data export (AccountLifecycle module)
- `GET /health` — Health probe (unauthenticated, used by Container Apps and APIM)

### 5.2 Candidate Resolution Endpoint

`POST /v1/scan/{request_id}/resolve`

Request body:
```json
{
  "selected_mbid": "string|null",
  "selected_discogs_release_id": "string|null"
}
```

Behavior:
- Validates that `request_id` matches a prior scan with `status = ambiguous` for the authenticated user.
- Validates that the selected identity matches one of the `candidates` returned in that scan.
- Checks collection ownership for the selected identity.
- Returns same response schema as `POST /v1/scan`.
- Idempotent: replaying with same selection returns same result.

Error cases:
- `404` — request_id not found or not owned by user
- `409` — request_id is not in `ambiguous` status
- `422` — selected identity not in original candidates list

### 5.3 Scan Response Schema

`POST /v1/scan` response `200`:

```json
{
  "status": "owned|safe_to_buy|ambiguous|no_match",
  "confidence": 0.0,
  "album": {
    "mbid": "string|null",
    "discogs_release_id": "string|null",
    "title": "string",
    "artist": "string",
    "year": 1970
  },
  "owned_record": {
    "collection_album_id": "uuid",
    "format": "vinyl|cd|cassette|other",
    "date_added": "2026-05-10T10:00:00Z"
  },
  "candidates": [
    {
      "mbid": "string|null",
      "discogs_release_id": "string|null",
      "title": "string",
      "artist": "string",
      "year": 1970
    }
  ],
  "request_id": "uuid"
}
```

Notes:
- `owned_record` is `null` unless `status = owned`.
- `candidates` is non-empty only when `status = ambiguous`; empty array otherwise.
- `label`, `genre`, `related_artists`, `cover_art_url` are **not** returned here. Retrieve via `GET /v1/collection/{id}` after the record is added.

### 5.4 Contract Rules

- Stable response envelope with `request_id`
- Standardised error schema: `code`, `message`, `retryable`, `request_id`
- Idempotency keys on scan (`client_scan_id`) and write operations (`idempotency_key`)
- Additive backward-compatible evolution within `v1`
- Rate limit headers (`X-RateLimit-Limit`, `X-RateLimit-Remaining`, `Retry-After`) on 429 responses

### 5.5 Performance and SLO Policy

- **Scan critical path**: image validation → pHash → cache check → AI identification → ownership check
- **End-to-end scan P95 target**: `< 3.0 s`
- **Client hard timeout**: `6.0 s`
- **Internal orchestration budget**: `5.0 s`
- **Enrichment**: not in scan path. On-demand via `GET /v1/collection/{id}`. No SLO required.

### 5.6 Scan Pipeline Latency Budget

The `< 3.0 s` P95 SLO is enforced through the budget below. OpenAI.com Vision is the only serial dependency on the cache-miss path. The ownership check and cache write are a fast PostgreSQL round-trip. Enrichment is not called.

```
CLIENT SENDS IMAGE
        │
        ▼
[1] Image validation                           ~5ms
        │
[2] pHash computation                          ~5ms
        │
[3] PostgreSQL cache lookup                    ~10–15ms
        │
   ┌────┴──────────┐
Cache HIT        Cache MISS
   │                 │
   │         [4] OpenAI.com Vision call        ~2,000ms (P95 budget)
   │                 │
   │         Returns album identity + confidence
   │                 │
   └────┬────────────┘
        │
[5] PostgreSQL ownership check                 ~10–20ms
        │
[6] PostgreSQL cache write + ScanEvent append  ~15–20ms
        │
        ▼
RESPONSE TO CLIENT

TOTAL (cache miss, P95): ~2,045–2,065ms  ✅ well under 3s
TOTAL (cache hit):            ~30–45ms   ✅
```

**Provider timeout policy:**

| Provider | Timeout | On Timeout / Failure |
|---|---|---|
| OpenAI.com Vision | 5,500 ms | Return error toast to client (retryable) |
| PostgreSQL | 200 ms | Return error toast to client (retryable) |

**pHash cache sequencing:**

1. Compute pHash server-side from incoming JPEG.
2. Lookup `(user_id, pHash)` key in PostgreSQL cache table.
   - **HIT**: return cached `ScanResult` → skip OpenAI call entirely.
   - **MISS**: call OpenAI.com Vision → proceed to ownership check.
3. After ownership check, write result to cache with 15-minute TTL.

### 5.7 Metadata Conflict Resolution Policy

Called only from `GET /v1/collection/{id}` (on-demand enrichment). Implemented as `MetadataMerger` — a pure domain service in the `MetadataEnrichment` module with no I/O dependencies, making it fully unit-testable. It accepts typed results from each provider adapter (`MusicBrainzResult`, `DiscogsResult`, `SpotifyResult`). An adapter failure or timeout produces a `null` typed result; the merger treats `null` as "no data from this provider" and proceeds without failing the request.

**Canonical rule: MusicBrainz is truth for identity; Discogs supplements pressing detail; Spotify decorates.**

| Field | Source | Rule |
|---|---|---|
| `mbid` | MusicBrainz | Canonical. Never overwritten. |
| `title` | MusicBrainz | Canonical. Discogs title ignored. |
| `artist` | MusicBrainz | Canonical. |
| `label` | MusicBrainz | Canonical. Discogs used only if MusicBrainz `label` is null. |
| `release_year` | MusicBrainz | Canonical. |
| `country` | MusicBrainz | Canonical. |
| `genre` | MusicBrainz | Canonical. Spotify `genres[]` appended as secondary tags if not already present. |
| `tracklist` | MusicBrainz | Canonical. |
| `catalogue_number` | Discogs | Discogs-only. |
| `matrix_runout` | Discogs | Discogs-only. |
| `edition` | Discogs | Discogs-only. |
| `pressing_country` | Discogs | Discogs-only. |
| `estimated_value` | Discogs | Discogs-only (median sale price). Refreshed on each enrichment call. |
| `album_bio` | Spotify | Spotify-only. Refreshed on each enrichment call. |
| `related_artists` | Spotify | Spotify-only. Refreshed on each enrichment call. |
| `cover_art_url` | MusicBrainz | MusicBrainz preferred. Null if MusicBrainz has none (no fallback in v1). |

**Re-enrichment policy (user views an already-owned album):** MusicBrainz identity fields (`mbid`, `title`, `artist`) are never overwritten. Discogs and Spotify decorative fields are refreshed (prices and bios change over time).

**Provider resilience for enrichment:** Each provider adapter wraps its HTTP client with a Polly circuit breaker (5 failures in 30 s → open for 60 s). A broken circuit causes the adapter to return `null` immediately, which `MetadataMerger` handles gracefully. MusicBrainz additionally uses a token-bucket rate limiter in its adapter (1 request/second) to respect the API's strict rate limit.

### 5.8 Offline / Degraded Mode — Data Contract

The iOS client maintains a Core Data offline cache. The backend exposes the incremental sync endpoint (`GET /v1/collection?since=`) to support it.

**What lives in Core Data:**
- Full collection record (all fields from the `collection_records` PostgreSQL table)
- Cover art thumbnails (200 px) cached locally; full-resolution lazy-loaded on demand via `cover_art_url`
- Last-sync timestamp per user

**Sync strategy:**
- On app foreground: pull diff via `GET /v1/collection?since={last_sync_timestamp}`
- On collection write: optimistic local update first, then API call; if offline, enqueue in a local pending-ops store
- On reconnection: flush pending-ops queue in order, using idempotency keys (Section 5.4) to prevent duplicates
- **Conflict rule (server wins):** if the server `updated_at` is newer than the local record, overwrite local. Only user-edited fields (`notes`, `format`) are at meaningful conflict risk; last-write-wins with server timestamp as authority.

**`GET /v1/collection?since=` response additions:**

The response must include a `deleted_ids` array listing `collection_album_id` values hard-deleted since the given timestamp, so the iOS client can evict them from Core Data:

```json
{
  "items": [ ... ],
  "deleted_ids": ["uuid", "uuid"],
  "next_cursor": "string|null",
  "sync_timestamp": "2026-05-11T10:00:00Z"
}
```

---

## 6. Azure Platform and Landing Zone

### 6.1 Management and Subscription Model

- Management groups: `Platform`, `Workloads`
- Subscriptions:
  - `deja-platform-prod` — shared services (Key Vault, Log Analytics workspace, App Insights)
  - `deja-app-prod` — production workload (Container Apps, PostgreSQL, APIM)
  - `deja-app-nonprod` — dev + staging environments

### 6.2 Guardrails (Before Workload Onboarding)

- Policy-as-code for:
  - Mandatory resource tags (see Section 6.4)
  - Region restriction (single region for v1)
  - Require diagnostic settings for Container Apps, PostgreSQL, Key Vault, APIM
  - Require HTTPS-only for all HTTP-accessible resources
- RBAC/PIM model with break-glass access process
- Mandatory centralised logging to Log Analytics workspace

### 6.3 Environment Isolation

- Prod/non-prod subscription isolation
- Separate Key Vault instances, databases, and APIM subscriptions per environment

### 6.4 Mandatory Resource Tagging Strategy

All resources must carry these tags, enforced by Azure Policy with `Deny` effect:

| Tag | Values | Purpose |
|---|---|---|
| `environment` | `dev` \| `staging` \| `prod` | Cost attribution and alert scoping |
| `application` | `deja-groove` | Portfolio grouping |
| `owner` | owner email | Incident escalation |
| `cost-centre` | `deja-groove-v1` | Budget alert binding |

---

## 7. Azure Networking Architecture

### 7.1 Topology

- **Single VNet** per environment (no hub-and-spoke for v1)
- Hub-and-spoke deferred until a second workload justifies shared transit. Azure Firewall (~$1,000+/month) is not viable at indie scale.
- Private endpoints for PostgreSQL and Key Vault only
- OpenAI.com traffic egresses over public internet (HTTPS). Accepted risk — see ADR-009.
- NSGs on all subnets with default-deny posture

### 7.2 CIDR Address Plan

| Segment | CIDR | Size | Notes |
|---|---|---|---|
| VNet (prod) | `10.1.0.0/22` | 1022 hosts | Room for future subnets |
| Container Apps subnet | `10.1.0.0/23` | 510 hosts | Minimum /23 required by ACA infrastructure |
| Private endpoint subnet | `10.1.2.0/27` | 30 hosts | PostgreSQL PE, Key Vault PE |
| Reserved / future | `10.1.2.32/27` | 30 hosts | APIM injection or additional PEs |
| VNet (nonprod) | `10.2.0.0/22` | 1022 hosts | Same structure, separate CIDR |

### 7.3 Private Connectivity

- Private Endpoint for PostgreSQL Flexible Server (subnet `10.1.2.0/27`)
- Private Endpoint for Key Vault (subnet `10.1.2.0/27`)
- Container Apps environment uses VNet integration for outbound calls to private endpoints
- Private DNS zones: `privatelink.postgres.database.azure.com`, `privatelink.vaultcore.azure.net`, linked to VNet
- APIM Consumption: no VNet support; calls Container Apps over public HTTPS. Container Apps ingress restricted to APIM outbound IP ranges via Container Apps IP restrictions.

### 7.4 DNS and NSG Validation

- Release gate includes: DNS resolution check for private endpoints, NSG effective rule validation, Container Apps outbound connectivity test to PostgreSQL private endpoint.
- NSG on Container Apps subnet: allow inbound HTTPS from APIM IP range; allow outbound to private endpoint subnet and to `api.openai.com:443`.

---

## 8. Security Architecture

### 8.1 Identity and Access

- **Entra External ID** (Microsoft's consumer identity platform, successor to Azure AD B2C)
  - Why not Entra ID (enterprise)? Entra ID targets organisational/work accounts. Déjà Groove is a consumer app — users register with personal email. Entra External ID supports email+password and social login (Apple, Google), uses MSAL for iOS, and is free under 50,000 MAU.
  - MSAL + PKCE on iOS client. JWT stored in iOS Keychain (not UserDefaults). Refresh token expiry: 90 days.
  - JWT tokens validated at APIM via JWKS endpoint from Entra External ID tenant.
  - `user_id` = Entra External ID Object ID. This is the partition key for all collection queries — no use case reads across user boundaries regardless of token claims.
  - Auth abstracted behind `IdentityAccess` module port — no identity provider types leak into domain or application layers. If the provider changes post-v1, only the MSAL adapter and APIM JWT policy change.

### 8.2 Secrets, Keys, and Data

- **All secrets in Key Vault only** — OpenAI API key, Discogs/MusicBrainz/Spotify API keys
- Container Apps accesses Key Vault via Managed Identity (no secret in environment variables or app settings files)
- Config hierarchy: Container Apps environment variables → Key Vault secret references resolved at runtime → no secrets in committed files (Factor III)
- TLS in transit for all network paths
- Encryption at rest: PostgreSQL transparent data encryption (default on), Key Vault HSM-backed for secrets
- No persistent storage of raw scan images in v1

### 8.3 OpenAI.com Integration Security

OpenAI.com is used directly (not Azure OpenAI Service). Accepted trade-offs:

| Concern | Mitigation |
|---|---|
| No private endpoint (public internet path) | HTTPS only; TLS 1.2+ enforced; API key in Key Vault |
| No Azure SLA | Retry policy (1 auto-retry on transient); user-facing error toast on failure |
| Data residency (images sent to OpenAI servers) | App privacy policy must disclose this. No PII in images (album covers only). |
| No Azure-native audit trail for AI calls | Log `model_latency_ms` and `result_status` in App Insights; OpenAI usage dashboard for token tracking |
| Cost control | Per-user rate limiting at APIM; budget alert on OpenAI usage dashboard |

AI model response is validated against expected JSON schema before processing. Unexpected response shapes are treated as errors, not parsed.

### 8.4 Detection and Response

- Defender for Cloud enabled on all subscriptions (free tier)
- App Insights alerts on: auth failures spike, 5xx rate spike, scan latency P95 breach, dependency failure rate
- Auditable account deletion flow: deletion request logged with `request_id` before execution
- Key Vault access logging enabled; alert on unusual secret access patterns

---

## 9. Twelve-Factor Alignment

| Factor | Status | Detail |
|---|---|---|
| 1. Codebase | Meets | Single repo, modular boundaries, one deployable per environment |
| 2. Dependencies | Meets | .NET 9 with explicit NuGet package lock; no implicit runtime dependencies |
| 3. Config | Meets | All config via Container Apps environment variables; secrets via Key Vault secret references; zero secrets in committed files |
| 4. Backing services | Meets | PostgreSQL, Key Vault, APIM, OpenAI treated as attached resources via config |
| 5. Build/Release/Run | Meets | CI builds image, CD promotes immutable image tag through environments |
| 6. Processes | Meets | Container Apps instances are stateless; session state held in JWT only |
| 7. Port binding | Meets | ASP.NET Core binds on configured port; Container Apps routes to it |
| 8. Concurrency | Meets | Horizontal scale via Container Apps replica count |
| 9. Disposability | Meets | Container Apps instances start and stop cleanly; 1 min replica eliminates cold-start SLO impact |
| 10. Dev/Prod parity | Meets | IaC (Bicep) provisions identical topology per environment; same container image promoted through envs |
| 11. Logs | Meets | Structured JSON logs to stdout; Container Apps forwards to App Insights |
| 12. Admin processes | Meets | One-off admin operations (data migrations, account deletion jobs) run as short-lived Container Apps Jobs |

---

## 10. Microsoft Agent Framework Position

- **Decision for v1**: MAF excluded from the critical scan transaction path.
- **Rationale**: The scan workflow is deterministic and latency-sensitive. MAF adds non-deterministic orchestration overhead incompatible with the 5 s internal budget.
- **Optional later use**: MAF for non-critical flows (collection recommendations, curation assistant), isolated from the core write path.

---

## 11. Architecture Decision Records

### ADR-001: Modular Monolith + Hexagonal Architecture

**Status**: Accepted  
**Context**: Déjà Groove v1 has a single primary workflow (scan → identify → dedupe → respond). Team is small. Operational complexity of microservices is disproportionate to current scale.  
**Decision**: Modular monolith with hexagonal (ports/adapters) architecture. One deployable; strict internal module boundaries; dependency rule enforced inward only.  
**Consequences (+)**: Simple deployment, easy testing with test doubles, low operational burden.  
**Consequences (−)**: All modules scale together; extraction requires more upfront effort than purpose-built services. Mitigated by clean seam design.  
**Review trigger**: Any of the evolution triggers in Section 2.3.

---

### ADR-002: APIM Consumption as Single Ingress

**Status**: Accepted  
**Context**: API gateway needed for JWT validation, rate limiting, and request correlation. Standard/Premium APIM tiers are cost-prohibitive ($150–$2,800/month).  
**Decision**: APIM Consumption tier. No base fee; $3.50 per million API calls. JWT validation via Entra External ID JWKS policy. Rate limiting policy per user. No VNet integration — APIM calls Container Apps over public HTTPS; Container Apps restricts inbound to APIM outbound IP ranges.  
**Consequences (+)**: Essentially free at indie scale; preserves gateway pattern for future policy addition.  
**Consequences (−)**: No SLA on APIM Consumption; APIM → Container Apps path is public. Accepted — see Section 8.3.  
**Review trigger**: Monthly call volume exceeds 5 million; or private APIM → Container Apps path becomes a compliance requirement.

---

### ADR-003: PostgreSQL Flexible Server + PostgreSQL Scan Cache (No Redis)

**Status**: Accepted  
**Context**: Relational system of record needed. Redis was proposed for scan result caching to avoid repeat AI calls. Redis Standard tier costs ~$30–50/month for that single purpose.  
**Decision**: PostgreSQL Flexible Server (Burstable B1ms) as system of record. Scan result cache as `scan_results_cache` table, keyed on `(user_id, perceptual_hash)` with `expires_at`. Background job prunes expired rows.  
**Consequences (+)**: Eliminates Redis and its cost; cache persists across restarts; single data plane.  
**Consequences (−)**: Cache lookup adds ~10–15 ms DB round-trip (vs. ~1–5 ms Redis). Acceptable within budget. Mitigate contention with `INSERT ... ON CONFLICT DO NOTHING`.  
**PostgreSQL version**: Flexible Server only (Single Server retired March 2025). Burstable B1ms for v1.  
**Review trigger**: Cache table exceeds 500,000 rows, or cache query P99 exceeds 50 ms.

---

### ADR-004: Single-VNet Networking (Hub-and-Spoke Deferred)

**Status**: Accepted  
**Context**: Hub-and-spoke with Azure Firewall was proposed for private egress control. Azure Firewall costs ~$1,000+/month.  
**Decision**: Single VNet per environment. Private endpoints for PostgreSQL and Key Vault. No Azure Firewall. NSGs with default-deny on all subnets. OpenAI.com egress over public HTTPS.  
**Consequences (+)**: Saves ~$1,000/month; simpler to operate; sufficient for v1 threat model.  
**Consequences (−)**: No centralised egress inspection. Mitigated by NSG outbound rules.  
**Review trigger**: Second workload onboarded that shares network; or compliance mandates private egress inspection.

---

### ADR-005: Entra External ID for Consumer Identity

**Status**: Accepted  
**Context**: Azure AD B2C is in maintenance mode. Entra External ID is Microsoft's designated successor for consumer identity.  
**Decision**: Entra External ID. MSAL iOS SDK with PKCE. JWT stored in iOS Keychain (not UserDefaults). Refresh token expiry: 90 days. `user_id` = Entra External ID Object ID; this is the partition key for all collection queries — no use case reads across user boundaries. Auth abstracted behind `IdentityAccess` port — if the provider changes, only the MSAL adapter and APIM JWT policy change; no use case logic is affected.  
**Why not Entra ID (enterprise)?** Entra ID is for organisational accounts. Consumer sign-up with personal email and Apple/Google social login requires Entra External ID.  
**Consequences (+)**: Free under 50,000 MAU; Microsoft-supported; clean migration seam.  
**Consequences (−)**: Newer product; confirm feature parity with B2C before M2 freeze.  
**Review trigger**: M2 feature freeze — confirm email registration, Apple login, password reset, account deletion trigger all work.

---

### ADR-006: MAF Excluded from v1 Critical Path

**Status**: Accepted  
**Context**: MAF could orchestrate the scan workflow but adds non-deterministic overhead.  
**Decision**: MAF excluded from scan transaction path. `ScanWorkflowUseCase` is a direct imperative interactor. MAF reserved for future non-critical flows.  
**Consequences (+)**: Deterministic latency; simpler failure model.  
**Consequences (−)**: No agentic reasoning in scan path (not needed for v1).

---

### ADR-007: Azure Container Apps as Compute Platform

**Status**: Accepted  
**Context**: Azure Functions cold-start risk (2–5 s on Consumption plan) directly threatens the P95 < 3 s SLO. Functions Premium EP1 eliminates cold-start but costs ~$120–$160/month.

**Options evaluated:**

| Option | Cold start | Est. cost/month | Notes |
|---|---|---|---|
| Functions Consumption | 2–5 s (risk) | ~$1–5 | SLO violation risk on cold path |
| Functions Premium EP1 | None | ~$120–160 | Too expensive for v1 |
| Functions Flex Consumption (min 1) | None | ~$40–55 | Viable; less container-native |
| **Container Apps (min 1 replica)** | **None** | **~$35–45** | Selected — best cost/warm ratio |

**Decision**: Azure Container Apps, Consumption + Dedicated profile, minimum 1 replica (0.5 vCPU / 1 GB) in prod. Scales to 0 in non-prod.  
**Consequences (+)**: No cold start; container-native suits a modular monolith ASP.NET Core app; lower cost than Functions Premium.  
**Consequences (−)**: Less built-in trigger ecosystem than Functions. For v1, all triggers are HTTP — no loss. Timer tasks run as Container Apps Jobs.  
**Review trigger**: Functions Flex Consumption reaches pricing parity.

---

### ADR-008: Enrichment Out of Scan Critical Path

**Status**: Accepted  
**Context**: Adding MusicBrainz, Discogs, and Spotify to the synchronous scan response makes P95 < 3 s unachievable with any reasonable margin.  
**Core requirement**: The user needs to know one thing — have I already bought this album? Metadata is useful but not time-critical.  
**Decision**: Scan returns `AlbumIdentity` + ownership `status` only. Enrichment is on-demand via `GET /v1/collection/{id}`. `MetadataEnrichment` module is not called during scan execution.  
**Consequences (+)**: Realistic latency budget; enrichment failures never affect scan SLO; enrichment retried independently.  
**Consequences (−)**: iOS client makes a second call to show full metadata after adding to collection. Acceptable UX: user taps "Add", detail view loads enrichment asynchronously.  
**Review trigger**: User research shows metadata-at-scan-time is a meaningful friction point.

---

### ADR-009: OpenAI.com Direct Integration (Not Azure OpenAI Service)

**Status**: Accepted  
**Context**: PRD specifies GPT-5.4 Vision (OpenAI). GPT-5.4 may not yet be available in Azure OpenAI Service.  
**Decision**: OpenAI.com API used directly. API key in Key Vault. HTTPS enforced. Album cover images (no PII) sent to OpenAI servers. Privacy policy must disclose this.  
**Accepted risks**: No private network path; no Azure SLA; data leaves Azure trust boundary. Mitigated by: HTTPS-only; no PII; retry on transient failure; per-user rate limiting.  
**Review trigger**: Azure OpenAI Service makes GPT-5.4 available; or compliance requires Azure data residency.

---

### ADR-010: PostgreSQL Table as Scan Result Cache

**Status**: Accepted  
*(Full rationale in ADR-003.)*

Schema:
```sql
CREATE TABLE scan_results_cache (
    user_id         UUID        NOT NULL,
    perceptual_hash BIGINT      NOT NULL,
    result_status   TEXT        NOT NULL,
    result_json     JSONB       NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at      TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (user_id, perceptual_hash)
);
CREATE INDEX idx_src_expires ON scan_results_cache (expires_at)
    WHERE expires_at < now();
```

TTL: 15 minutes. Short TTL ensures ownership status remains coherent if user adds an album mid-session.

---

### ADR-011: Monetisation Seam — ICollectionQuotaPolicy

**Status**: Accepted  
**Context**: Monetisation is deferred to v2. Without a deliberate seam, introducing a freemium cap later would require modifying use case logic.  
**Decision**: The `Collection` module exposes an `ICollectionQuotaPolicy` port. The v1 implementation is `NoLimit` (always permits). The `AddToCollectionUseCase` calls `ICollectionQuotaPolicy.IsWithinLimit(userId, currentCount)` before persisting. v2 can introduce `FreemiumLimit(200)` or `ProUnlimited` by registering a different implementation — no use case code changes.  
**Consequences (+)**: Clean v2 monetisation seam; policy is independently testable; use case logic unchanged.  
**Consequences (−)**: Minor abstraction overhead for a v1-only `NoLimit` rule.  
**Review trigger**: When v2 monetisation strategy is defined.

---

## 12. Phased Rollout Plan

### Phase 1: Platform Foundation
- Landing zone, policies, RBAC/PIM, tagging enforcement, Log Analytics workspace, App Insights instance
- VNet, subnets, NSGs, private DNS zones
- Key Vault with Managed Identity access model

### Phase 2: Core Product Backbone
- Entra External ID tenant configuration; MSAL iOS integration (Keychain storage, PKCE)
- APIM Consumption instance; JWT validation policy; rate limiting policy
- PostgreSQL Flexible Server; schema migrations; `scan_results_cache` table
- Container Apps environment; health probe; deployment pipeline (CI builds image, CD promotes)
- Collection API (`POST`, `GET`, `GET?since=`, `PATCH /v1/collection`; `DELETE /v1/account`; `GET /v1/account/export`)

### Phase 3: Scan Pipeline
- `ScanWorkflowUseCase` implementation with all ports wired
- OpenAI.com adapter (API key from Key Vault)
- Image validation, pHash computation, cache lookup
- `POST /v1/scan` and `POST /v1/scan/{request_id}/resolve` endpoints
- Idempotency validation; ScanEvent append-only logging

### Phase 4: Enrichment and Hardening
- `MetadataEnrichment` module; MusicBrainz adapter (with token-bucket rate limiter), Discogs adapter, Spotify adapter; Polly circuit breakers per provider
- `MetadataMerger` domain service wired to `GET /v1/collection/{id}`
- Retry and resilience tuning for enrichment providers
- iOS Core Data offline cache + incremental sync (`since=` endpoint)
- Observability: alert rules, latency dashboards, SLO burn rate alert

### Phase 5: Launch Readiness
- SLO gate validation: P95 < 3.0 s and P99 < 6.0 s confirmed under representative load
- Privacy deletion path validated end-to-end; GDPR export validated
- Accessibility checks: VoiceOver, Dynamic Type, non-colour-only badges
- Idempotency verified for `POST /v1/scan` and `POST /v1/collection`
- Security: Key Vault secret rotation procedures documented; Defender for Cloud findings reviewed

---

## 13. Estimated Monthly Cost (Production)

All estimates in USD, East US region, approximate as of May 2026. Actual costs vary with usage.

| Component | Tier | Est. $/month |
|---|---|---|
| Azure Container Apps | Consumption + Dedicated, 1 min replica (0.5 vCPU / 1 GB) | ~$38–45 |
| APIM | Consumption ($3.50/million calls) | ~$0–2 |
| PostgreSQL Flexible Server | Burstable B1ms + 32 GB storage | ~$18–22 |
| Azure Key Vault | Standard (operations-based) | ~$1 |
| App Insights + Log Analytics | First 5 GB/month free | ~$2–5 |
| Private DNS zones (×2) | $0.50/zone/month | ~$1 |
| Entra External ID | Free under 50,000 MAU | $0 |
| OpenAI.com | Usage-based (~$0.01/image at GPT-4o Vision rates) | ~$1–20 |
| **Total** | | **~$61–96/month** |

Note: OpenAI cost scales with scan volume. At 1,000 scans/month: ~$10. At 10,000 scans/month: ~$100 (OpenAI cost dominates at that point).

---

## 14. Risks and Open Questions

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Entra External ID feature gap vs. B2C | Medium | Confirm feature parity before M2 freeze (ADR-005) |
| R2 | OpenAI.com availability — no Azure SLA | Medium | 1 auto-retry; user-facing error toast; users can retry manually |
| R3 | OpenAI.com model availability (GPT-5.4 may not be accessible via API) | High | Confirm API access to GPT-5.4 or equivalent vision model before Phase 3 begins |
| R4 | PostgreSQL cache table contention under concurrent scans | Low | `INSERT ... ON CONFLICT DO NOTHING`; 15-min TTL; monitor index efficiency |
| R5 | Enrichment provider rate limits and latency variability | Medium | MusicBrainz: token-bucket rate limiter (1 req/s) in adapter + pHash cache hit skips MusicBrainz entirely for repeat scans. All providers: Polly circuit breaker (5 failures/30 s → open 60 s). Enrichment not in scan SLO path — failures are graceful. |
| R6 | APIM Consumption first-call latency | Low | Sub-second; acceptable for v1 |
| R7 | Container Apps egress to OpenAI.com blocked by future NSG change | Low | FQDN allow rule (`api.openai.com:443`) documented in IaC; included in release gate check |
| R8 | Single-region: no DR for database | Medium | Zone-redundant HA on PostgreSQL Flexible Server (~$18/month extra); defer to post-launch if budget constrained |

---

## 15. Review Checklist

Challenge this proposal on:

1. **Boundary quality**: Are modules cohesive and independently testable via port interfaces?
2. **SLO realism**: Is P95 < 3 s achievable with Container Apps (1 min replica) + OpenAI.com + PostgreSQL cache on the hot path?
3. **Security control completeness**: Private paths for PostgreSQL/Key Vault; OpenAI.com accepted public path; APIM JWT validation; JWT in iOS Keychain.
4. **Landing-zone sufficiency**: Policy coverage (tagging, diagnostics, HTTPS-only); exemption governance.
5. **Networking assumptions**: CIDR plan correctness; Container Apps subnet /23 requirement; NSG outbound rule for `api.openai.com`.
6. **Extraction readiness**: Are seams clean if enrichment or matching is later split into a separate service?
7. **Cost realism**: Validate estimates against Azure Pricing Calculator before commitment.
8. **Offline sync correctness**: Does the `since=` + `deleted_ids` contract cover all conflict scenarios for Core Data?

---

*Déjà Groove — Never buy the same album twice.*
