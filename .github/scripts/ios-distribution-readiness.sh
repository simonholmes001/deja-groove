#!/usr/bin/env bash
set -euo pipefail

required_files=(
  "ios/DejaGrooveApp/PrivacyInfo.xcprivacy"
  "ios/fastlane/Appfile"
  "ios/fastlane/Fastfile"
  "ios/fastlane/Matchfile"
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

grep -q 'lane :verify_distribution_env' ios/fastlane/Fastfile || { echo "Missing Fastlane lane: verify_distribution_env" >&2; exit 1; }
grep -q 'lane :prepare_signing' ios/fastlane/Fastfile || { echo "Missing Fastlane lane: prepare_signing" >&2; exit 1; }
grep -q 'lane :upload_internal_testflight' ios/fastlane/Fastfile || { echo "Missing Fastlane lane: upload_internal_testflight" >&2; exit 1; }
grep -q 'sync_code_signing(type: "appstore"' ios/fastlane/Fastfile || { echo "Missing App Store signing sync in Fastfile" >&2; exit 1; }
grep -q 'app_store_connect_api_key(' ios/fastlane/Fastfile || { echo "Missing explicit App Store Connect API key setup in Fastfile" >&2; exit 1; }
grep -q 'upload_to_testflight(' ios/fastlane/Fastfile || { echo "Missing TestFlight upload in Fastfile" >&2; exit 1; }

grep -q 'force_legacy_encryption(true)' ios/fastlane/Matchfile || { echo "Matchfile missing legacy encryption compatibility setting" >&2; exit 1; }

grep -q 'permissions:' .github/workflows/ios-testflight.yml || { echo "Workflow missing explicit permissions" >&2; exit 1; }
grep -q 'contents: read' .github/workflows/ios-testflight.yml || { echo "Workflow missing least-privilege contents: read" >&2; exit 1; }
grep -q 'actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd' .github/workflows/ios-testflight.yml || { echo "Workflow missing immutable checkout pin" >&2; exit 1; }
grep -q 'ruby/setup-ruby@97ecb7b512899eb71ab1bf2310a624c6f1589ac6' .github/workflows/ios-testflight.yml || { echo "Workflow missing immutable ruby/setup-ruby pin" >&2; exit 1; }
grep -Fq 'mktemp /tmp/deja-groove-authkey' .github/workflows/ios-testflight.yml || { echo "Workflow missing unique API key temp path" >&2; exit 1; }
grep -Fq 'chmod 600 "$key_path"' .github/workflows/ios-testflight.yml || { echo "Workflow missing API key permission hardening" >&2; exit 1; }
grep -Fq 'rm -f "${APP_STORE_CONNECT_API_KEY_PATH:-}"' .github/workflows/ios-testflight.yml || { echo "Workflow missing API key cleanup" >&2; exit 1; }
grep -q 'MATCH_GIT_BASIC_AUTHORIZATION' .github/workflows/ios-testflight.yml || { echo "Workflow missing Match git authentication secret" >&2; exit 1; }

grep -q 'run: bash .github/scripts/validate-ios-project.sh' .github/workflows/ios-testflight.yml || { echo "Workflow missing executable iOS project validation step" >&2; exit 1; }

grep -q 'DEJA_GROOVE_XCODE_PROJECT' ios/fastlane/Fastfile || { echo "Fastfile missing project forwarding" >&2; exit 1; }
grep -q 'DEJA_GROOVE_XCODE_WORKSPACE' ios/fastlane/Fastfile || { echo "Fastfile missing workspace forwarding" >&2; exit 1; }

echo "iOS distribution readiness checks passed."
