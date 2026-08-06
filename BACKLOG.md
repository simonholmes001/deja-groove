# Minimal Azure Proxy iPhone Runtime Backlog

## Context

The current Azure-hosted runtime is too expensive for the product's current
stage. The revised target is not a hosted application backend and not a pure
BYOK client. The app should keep user data and workflow state on the iPhone,
while Azure is reduced to the smallest viable secret-holding runtime for OpenAI
API calls.

## Target Architecture

```text
iPhone app
  - Stores collection data locally with SwiftData, Core Data, or SQLite
  - Captures and prepares album-cover images
  - Performs local image validation, hashing, caching, ownership checks, and scan state
  - Calls a minimal Azure Function only for OpenAI recognition
  - Stores scan results, ambiguity state, and collection records locally

Minimal Azure runtime
  - One HTTP-triggered Azure Function for album recognition
  - Stores the project-owned OpenAI API key in Function App configuration
  - Calls OpenAI and returns normalized candidates
  - Does not store user collection data, scan history, images, or account state
  - Does not require APIM, PostgreSQL, App Service containers, Entra user auth, or VNet
```

The intended Azure footprint is one Function App on a consumption-style plan,
one required storage account, application settings for secrets, and optional
Application Insights if diagnostics are worth the small extra cost. Key Vault,
APIM, PostgreSQL, container registry, managed database networking, and
containerized API deployment are out of scope for the minimum runtime.

## Current Main Branch Starting Point

- The iOS app already depends on the `ApiClient` protocol for scan, resolve,
  collection add/list, and collection patch operations.
- `LiveApiClient` still supports hosted `/v1/scan` and `/v1/collection`
  endpoints for comparison against existing deployed environments.
- The legacy .NET backend has been removed from the active repository. Any
  remaining behavior needed for the new runtime should be reimplemented in the
  iOS app or the minimal Function, not carried forward as .NET backend code.
- The old hosted runtime behavior that now belongs on the phone includes
  collection persistence, ownership checks, scan cache, and ambiguity
  resolution state.

The migration should keep the iOS UI stable by introducing a local/proxy-backed
implementation behind the existing `ApiClient` protocol before deleting the old
hosted runtime.

## Recommended Migration Slices

### 1. iPhone Runtime Wiring

Add a runtime mode that keeps collection and scan workflow state local while
using a minimal Azure recognition proxy. Keep `LiveApiClient` in place until the
new runtime proves scan and collection parity.

### 2. Minimal Azure Function Recognition Proxy

Create the smallest proxy that can safely hold the OpenAI API key:

- `POST /api/recognize-album`
- accepts one prepared image payload
- validates request size and content type
- calls OpenAI using the server-side key
- returns normalized candidate data only
- emits request/correlation IDs and minimal diagnostics
- stores no user collection data, original images, or scan history

Use Function-level authentication or a similarly small access control mechanism
for the first private build. Stronger abuse controls can be added later if the
app becomes public.

### 3. OpenAI Secret Configuration

Store the project-owned OpenAI API key only in Azure Function App configuration
for the minimal version. Avoid putting the key in the iOS app, source control,
GitHub Actions logs, or local settings committed to the repo. Key Vault can be
deferred unless policy or operational needs justify the extra resource.

### 4. Local Collection Persistence

Replace hosted collection API calls with local storage for collection records.
The local store must support add, list/search, patch format/notes, timestamps,
and duplicate detection.

### 5. Local Confidence Mapping

Port `RecognitionResultMapper` into Swift so scan status decisions stay local:

- no usable candidates -> `no_match`
- top confidence below `0.40` -> `no_match`
- runner-up within `0.10` of top candidate -> `ambiguous`
- top confidence above the domain threshold -> `safe_to_buy`

### 6. Local Scan Workflow And Cache

Port the phone-owned parts of `ScanWorkflowUseCase` into Swift:

- validate image input
- compute an image hash
- check local scan cache
- call the Azure recognition proxy on cache miss
- check local collection ownership
- persist scan event/cache/ambiguity state locally
- return existing `ScanResponse` models to the UI

### 7. Local Ambiguous Result Resolution

Persist ambiguous candidates by request ID and resolve selections locally. The
existing `ScanViewModel.resolve(...)` flow should continue to work through the
`ApiClient` abstraction.

### 8. Remove Hosted Auth From iOS Runtime

Remove Entra authentication from the iPhone happy path. Keep the auth package
temporarily if needed during migration, then delete it once no local/proxy
runtime path depends on it.

### 9. Minimal Azure Deployment And Cost Guardrails

Replace the current Azure deployment path with a deliberately small Function
deployment:

- no APIM
- no PostgreSQL
- no backend container registry or App Service container deployment
- no always-on compute
- explicit budget alert or manual cost check before wider testing
- documented teardown command/process

### 10. Legacy Runtime Decommission Plan

Document and execute shutdown of the old Azure runtime:

- stop or delete App Service/APIM/PostgreSQL/Key Vault resources no longer used
- keep backend container publish and large infrastructure deploy workflows removed
- keep legacy .NET backend source out of the active repository

## Product And Privacy Notes

- The project-owned OpenAI key stays server-side in Azure.
- The app must clearly explain that cover images are sent to the app's Azure
  recognition proxy and then to OpenAI for recognition.
- Do not store original cover images in Azure.
- Do not store original cover images locally by default.
- Cross-device sync is out of scope unless CloudKit/iCloud sync is added later.

## Open Decisions

- Use SwiftData, Core Data, or SQLite for local persistence.
- Implement the Azure Function in TypeScript.
- Use Azure Functions Flex Consumption or the lowest acceptable consumption
  option for the final subscription/region constraints.
- Add iCloud/CloudKit sync now or defer until after local-only storage works.

## Proposed GitHub Issue Set

All new issues for this migration should remain clearly marked with both:

- title prefix: `[NEW]`
- label: `NEW`

Updated issue list:

- #160 `[NEW] Migrate app to iPhone-local runtime with minimal Azure proxy`
- #161 `[NEW] Add iPhone-local runtime mode behind ApiClient`
- #162 `[NEW] Configure OpenAI secret handling for minimal Azure proxy`
- #163 `[NEW] Implement local collection persistence`
- #164 `[NEW] Implement minimal Azure Function album recognition proxy`
- #165 `[NEW] Port scan confidence mapping to Swift`
- #166 `[NEW] Implement local scan workflow and proxy-backed cache`
- #167 `[NEW] Implement local ambiguous scan resolution`
- #168 `[NEW] Remove hosted auth dependency from iOS runtime`
- #169 `[NEW] Replace legacy Azure runtime with minimum-cost Function deployment`
