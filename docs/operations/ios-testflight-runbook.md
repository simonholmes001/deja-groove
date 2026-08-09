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
  - `MATCH_GIT_BASIC_AUTHORIZATION`
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
- One-time Match initialization command:

```bash
cd ios
DEJA_GROOVE_APP_IDENTIFIER="com.dejagroove.app" \
DEJA_GROOVE_APPLE_ID="<apple-id-email>" \
DEJA_GROOVE_ITC_TEAM_ID="<app-store-connect-team-id>" \
DEJA_GROOVE_TEAM_ID="<apple-developer-team-id>" \
MATCH_GIT_URL="<private-signing-repo-url>" \
MATCH_PASSWORD="<match-encryption-password>" \
bundle exec fastlane match appstore
```

- Read-only verification command:

```bash
cd ios
bundle install
bundle exec fastlane ios prepare_signing
```

This lane uses `match` in read-only mode and fails fast when required environment values are missing.
`MATCH_PASSWORD` decrypts the signing repository. If the signing repository is
private and CI clones it over HTTPS, set `MATCH_GIT_BASIC_AUTHORIZATION` to the
base64 encoding of `<github-username>:<fine-grained-token-with-repo-read-access>`.

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
```

This verifies all required files and expected workflow/fastlane hooks exist.

## Recognition Runtime

The legacy .NET backend, Docker Hub image, APIM gateway, App Service
container, and PostgreSQL runtime have been retired.

The target runtime is:

- iOS stores collection and scan state locally.
- A minimal Azure Function holds `OPENAI_KEY`.
- The Function performs only OpenAI album recognition and returns normalized candidates.

Until the minimal Function is implemented, keep the app in `hosted` mode only
for comparison against existing deployed environments. New iPhone-first
testing should target `local_proxy` mode once the Function endpoint exists.

## Local Xcode User Testing

Use this path for direct testing from Xcode on a physical iPhone. No Azure CLI
commands are required.

1. In the Azure Portal, open the Function App
   `func-deja-recognition-dev-yzoqh3gf`.
2. Open **App keys** and copy the `default` function key.
3. In the repository, copy
   `ios/DejaGroove/Config/Debug.local.example.xcconfig` to
   `ios/DejaGroove/Config/Debug.local.xcconfig`.
4. Replace `REPLACE_WITH_AZURE_FUNCTION_DEFAULT_KEY` in
   `Debug.local.xcconfig` with the copied key.
5. Open `ios/DejaGroove.xcodeproj` in Xcode.
6. Select the `DejaGroove` scheme and a connected iPhone as the run
   destination.
7. Build and run. The Debug build uses `local_proxy`, calls the deployed
   Function for recognition, and stores the collection locally on the device.

`Debug.local.xcconfig` is ignored by git. Do not put the real Function key in
`Debug.xcconfig`, `Release.xcconfig`, or any committed file.
