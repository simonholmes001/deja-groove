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
  lane :prepare_signing do
    sync_code_signing(type: "appstore", readonly: true)
  end

  lane :upload_internal_testflight do
    build_app(scheme: "DejaGroove")
    upload_to_testflight(skip_waiting_for_build_processing: true)
  end
end
EOF_FAST

  cat > "$repo/.github/workflows/ios-testflight.yml" <<'EOF_WF'
name: iOS TestFlight
on:
  workflow_dispatch:
jobs:
  upload:
    runs-on: macos-latest
    steps:
      - run: xcodebuild -list -json
      - run: bundle exec fastlane ios upload_internal_testflight
EOF_WF

  run_check "$repo" || fail "expected pass when required files are present"
}

test_missing_required_files_fails
test_required_files_present_passes

echo "ios-distribution-readiness tests passed."
