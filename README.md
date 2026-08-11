# Déjà Groove

[![CI](https://github.com/simonholmes001/deja-groove/actions/workflows/ci.yaml/badge.svg)](https://github.com/simonholmes001/deja-groove/actions/workflows/ci.yaml)
[![iOS Tests](https://github.com/simonholmes001/deja-groove/actions/workflows/ios-tests.yml/badge.svg)](https://github.com/simonholmes001/deja-groove/actions/workflows/ios-tests.yml)
[![iOS TestFlight](https://github.com/simonholmes001/deja-groove/actions/workflows/ios-testflight.yml/badge.svg)](https://github.com/simonholmes001/deja-groove/actions/workflows/ios-testflight.yml)
[![Infrastructure Validate](https://github.com/simonholmes001/deja-groove/actions/workflows/infrastructure-validate.yaml/badge.svg)](https://github.com/simonholmes001/deja-groove/actions/workflows/infrastructure-validate.yaml)
[![Dev Infrastructure Deploy](https://github.com/simonholmes001/deja-groove/actions/workflows/infrastructure-deploy-dev.yaml/badge.svg)](https://github.com/simonholmes001/deja-groove/actions/workflows/infrastructure-deploy-dev.yaml)
[![Release](https://github.com/simonholmes001/deja-groove/actions/workflows/release.yml/badge.svg)](https://github.com/simonholmes001/deja-groove/actions/workflows/release.yml)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![iOS 17+](https://img.shields.io/badge/iOS-17%2B-blue)
![Node 22+](https://img.shields.io/badge/Node.js-22%2B-green)
![Azure Functions](https://img.shields.io/badge/Azure-Functions-0078D4)

Déjà Groove is an iPhone-first record-store companion for vinyl collectors. Scan an album cover, identify the release, check whether it is already in your crate, save it locally, and organize it into collections.

The current product direction is deliberately local-first: the iOS app owns the user's crate, collections, duplicate detection, and local persistence. Azure is reduced to a small recognition proxy that keeps provider secrets off the phone and calls OpenAI plus optional metadata/artwork providers.

## Why This Exists

Record shopping is fast, noisy, and often network-constrained. The useful question is not just "what album is this?", but "do I already own this version, and where does it fit in my collection?"

Déjà Groove focuses on that workflow:

- identify a record from a cover image
- flag duplicate ownership at scan time
- enrich album details with release metadata and artwork
- save albums into a local crate on the iPhone
- organize albums into named collections
- keep the hosted cloud footprint minimal until the product needs sync or collaboration

## Current Status

The app is usable through TestFlight/internal iPhone testing. The active runtime is:

- iOS app in `local_proxy` mode
- local My Crate and Collections storage on device
- Azure Function recognition proxy for scan inference
- OpenAI recognition with Discogs metadata enrichment
- Cover Art Archive and iTunes artwork fallback
- automatic internal TestFlight upload on iOS-related pushes to `main`

This is not yet a public App Store-ready product. The remaining work is mostly privacy/compliance, accessibility, local data hardening, and product polish rather than core proof of concept.

## Features

- Scan album covers from camera or existing photos.
- See scan states: `SAFE TO BUY`, `DUPLICATE`, `AMBIGUOUS`, and `NO MATCH`.
- Resolve ambiguous release candidates manually.
- Add albums to My Crate.
- View album artwork and release details.
- Edit locally stored album information.
- Delete albums and uploaded local cover images.
- Create, rename, delete, and browse collections.
- Add/remove albums from collections.
- Search and filter crate content.
- Sort album lists by artist family name.
- Build and distribute internal TestFlight builds through CI.

## Repository Layout

```text
.
├── ios/
│   ├── DejaGroove.xcodeproj        # installable iOS app project
│   ├── DejaGroove/                 # app entry point, assets, xcconfig files
│   ├── DejaGrooveApp/              # Swift package for app UI/domain/runtime
│   ├── DejaGrooveAuth/             # legacy hosted auth package
│   └── fastlane/                   # TestFlight signing and upload lanes
├── functions/
│   └── recognition-proxy/          # TypeScript Azure Function recognition proxy
├── infrastructure/
│   ├── bicep/                      # minimal Azure Function infrastructure
│   └── scripts/                    # validate, package, deploy scripts
├── docs/
│   ├── operations/                 # runbooks for TestFlight, identity, releases
│   └── identity/                   # identity notes from hosted-runtime era
├── scripts/                        # local helper scripts
└── BACKLOG.md                      # local-first migration backlog context
```

## Architecture

```text
             ┌──────────────────────────────────────────────┐
             │                  iPhone App                  │
             │                                              │
             │  Scan UI  ── My Crate ── Collections         │
             │     │             │             │            │
             │     └─────────────┴─────────────┘            │
             │          local persistence + duplicate checks │
             └──────────────────────┬───────────────────────┘
                                    │ HTTPS + Function key
                                    ▼
             ┌──────────────────────────────────────────────┐
             │        Azure Function Recognition Proxy       │
             │                                              │
             │  request validation, image handling, logs     │
             │  OpenAI recognition, metadata/artwork enrich  │
             └───────────────┬───────────────┬──────────────┘
                             │               │
                             ▼               ▼
                         OpenAI API       Discogs / artwork fallbacks
```

### Design Principles

- **Local-first user data:** crate and collection state live on the iPhone.
- **Small cloud surface:** Azure exists primarily to protect API keys and normalize scan responses.
- **No committed secrets:** local Function keys live in ignored `.xcconfig` files; CI secrets live in GitHub Actions and Azure Key Vault.
- **Provider data is nullable:** Discogs/artwork metadata varies by release; UI and persistence must tolerate missing fields.
- **Release automation over manual drift:** GitHub Actions owns validation, releases, and TestFlight uploads.

## Prerequisites

For iOS development:

- macOS with Xcode that supports Swift 6
- iOS 17+ device or simulator
- GitHub CLI if working with PRs/issues locally

For the recognition proxy:

- Node.js 22+
- Azure Functions Core Tools if running the Function locally
- Azure access for deployed dev infrastructure

For TestFlight:

- Apple Developer Program membership
- App Store Connect app for `com.dejagroove.app`
- Fastlane Match signing repository and required GitHub secrets

## Installation

Clone the repository:

```bash
git clone https://github.com/simonholmes001/deja-groove.git
cd deja-groove
```

Install Function dependencies:

```bash
cd functions/recognition-proxy
npm ci
npm run build
npm test
```

Install iOS Fastlane dependencies:

```bash
cd ios
bundle install
```

Open the iOS project:

```bash
open ios/DejaGroove.xcodeproj
```

Select the `DejaGroove` scheme and run on a connected iPhone or simulator.

## Local iPhone Testing From Xcode

Debug builds use the deployed recognition proxy through `local_proxy` mode. To run on a physical iPhone without using Azure CLI:

1. In the Azure Portal, open the Function App.
2. Copy the default Function key from **App keys**.
3. Copy `ios/DejaGroove/Config/Debug.local.example.xcconfig` to `ios/DejaGroove/Config/Debug.local.xcconfig`.
4. Replace `REPLACE_WITH_AZURE_FUNCTION_DEFAULT_KEY` with the copied key.
5. Open `ios/DejaGroove.xcodeproj`.
6. Select the `DejaGroove` scheme and your connected iPhone.
7. Build and run.

`Debug.local.xcconfig` is ignored by git. Do not commit real Function keys.

## Usage

1. Open the app.
2. Go to **Scan**.
3. Tap **Pick or Capture Cover**.
4. Choose a cover image or capture one with the camera.
5. Review the recognition result.
6. Add safe results to **My Crate**, or resolve ambiguous candidates.
7. Use **My Crate** to search, filter, edit, delete, and assign albums to collections.
8. Use **Collections** to create named groupings and manage membership.

TestFlight builds expire after 90 days, but local app data is not removed by normal TestFlight updates. Data can be lost if the app is deleted from the device, the bundle identifier changes, or a future migration bug corrupts local storage.

## Development Commands

Run Swift package tests:

```bash
cd ios/DejaGrooveAuth
swift test --parallel

cd ../DejaGrooveApp
swift test --parallel
```

Run Function tests:

```bash
cd functions/recognition-proxy
npm ci
npm test
```

Run repository readiness checks:

```bash
bash .github/scripts/ios-distribution-readiness.sh
bash .github/scripts/validate-ios-project.sh
```

Validate infrastructure:

```bash
./infrastructure/scripts/validate.sh dev
./infrastructure/scripts/validate.sh dev --what-if
```

Deploy dev infrastructure and Function code:

```bash
./infrastructure/scripts/deploy.sh dev
```

## TestFlight Delivery

The `iOS TestFlight` workflow uploads internal builds.

It runs automatically when iOS-related changes are pushed to `main` and can also be run manually from GitHub Actions.

Required repository secrets include:

- `DEJA_GROOVE_APP_IDENTIFIER`
- `DEJA_GROOVE_APPLE_ID`
- `DEJA_GROOVE_ITC_TEAM_ID`
- `DEJA_GROOVE_TEAM_ID`
- `MATCH_GIT_URL`
- `MATCH_PASSWORD`
- `MATCH_KEYCHAIN_PASSWORD`
- `MATCH_GIT_BASIC_AUTHORIZATION`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_KEY_BASE64`
- `DEJA_GROOVE_XCODE_PROJECT` or `DEJA_GROOVE_XCODE_WORKSPACE`
- `DEJA_GROOVE_XCODE_SCHEME`
- `DEJA_GROOVE_RECOGNITION_PROXY_BASE_URL`
- `DEJA_GROOVE_RECOGNITION_PROXY_KEY`

See [docs/operations/ios-testflight-runbook.md](docs/operations/ios-testflight-runbook.md) for setup details.

## Configuration And Secrets

Local app configuration is controlled through Xcode `.xcconfig` files:

- `ios/DejaGroove/Config/Debug.xcconfig`
- `ios/DejaGroove/Config/Release.xcconfig`
- ignored local overrides: `Debug.local.xcconfig` and `Release.local.xcconfig`

The Azure Function reads:

- `OPENAI_KEY` from Key Vault as `openai-key`
- `DISCOGS-TOKEN` from Key Vault as `DISCOGS_TOKEN`
- optional scan/enrichment timeout and cache settings

Never commit API keys, Function keys, Apple signing secrets, Match passwords, or App Store Connect private keys.

## What We Should Do Next

The app now works well enough for real personal TestFlight use. The next work should focus on making that use durable, compliant, and trustworthy.

### 1. Protect User Data And Upgrade Safety

Priority: highest product risk.

- [#176](https://github.com/simonholmes001/deja-groove/issues/176) Harden local My Crate storage schema.
- [#63](https://github.com/simonholmes001/deja-groove/issues/63) Implement offline cache and stale-data indicators.

Why now: users can start storing real collections. Local data loss or bad migrations would be more damaging than missing secondary features.

### 2. Finish Privacy, Trust, And App Store Readiness

Priority: required before broader testing or public release.

- [#92](https://github.com/simonholmes001/deja-groove/issues/92) Draft, publish, and integrate privacy policy.
- [#96](https://github.com/simonholmes001/deja-groove/issues/96) Implement Apple Privacy Manifest.
- [#99](https://github.com/simonholmes001/deja-groove/issues/99) Prepare App Store Connect listing.
- [#65](https://github.com/simonholmes001/deja-groove/issues/65) Implement telemetry consent and privacy controls UI.

Why now: cover images and recognition provider calls need clear disclosure before inviting more testers.

### 3. Accessibility And Real-World Usability

Priority: important MVP quality gate.

- [#23](https://github.com/simonholmes001/deja-groove/issues/23) Accessibility compliance implementation.
- [#66](https://github.com/simonholmes001/deja-groove/issues/66) Localization framework for core screens.

Why now: the app is visual and scan-heavy. VoiceOver, Dynamic Type, contrast, and non-color-only status cues should be fixed before design debt spreads.

### 4. Simplify The Runtime And Remove Legacy Paths

Priority: reduce complexity and maintenance risk.

- [#168](https://github.com/simonholmes001/deja-groove/issues/168) Remove hosted auth dependency from iOS runtime.
- [#169](https://github.com/simonholmes001/deja-groove/issues/169) Replace legacy Azure runtime with minimum-cost Function deployment.
- [#160](https://github.com/simonholmes001/deja-groove/issues/160) Migrate app to iPhone-local runtime with minimal Azure proxy.

Why now: the product has moved to local-first. Keeping hosted-era auth and infrastructure paths around makes every change harder to reason about.

### 5. Improve Scan Reliability And Latency

Priority: continue after data safety and compliance.

- [#165](https://github.com/simonholmes001/deja-groove/issues/165) Port scan confidence mapping to Swift.
- [#167](https://github.com/simonholmes001/deja-groove/issues/167) Implement local ambiguous scan resolution.
- [#162](https://github.com/simonholmes001/deja-groove/issues/162) Configure OpenAI secret handling for minimal Azure proxy.

Why now: scan quality is the core experience, but the current baseline is usable. The next improvements should be measured against real record-store testing rather than model changes made in isolation.

### 6. Add Basic Settings And Account Surfaces

Priority: useful once testing expands.

- [#64](https://github.com/simonholmes001/deja-groove/issues/64) Implement settings and account management screens.
- [#24](https://github.com/simonholmes001/deja-groove/issues/24) Deliver My Crate browsing experience.

Why now: users need a place to understand runtime, privacy, storage, app version, and support state.

## MVP Definition

Déjà Groove is an MVP when:

- a tester can install through TestFlight without developer help
- scanning works reliably enough for normal record-store conditions
- albums can be added, edited, deleted, searched, filtered, and grouped locally
- local data survives app updates
- privacy disclosures accurately describe image recognition and third-party providers
- accessibility basics pass for the core Scan, My Crate, and Collections flows
- CI can deploy the Function and publish TestFlight builds without manual repair

## Known Constraints

- Back cover text and artwork availability depend on provider metadata.
- TestFlight builds expire after 90 days and must be refreshed by a new upload.
- Local-only storage means there is no cross-device sync yet.
- Deleting the app from the iPhone removes local data.
- The recognition proxy should not store original cover images or user crate data.

## Release Process

Releases use semantic versioning with `vMAJOR.MINOR.PATCH` tags and GitHub Releases as the changelog source. Releasable PRs require changeset files.

See [docs/operations/releasing.md](docs/operations/releasing.md).

## Further Reading

- [Minimal infrastructure](infrastructure/README.md)
- [TestFlight runbook](docs/operations/ios-testflight-runbook.md)
- [Release process](docs/operations/releasing.md)
- [Local-first backlog](BACKLOG.md)
- [Product requirements](DejaGroove_PRD_v1.5.md)
