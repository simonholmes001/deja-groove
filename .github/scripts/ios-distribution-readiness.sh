#!/usr/bin/env bash
set -euo pipefail

required_files=(
  "ios/DejaGrooveApp/PrivacyInfo.xcprivacy"
  "ios/fastlane/Appfile"
  "ios/fastlane/Fastfile"
  ".github/workflows/ios-testflight.yml"
)

missing=0
for path in "${required_files[@]}"; do
  if [ ! -f "$path" ]; then
    echo "Missing required file: $path" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  exit 1
fi

grep -q 'lane :prepare_signing' ios/fastlane/Fastfile || { echo "Missing Fastlane lane: prepare_signing" >&2; exit 1; }
grep -q 'lane :upload_internal_testflight' ios/fastlane/Fastfile || { echo "Missing Fastlane lane: upload_internal_testflight" >&2; exit 1; }
grep -q 'sync_code_signing(type: "appstore"' ios/fastlane/Fastfile || { echo "Missing App Store signing sync in Fastfile" >&2; exit 1; }
grep -q 'upload_to_testflight' ios/fastlane/Fastfile || { echo "Missing TestFlight upload in Fastfile" >&2; exit 1; }
grep -q 'xcodebuild -list -json' .github/workflows/ios-testflight.yml || { echo "Workflow missing scheme validation step" >&2; exit 1; }
grep -q 'fastlane ios upload_internal_testflight' .github/workflows/ios-testflight.yml || { echo "Workflow missing TestFlight upload lane invocation" >&2; exit 1; }

echo "iOS distribution readiness checks passed."
