#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/.github/scripts/validate-ios-project.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

new_repo() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/ios/DejaGrooveApp" "$dir/ios/DejaGroove" "$dir/ios/DejaGroove.xcodeproj" "$dir/ios/DejaGroove.xcworkspace" "$dir/bin"
  cat > "$dir/ios/DejaGroove/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSCameraUsageDescription</key>
  <string>Camera access is required for cover scanning.</string>
  <key>NSPhotoLibraryUsageDescription</key>
  <string>Photo access is required for library-based scanning.</string>
</dict>
</plist>
PLIST
  cat > "$dir/ios/DejaGrooveApp/PrivacyInfo.xcprivacy" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPrivacyTracking</key>
  <false/>
  <key>NSPrivacyCollectedDataTypes</key>
  <array/>
  <key>NSPrivacyAccessedAPITypes</key>
  <array/>
</dict>
</plist>
PLIST
  cat > "$dir/bin/xcodebuild" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
cat <<'JSON'
{"project":{"schemes":["DejaGroove"]}}
JSON
MOCK
  chmod +x "$dir/bin/xcodebuild"
  echo "$dir"
}

run_check() {
  local repo="$1"
  (
    cd "$repo"
    PATH="$repo/bin:$PATH" \
    DEJA_GROOVE_XCODE_PROJECT="ios/DejaGroove.xcodeproj" \
    DEJA_GROOVE_XCODE_SCHEME="DejaGroove" \
    bash "$SCRIPT"
  )
}

test_passes_for_valid_project_scheme_and_manifest() {
  local repo
  repo="$(new_repo)"
  run_check "$repo" || fail "expected validation to pass"
}

test_fails_when_scheme_missing() {
  local repo
  repo="$(new_repo)"
  if (
    cd "$repo" &&
    PATH="$repo/bin:$PATH" \
    DEJA_GROOVE_XCODE_PROJECT="ios/DejaGroove.xcodeproj" \
    DEJA_GROOVE_XCODE_SCHEME="WrongScheme" \
    bash "$SCRIPT"
  ); then
    fail "expected failure when scheme is missing"
  fi
}

test_fails_when_manifest_missing() {
  local repo
  repo="$(new_repo)"
  rm "$repo/ios/DejaGrooveApp/PrivacyInfo.xcprivacy"
  if run_check "$repo"; then
    fail "expected failure when privacy manifest is missing"
  fi
}

test_fails_when_project_and_workspace_set() {
  local repo
  repo="$(new_repo)"
  if (
    cd "$repo" &&
    PATH="$repo/bin:$PATH" \
    DEJA_GROOVE_XCODE_PROJECT="ios/DejaGroove.xcodeproj" \
    DEJA_GROOVE_XCODE_WORKSPACE="ios/DejaGroove.xcworkspace" \
    DEJA_GROOVE_XCODE_SCHEME="DejaGroove" \
    bash "$SCRIPT"
  ); then
    fail "expected failure when both project and workspace are set"
  fi
}

test_passes_for_workspace_mode() {
  local repo
  repo="$(new_repo)"
  if ! (
    cd "$repo" &&
    PATH="$repo/bin:$PATH" \
    DEJA_GROOVE_XCODE_WORKSPACE="ios/DejaGroove.xcworkspace" \
    DEJA_GROOVE_XCODE_SCHEME="DejaGroove" \
    bash "$SCRIPT"
  ); then
    fail "expected validation to pass for workspace mode"
  fi
}

test_fails_when_neither_project_nor_workspace_set() {
  local repo
  repo="$(new_repo)"
  if (
    cd "$repo" &&
    PATH="$repo/bin:$PATH" \
    DEJA_GROOVE_XCODE_SCHEME="DejaGroove" \
    bash "$SCRIPT"
  ); then
    fail "expected failure when neither project nor workspace is set"
  fi
}

test_fails_on_malformed_xcodebuild_json() {
  local repo
  repo="$(new_repo)"
  cat > "$repo/bin/xcodebuild" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "not-json"
MOCK
  chmod +x "$repo/bin/xcodebuild"
  if run_check "$repo"; then
    fail "expected failure for malformed xcodebuild JSON"
  fi
}

test_fails_when_camera_usage_description_missing() {
  local repo
  repo="$(new_repo)"
  cat > "$repo/ios/DejaGroove/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>NSPhotoLibraryUsageDescription</key>
  <string>Photo access is required for library-based scanning.</string>
</dict>
</plist>
PLIST
  if run_check "$repo"; then
    fail "expected failure when camera usage description is missing"
  fi
}

test_passes_for_valid_project_scheme_and_manifest
test_fails_when_scheme_missing
test_fails_when_manifest_missing
test_fails_when_project_and_workspace_set
test_passes_for_workspace_mode
test_fails_when_neither_project_nor_workspace_set
test_fails_on_malformed_xcodebuild_json
test_fails_when_camera_usage_description_missing

echo "validate-ios-project tests passed."
