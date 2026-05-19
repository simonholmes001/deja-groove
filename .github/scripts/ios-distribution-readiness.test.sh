#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/.github/scripts/ios-distribution-readiness.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

new_repo() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/ios/DejaGrooveApp" "$dir/ios/fastlane" "$dir/.github/workflows"
  echo "$dir"
}

run_check() {
  local repo="$1"
  (
    cd "$repo"
    bash "$SCRIPT"
  )
}

test_missing_required_files_fails() {
  local repo
  repo="$(new_repo)"
  if run_check "$repo"; then
    fail "expected failure when required files are missing"
  fi
}

test_required_files_present_passes() {
  local repo
  repo="$(new_repo)"

  cat > "$repo/ios/DejaGrooveApp/PrivacyInfo.xcprivacy" <<'JSON'
{}
JSON

  cat > "$repo/ios/fastlane/Appfile" <<'EOF_APP'
app_identifier(ENV.fetch("DEJA_GROOVE_APP_IDENTIFIER"))
apple_id(ENV.fetch("DEJA_GROOVE_APPLE_ID"))
itc_team_id(ENV.fetch("DEJA_GROOVE_ITC_TEAM_ID"))
team_id(ENV.fetch("DEJA_GROOVE_TEAM_ID"))
EOF_APP

  cat > "$repo/ios/fastlane/Fastfile" <<'EOF_FAST'
platform :ios do
  lane :verify_distribution_env do
    puts "ok"
  end

  lane :prepare_signing do
    sync_code_signing(type: "appstore", readonly: true)
  end

  lane :upload_internal_testflight do
    api_key = app_store_connect_api_key(
      key_id: ENV.fetch("APP_STORE_CONNECT_API_KEY_ID"),
      issuer_id: ENV.fetch("APP_STORE_CONNECT_API_ISSUER_ID"),
      key_filepath: ENV.fetch("APP_STORE_CONNECT_API_KEY_PATH")
    )
    build_app(scheme: "DejaGroove", project: ENV["DEJA_GROOVE_XCODE_PROJECT"], workspace: ENV["DEJA_GROOVE_XCODE_WORKSPACE"])
    upload_to_testflight(api_key: api_key, skip_waiting_for_build_processing: true)
  end
end
EOF_FAST

  cat > "$repo/.github/workflows/ios-testflight.yml" <<'EOF_WF'
name: iOS TestFlight
on:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  upload:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
      - uses: ruby/setup-ruby@97ecb7b512899eb71ab1bf2310a624c6f1589ac6
      - run: |
          key_path="$(mktemp /tmp/deja-groove-authkey.XXXXXX.p8)"
          chmod 600 "$key_path"
      - run: bash .github/scripts/validate-ios-project.sh
      - run: bundle exec fastlane ios upload_internal_testflight
      - run: rm -f "${APP_STORE_CONNECT_API_KEY_PATH:-}"
EOF_WF

  run_check "$repo" || fail "expected pass when required files are present"
}

test_fails_without_validate_script_hook() {
  local repo
  repo="$(new_repo)"

  cat > "$repo/ios/DejaGrooveApp/PrivacyInfo.xcprivacy" <<'JSON'
{}
JSON
  cat > "$repo/ios/fastlane/Appfile" <<'EOF_APP'
app_identifier("x")
apple_id("x")
itc_team_id("x")
team_id("x")
EOF_APP
  cat > "$repo/ios/fastlane/Fastfile" <<'EOF_FAST'
platform :ios do
  lane :verify_distribution_env do
  end
  lane :prepare_signing do
    sync_code_signing(type: "appstore", readonly: true)
  end
  lane :upload_internal_testflight do
    api_key = app_store_connect_api_key(key_id: "x", issuer_id: "x", key_filepath: "/tmp/x")
    build_app(scheme: "x", project: ENV["DEJA_GROOVE_XCODE_PROJECT"], workspace: ENV["DEJA_GROOVE_XCODE_WORKSPACE"])
    upload_to_testflight(api_key: api_key)
  end
end
EOF_FAST
  cat > "$repo/.github/workflows/ios-testflight.yml" <<'EOF_WF'
name: iOS TestFlight
on:
  workflow_dispatch:
permissions:
  contents: read
jobs:
  upload:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
      - uses: ruby/setup-ruby@97ecb7b512899eb71ab1bf2310a624c6f1589ac6
      - run: |
          key_path="$(mktemp /tmp/deja-groove-authkey.XXXXXX.p8)"
          chmod 600 "$key_path"
      - run: echo "bash .github/scripts/validate-ios-project.sh"
      - run: bundle exec fastlane ios upload_internal_testflight
      - run: rm -f "${APP_STORE_CONNECT_API_KEY_PATH:-}"
EOF_WF

  if run_check "$repo"; then
    fail "expected failure when validate script is only referenced in comment/echo"
  fi
}

test_missing_required_files_fails
test_required_files_present_passes
test_fails_without_validate_script_hook

echo "ios-distribution-readiness tests passed."
