# How this repo actually works

_Source-derived walkthrough written by reading the code, not the README. Evidence tags:_
_`Verified` = read in-tree at the cited path, `Derived` = inferred from multiple verified sources._

Despite what the folder names suggest, Déjà Groove is **not** a .NET backend. The `backend/src/DejaGroove.{Api,Application,Domain,Infrastructure}` folders contain only `bin/` and `obj/` — empty stubs of a design that was never written (Verified). The real system is a two-piece stack:

1. **A stateless Azure Function proxy** (Node/TypeScript) that turns a vinyl cover photo into structured album metadata.
2. **A SwiftUI iOS app** that captures the image, calls the Function, and keeps a **local, on-device** collection / wishlist / discovery history.

There is no server-side database and no backend user account today; the app is fully local except for the recognition call (Derived).

---

## 1. The recognition Function (`functions/recognition-proxy/`)

Node 22, `@azure/functions` v4, deployed on a Flex Consumption plan. Wired in `functions/recognition-proxy/src/index.ts:1` (Verified):

- `GET  /health` — anonymous, returns a version marker (`src/health.ts:22`).
- `POST /v1/scan` — `function` auth level (requires `x-functions-key` header). Handler in `src/scan.ts:22`.
- `POST /v1/enrich` — same auth. Handler in `src/enrich.ts:16`.

At boot it constructs a chain of ports (`src/index.ts:20`):

```
CachedAlbumEnrichment( ArtworkFallbackAlbumEnrichment( DiscogsAlbumEnrichment ) )
```

Each layer is a small interface (`AlbumEnrichmentPort` in `src/discogs.ts:3`) — a hand-rolled decorator pipeline with clear seams for testing.

### The scan pipeline (`src/scanPipeline.ts:13`)

Per request:

1. `readScanImage` (`src/http.ts:10`) validates the multipart upload: must be `image/jpeg|png|webp`, non-empty, ≤ 8 MB, else throws a typed `RequestError` mapped to `415 / 400 / 413`.
2. **Recognition** — `OpenAIAlbumRecognition.recognize` (`src/openaiRecognition.ts:32`) posts the image as a base64 data URL to OpenAI's Responses API (`gpt-5-mini` by default) with a **strict JSON schema** (`recognitionSchema`, `src/openaiRecognition.ts:188`). Only 3 statuses are legal: `safe_to_buy | ambiguous | no_match`, plus `confidence ∈ [0,1]`, one `album`, and up to 5 `candidates`. The prompt (`src/openaiRecognition.ts:14`) explicitly tells the model to identify the album only and *not* to hallucinate Discogs/MusicBrainz metadata — that's the enrichment layer's job.
3. **Enrichment**, wrapped in `withTimeout` (default 12 s, `SCAN_ENRICHMENT_TIMEOUT_MS`, `src/runtimeConfig.ts`). Runs against both the primary album and every candidate:
   - `DiscogsAlbumEnrichment` (`src/discogs.ts`): searches `/database/search` using artist/title/format/country/year/label/catno/barcode, retries once stripping parentheticals from the title, then fetches `/releases/{id}` and merges the full release (labels, catalog number, tracklist, identifiers, images, companies, data quality). Uses `signal` from `AbortController` so a timeout cancels the outbound HTTP.
   - `ArtworkFallbackAlbumEnrichment` (`src/artworkFallback.ts:56`): if Discogs left artwork or a listening link empty, tries Cover Art Archive by MBID for front/back covers, then iTunes Search for artwork + an Apple Music album URL; if that fails too, synthesizes an `https://music.apple.com/search?term=…` link as a last resort.
   - `CachedAlbumEnrichment` (`src/cachedEnrichment.ts`): in-process LRU keyed by `discogs_release_id` → `mbid` → normalized `artist|title|year|format|catno`. Default 24 h TTL, 500 entries. **Single-flight** via a `pending` map so concurrent requests for the same album share one Discogs call (skipped when the caller passes an `AbortSignal`, to avoid one aborted call poisoning another).
4. If enrichment throws or times out, the response falls back to the pre-enriched recognition result and the timeout is surfaced as `timings.enrichment_timed_out: true` (`src/scanPipeline.ts:66`).
5. `toScanResponse` (`src/scanResponse.ts:4`) shapes the response:
   - `safe_to_buy` → return the single `album`, no `candidates`.
   - `ambiguous` → return `candidates`, no `album`.
   - Guarantees every returned album has at least one `listening_link` — falling back to an Apple Music search URL if none was found.
   - `confidence` is clamped into `[0,1]`.

Every response includes a UUID `request_id` and `Cache-Control: no-store`. Errors always use the same envelope `{ error: { code, message, retryable, request_id } }` (`src/scanResponse.ts:15`) — the client relies on `retryable` to decide whether to offer a retry button.

`/v1/enrich` is the same enrichment chain exposed directly, taking `{ album: {...} }` and returning the enriched album — used by the iOS app to enrich albums it discovered by *audio* (Shazam) rather than by cover scan.

Contracts required at boot: `OPENAI_KEY`, `DISCOGS_TOKEN` (throws at import time if missing, `src/index.ts:11`). Optional: `OPENAI_MODEL`, `SCAN_ENRICHMENT_TIMEOUT_MS`, `SCAN_INCLUDE_TIMINGS`, `SCAN_INCLUDE_DEBUG`, `ENRICHMENT_CACHE_TTL_MS/MAX_ENTRIES`, `HEALTH_INCLUDE_DEPLOYMENT`.

---

## 2. Infrastructure (`infrastructure/`)

Bicep, subscription-scope entrypoint `bicep/minimal-function.bicep` (Verified) creates `rg-deja-groove-dev-recognition` and calls `bicep/recognition-function.bicep`, which stands up:

- **Storage account** (`Standard_LRS`, shared-key **off**, OAuth default). One blob container `function-releases` for deployment packages.
- **Key Vault** with RBAC auth, soft-delete 7 d. Secrets: `openai-key` (always), `DISCOGS-TOKEN` (only if a new value is passed; otherwise it references the existing secret).
- **App Insights** (optional, RetentionInDays 30).
- **Serverfarm** `FC1 / FlexConsumption`, Linux Node 22.
- **Function App** with SystemAssigned identity. App settings pull secrets via `@Microsoft.KeyVault(SecretUri=…)`. Storage auth uses `AzureWebJobsStorage__credential=managedidentity`.
- **Role assignments** on the identity: Storage Blob Data Owner + Queue + Table Contributor on the storage account; Key Vault Secrets User on the vault. If the deployer principal object id is passed, it also gets Storage Blob Data Contributor so it can upload packages.

Deploy is a two-phase script `infrastructure/scripts/deploy.sh`:

1. Runs `validate.sh` (Bicep lint / preflight).
2. Subscription-scope Bicep deploy.
3. `package-function.sh` → `npm ci && tsc && npm prune --omit=dev` → zips `host.json`, `package.json`, `package-lock.json`, `node_modules`, `dist` into `.artifacts/recognition-proxy.zip`, embedding a `deployment-marker.json` with the deployment name.
4. Uploads the zip with `--auth-mode login` (retries up to 30× waiting for RBAC propagation — a real quirk of fresh managed identities).
5. Mints a short-lived user-delegation SAS and calls `function-onedeploy.bicep`, which posts to `Microsoft.Web/sites/extensions/onedeploy` with the SAS URI.
6. Post-verify: `az rest` to confirm the `DISCOGS_TOKEN` Key Vault reference resolved; polls `/health` (matching `deployment.packageVersion` against the deployment name) and checks that `/v1/scan` returns 401/403 without a function key.

---

## 3. iOS app (`ios/`)

Two Swift packages consumed by an Xcode app target (`ios/DejaGroove/`):

- **`DejaGrooveApp`** — the actual app (SwiftUI, iOS 17+, `Package.swift:5`), split into `App/`, `Core/`, `Features/{Scan, Discovery, Collection, Wishlist}/`.
- **`DejaGrooveAuth`** — an Entra External ID (CIAM) OAuth Authorization Code + PKCE client with a Keychain session store. It's **not currently wired into `DejaGrooveApp`** — no dependency in `Package.swift`, nothing imports it from the app target. It exists as reviewed infrastructure waiting for a future authenticated backend (Verified via absence).

### Boot & configuration (`ios/DejaGroove/DejaGrooveApp.swift:5`)

`AppConfiguration.load()` (`ios/DejaGroove/AppConfiguration.swift:23`) reads three Info.plist keys — `DEJA_GROOVE_RUNTIME_MODE` (must be `local_proxy`), `DEJA_GROOVE_RECOGNITION_PROXY_BASE_URL` (must be HTTPS, not `.example`), `DEJA_GROOVE_RECOGNITION_PROXY_KEY` (must not be a `REPLACE_…` placeholder). On failure the app shows `StartupConfigurationErrorView` instead of the tab bar; on success it constructs the `ApiClient` and hands it to `DejaGrooveRootView`.

### The layered API client (`Core/`)

`ApiClient` (`Core/ApiClient.swift:9`) is a single protocol covering scan, resolve, collection CRUD, crate collections, wishlist, and Apple Music helpers. The production implementation `LocalProxyApiClient` (`Core/LocalProxyApiClient.swift:23`) composes four smaller ports:

- `LocalScanRuntime` → `RecognitionProxyScanRuntime` (`Core/RecognitionProxyScanRuntime.swift`) — builds the multipart body by hand, `POST`s to `{baseURL}/v1/scan` with `x-functions-key`, decodes `ScanResponse`. `resolve(...)` doesn't hit the network at all: it synthesizes a `safe_to_buy` result locally from the candidate the user picked.
- `LocalCollectionStore` → `PersistentLocalCollectionStore` (a Swift `actor`) — reads/writes a single JSON document at `Application Support/DejaGroove/collection.json`. Enforces duplicate detection via `LocalCollectionRules.isDuplicate` (throws `409 collection_duplicate` unless `addAnyway`), does version bumps, and manages "crate collections" (named record groupings, unique names) with cascade cleanup on record delete.
- `LocalWishlistStore`, `LocalDiscoveryStore` — same shape, separate JSON files.

The clever bit is `decorateScanResponse` (`Core/LocalProxyApiClient.swift:126`): after every scan/resolve, the client reruns the recognized album through the local stores and *overrides* the status. `safe_to_buy` becomes `owned` if it's already in the crate, `wishlist_match` if it's on the wishlist, `discovery_match` if it's in discovery history. `ScanResponse.canAddToCollection/canAddToWishlist` (`Core/Models.swift:271`) drive the UI buttons off those synthesized statuses. The Function itself never knows about the user's crate.

Wire compatibility with the Function: JSON keys are snake_case in the wire format, camelCase on the Swift side, bridged by explicit `CodingKeys` and hand-written `init(from:)/encode(to:)` (`Core/Models.swift:96`). The decoder validates that `status` is one of the six known values and rejects anything else — a defensive check against schema drift.

### Features

`DejaGrooveRootView` (`App/DejaGrooveRootView.swift`) is a `TabView` with five tabs: **Scan, Discover, My Crate, Wishlist, Collections**. Each screen has an MVVM pair (`FooView` + `FooViewModel`).

- **Scan** — `ScanView` uses `CameraCaptureView` / photo library, calls `ScanViewModel.submitScan` (`Features/Scan/ScanViewModel.swift:19`), which drives a state machine `idle → loading(uploading|recognizing|resolving) → result | error`, tracks `isLastErrorRetryable` off the Function's error envelope, and offers add-to-collection / add-to-wishlist / save-to-discovery actions.
- **Discover** — Uses `ShazamKitAudioDiscoveryService` (`Core/DiscoveryServices.swift:410`) to identify playing audio via `AVAudioEngine` + `SHSession` (25 s timeout, mic permission check on iOS). Matched tracks are turned into album candidates by `MusicKitAlbumCandidateResolver` → falls back to `AppleMusicAlbumCandidateResolver` (iTunes Search API) → falls back to `LocalAlbumCandidateResolver`. The selected candidate is then sent to `/v1/enrich` via `RecognitionProxyAlbumMetadataEnricher` (`Core/DiscoveryServices.swift:105`) to pull in Discogs metadata, then can be added to wishlist. `AppleMusicLibraryAddButton` uses `MusicKitAppleMusicLibraryAdder` (`Core/DiscoveryServices.swift:359`) to write to the user's Apple Music library when a catalog id is known.
- **My Crate / Wishlist / Collections** — pure local UI over the persistent stores; search, sort by artist family name, and grouping into named "crates".

### Auth package (not wired)

`DejaGrooveAuth` implements OAuth Authorization Code + PKCE against Entra External ID (`EntraTokenProvider.swift`): builds `authorize` URL with PKCE `code_challenge`, hands off to an `AuthorizationCodeRequesting` protocol (backed by `ASWebAuthenticationSession` in prod), exchanges code + refresh grants at `oauth2/v2.0/token`, extracts the `sub` claim from the id_token without validating signature (server is expected to do full JWT validation). `AuthSessionManager` (`AuthSessionManager.swift`) is a `@MainActor` state machine: `unauthenticated → authenticating → authenticated | reauthenticationRequired(reason)` with `refreshIfNeeded()` and a Keychain-backed `SecureSessionStore`. RFC 6749 error codes are mapped to `invalidCredentials` vs `providerConfiguration` so the UI doesn't loop on non-recoverable failures.

---

## 4. CI/CD (`.github/workflows/`)

Eleven workflows. The load-bearing ones:

- **`ci.yaml`** — runs on every PR: changeset-check, several Node/Bash script self-tests (codex-review, release computation, iOS project validation, fastlane scripts).
- **`ios-tests.yml`** — macOS-15, `swift test --parallel` in both `ios/DejaGrooveAuth` and `ios/DejaGrooveApp` when anything under `ios/**` changes.
- **`infrastructure-validate.yaml`** / **`iac-lint.yaml`** — Bicep lint + preflight on PRs.
- **`infrastructure-deploy-dev.yaml`** — pushes to `main` touching `infrastructure/**` or `functions/**` deploy dev via OIDC (`azure/login` with client-id/tenant-id/subscription-id), runs the recognition-proxy tests, invokes `infrastructure/scripts/deploy.sh` end-to-end.
- **`ios-testflight.yml`**, **`release.yml`**, **`pr-checks.yaml`** — release + TestFlight distribution; there's a `.changeset/` directory driving semver/release notes.
- **`codex-pr-review.yaml`** / **`ensure-codex-ruleset.yaml`** / **`auto-sort-project.yml`** — Codex-assisted PR review and repo/board hygiene.

`.githooks/`, `scripts/setup-hooks.sh`, `scripts/regression-suite.sh`, `scripts/smoke-ios-app-assembly.sh` are local dev conveniences.

---

## The overall shape

```
iOS app  ──multipart JPG──▶  POST /v1/scan  ──▶  OpenAI Responses (gpt-5-mini)
                                    │                    │
                                    │        strict JSON: status/confidence/album/candidates
                                    ▼
                             enrichment chain:
                             Cache ▶ Discogs ▶ CoverArtArchive/iTunes ▶ Apple-Music-search fallback
                                    │
                                    ▼
                             ScanResponse (album or candidates, ≥1 listening_link, request_id)
                                    │
                                    ▼
iOS decorates status  ──▶  status becomes owned / wishlist_match / discovery_match from LOCAL JSON stores
                                    │
                                    ▼
                             Local JSON files in Application Support:
                               collection.json  (records + crate collections)
                               wishlist.json
                               discovery.json
```

The Function is the only network dependency for the golden path. The "backend" you'd expect (users, cloud collection, RBAC, EF Core, .NET) hasn't been built — the empty `backend/src/*` folders and the unwired `DejaGrooveAuth` package are placeholders for that future direction; today, everything user-owned lives on the phone.
