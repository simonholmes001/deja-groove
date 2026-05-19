#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="${DEJA_GROOVE_XCODE_PROJECT:-}"
WORKSPACE_PATH="${DEJA_GROOVE_XCODE_WORKSPACE:-}"
SCHEME="${DEJA_GROOVE_XCODE_SCHEME:-}"
MANIFEST_PATH="ios/DejaGrooveApp/PrivacyInfo.xcprivacy"

if [ -z "$SCHEME" ]; then
  echo "DEJA_GROOVE_XCODE_SCHEME is required" >&2
  exit 1
fi

if [ -n "$PROJECT_PATH" ] && [ -n "$WORKSPACE_PATH" ]; then
  echo "Set only one of DEJA_GROOVE_XCODE_PROJECT or DEJA_GROOVE_XCODE_WORKSPACE" >&2
  exit 1
fi

if [ -z "$PROJECT_PATH" ] && [ -z "$WORKSPACE_PATH" ]; then
  echo "Either DEJA_GROOVE_XCODE_PROJECT or DEJA_GROOVE_XCODE_WORKSPACE must be set" >&2
  exit 1
fi

if [ -n "$PROJECT_PATH" ]; then
  [ -f "$PROJECT_PATH" ] || { echo "Xcode project not found: $PROJECT_PATH" >&2; exit 1; }
  LIST_JSON="$(xcodebuild -project "$PROJECT_PATH" -list -json)"
else
  [ -f "$WORKSPACE_PATH" ] || { echo "Xcode workspace not found: $WORKSPACE_PATH" >&2; exit 1; }
  LIST_JSON="$(xcodebuild -workspace "$WORKSPACE_PATH" -list -json)"
fi

echo "$LIST_JSON" | jq -e --arg scheme "$SCHEME" '.project.schemes // .workspace.schemes | index($scheme) != null' >/dev/null || {
  echo "Scheme not found: $SCHEME" >&2
  exit 1
}

[ -f "$MANIFEST_PATH" ] || { echo "Missing privacy manifest: $MANIFEST_PATH" >&2; exit 1; }

if command -v plutil >/dev/null 2>&1; then
  plutil -lint "$MANIFEST_PATH" >/dev/null

  # Enforce required top-level keys for submission readiness.
  plutil -extract NSPrivacyTracking raw "$MANIFEST_PATH" >/dev/null
  plutil -extract NSPrivacyCollectedDataTypes xml1 -o - "$MANIFEST_PATH" >/dev/null
  plutil -extract NSPrivacyAccessedAPITypes xml1 -o - "$MANIFEST_PATH" >/dev/null
else
  python3 - "$MANIFEST_PATH" <<'PY'
import plistlib
import sys

path = sys.argv[1]
with open(path, "rb") as f:
    data = plistlib.load(f)

required = [
    "NSPrivacyTracking",
    "NSPrivacyCollectedDataTypes",
    "NSPrivacyAccessedAPITypes",
]

for key in required:
    if key not in data:
        raise SystemExit(f"Missing required privacy key: {key}")
PY
fi

echo "iOS project and privacy manifest validation passed."
