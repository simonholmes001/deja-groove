# Deja Groove Minimal Infrastructure

The legacy .NET backend, APIM, App Service container, PostgreSQL, Key Vault,
and VNet infrastructure has been retired from the active repository.

The active target is a minimum-cost Azure Function recognition proxy. Key Vault
holds the project OpenAI API key and Discogs token, and the Function reads them
via Key Vault references. The Function performs OpenAI album recognition and
optional Discogs metadata enrichment. The iOS app owns collection state, scan
state, duplicate detection, and local persistence.

## Scope

- Dev region: `swedencentral`
- Deployment scope: subscription
- Active runtime target: Azure Function App
- Secret store: Azure Key Vault with RBAC authorization
- Azure resource access: Function system-assigned managed identity
- Observability: minimal Application Insights for Function request/error/timing diagnostics
- Required pipeline secret: `OPENAI_KEY`
- Required Key Vault secret for Discogs enrichment: `DISCOGS-TOKEN`
- `POST /v1/scan` requires an Azure Functions key; `GET /health` is anonymous.
- Out of scope: hosted collection API, PostgreSQL, APIM, App Service
  containers, container registry, Entra-backed API auth, and private network
  topology.

## Directory

```
infrastructure/
├── bicep/
│   ├── minimal-function.bicep      # subscription-scope RG bootstrap
│   ├── function-onedeploy.bicep    # Flex Consumption code deployment
│   ├── recognition-function.bicep  # Function resources in the recognition RG
│   └── parameters/
│       └── dev.bicepparam
└── scripts/
    ├── package-function.sh         # builds and zips the Function app
    ├── validate.sh                 # minimal Function lint/validate/what-if
    └── deploy.sh                   # dev infra deploy + Function publish
```

Dev resources are created in `rg-deja-groove-dev-recognition`, keeping the
recognition proxy isolated from any future platform or app concerns.

## Required Secrets/Vars

For GitHub OIDC login:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

For Function App configuration:

- `OPENAI_KEY` (pipeline secret, written into Key Vault during deployment)
- `DISCOGS-TOKEN` (Key Vault secret, manually created in the vault; exposed to the Function as `DISCOGS_TOKEN`)
- `SCAN_ENRICHMENT_TIMEOUT_MS` defaults to `4000`.
- `ENRICHMENT_CACHE_TTL_MS` defaults to `86400000` for a 24-hour warm-instance metadata/artwork cache.
- `ENRICHMENT_CACHE_MAX_ENTRIES` defaults to `500`.
- `enableApplicationInsights` is enabled for dev to capture request status,
  Function errors, scan timings, and recognition failure diagnostics.

Managed identity and RBAC:

- Function identity reads `openai-key` and `DISCOGS-TOKEN` from Key Vault via `Key Vault Secrets User`.
- Function identity accesses host/deployment storage via Storage Blob Data Owner, Storage Queue Data Contributor, and Storage Table Data Contributor.
- Storage shared key access is disabled; Function storage uses identity-based settings.

For scan calls after deployment:

- Use an Azure Functions key through the `x-functions-key` header.

The enrichment cache is in-memory per warm Function instance. It reduces
repeated Discogs/Cover Art Archive/iTunes lookups during active testing, but it
is not durable and may be empty after scale-out or cold start.

## Observability

Dev deployments create an Application Insights resource named
`appi-deja-recognition-dev`. The Function writes scan completion events,
recognition failures, metadata timeout warnings, request IDs, and scan timing
fields there. Logs must not include image payloads, OpenAI responses, API keys,
Discogs tokens, or other secrets.

Telemetry is intentionally minimal: the Function host samples telemetry in
`functions/recognition-proxy/host.json`, keeps requests visible, and the
Application Insights resource uses 30-day retention.

## Pipeline Behavior

- `infrastructure-validate.yaml`: PR-time minimal Function lint/validate/what-if,
  runs when `minimal-function.bicep` exists.
- `infrastructure-deploy-dev.yaml`: push-to-main and manual dev deployment
  using `infrastructure/scripts/deploy.sh dev`; deploys infrastructure and publishes Function code after validation.
- `ios-testflight.yml`: manual internal TestFlight upload. The workflow writes
  `ios/DejaGroove/Config/Release.local.xcconfig` from GitHub secrets before
  archiving so Release builds use the live Function proxy URL and key without
  committing secrets.

Flex Consumption code publish uses One Deploy. The deploy script uploads the
ready-to-run package to the configured deployment blob container as
`released-package.zip`, invokes the `Microsoft.Web/sites/extensions/onedeploy`
resource, then verifies `GET /health` and the protected `POST /v1/scan`
without a function key.

## TestFlight

Run the **iOS TestFlight** workflow manually from GitHub Actions after these
repository secrets are configured:

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
- `DEJA_GROOVE_XCODE_PROJECT` (`ios/DejaGroove.xcodeproj`)
- `DEJA_GROOVE_XCODE_SCHEME` (`DejaGroove`)
- `DEJA_GROOVE_RECOGNITION_PROXY_BASE_URL`
- `DEJA_GROOVE_RECOGNITION_PROXY_KEY`

Set either `DEJA_GROOVE_XCODE_PROJECT` or `DEJA_GROOVE_XCODE_WORKSPACE`, not
both. The workflow uses the GitHub run number as the TestFlight build number so
repeated uploads do not reuse `CFBundleVersion`.

`MATCH_PASSWORD` decrypts the Fastlane Match signing repository contents.
`MATCH_KEYCHAIN_PASSWORD` unlocks the temporary macOS keychain that GitHub
Actions creates for importing Apple signing certificates during the build.
`MATCH_GIT_BASIC_AUTHORIZATION` authenticates GitHub Actions to clone that
private signing repository when `MATCH_GIT_URL` uses HTTPS. Set it to the base64
encoding of `<github-username>:<fine-grained-token-with-repo-read-access>`.

## Local Usage

```bash
# Validate dev
./infrastructure/scripts/validate.sh dev

# Validate + what-if
./infrastructure/scripts/validate.sh dev --what-if

# Deploy dev infrastructure and Function code
./infrastructure/scripts/deploy.sh dev
```
