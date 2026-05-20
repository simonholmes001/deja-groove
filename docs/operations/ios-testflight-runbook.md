# iOS TestFlight Runbook

This runbook covers issue scope for #95, #96, and #97.

## Prerequisites

- Apple Developer account is active.
- App Store Connect app exists for the production bundle identifier.
- Repository secrets are configured:
  - `DEJA_GROOVE_APP_IDENTIFIER`
  - `DEJA_GROOVE_APPLE_ID`
  - `DEJA_GROOVE_ITC_TEAM_ID`
  - `DEJA_GROOVE_TEAM_ID`
  - `MATCH_GIT_URL`
  - `MATCH_PASSWORD`
  - `APP_STORE_CONNECT_API_KEY_ID`
  - `APP_STORE_CONNECT_API_ISSUER_ID`
  - `APP_STORE_CONNECT_API_KEY_BASE64`
  - `DEJA_GROOVE_XCODE_SCHEME`
  - `DEJA_GROOVE_XCODE_PROJECT` or `DEJA_GROOVE_XCODE_WORKSPACE` (set exactly one)

## Privacy Manifest (#96)

- Manifest file: `ios/DejaGrooveApp/PrivacyInfo.xcprivacy`
- Current declaration includes:
  - User ID collected for app functionality
  - UserDefaults required-reason API usage

Review and extend declarations whenever SDK usage changes.

## Signing and Profiles (#95)

- Fastlane lane: `prepare_signing`
- Command:

```bash
cd ios
bundle install
bundle exec fastlane ios prepare_signing
```

This lane uses `match` in read-only mode and fails fast when required environment values are missing.

## Internal TestFlight Upload (#97)

- Fastlane lane: `upload_internal_testflight`
- Command:

```bash
cd ios
bundle install
bundle exec fastlane ios upload_internal_testflight
```

The lane uploads to the `Internal` tester group and skips waiting for full processing.

## GitHub Actions Trigger

- Workflow: `.github/workflows/ios-testflight.yml`
- Trigger manually with `workflow_dispatch`.

## Local Readiness Gate

```bash
bash .github/scripts/validate-ios-project.sh
bash .github/scripts/ios-distribution-readiness.sh
bash .github/scripts/backend-container-readiness.sh
```

This verifies all required files and expected workflow/fastlane hooks exist.

## Backend Runtime (Docker Hub + Azure)

Before testing on iPhone, the Azure backend must run a real API image instead of a placeholder:

- Publish workflow: `.github/workflows/backend-container-publish.yml`
- Infra deploy secret: `DOCKER_IMAGE_REFERENCE`
- Expected image format: `<dockerhub-user>/deja-groove-api:<tag>`
- Image policy and promotion/retention contract: `docs/operations/container-image-policy.md`

For dev, set `DOCKER_IMAGE_REFERENCE` to a pushed image tag like:

`simonholmes001/deja-groove-api:dev-latest`

Then run or trigger `.github/workflows/infrastructure-deploy-dev.yaml`.

## Xcode iPhone API Endpoint

For real-device testing, set the app API base URL to APIM. Resolve the current gateway URL from the latest deploy output:

```bash
az deployment sub show \
  --name "<latest-deployment-name>" \
  --query "properties.outputs.apimGatewayUrl.value" -o tsv
```

Do not use the direct App Service hostname as the client base URL.
