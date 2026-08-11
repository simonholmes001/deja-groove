#!/usr/bin/env bash
set -euo pipefail

required_files=(
  "ios/DejaGroove/Info.plist"
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
grep -q 'sync_code_signing(' ios/fastlane/Fastfile || { echo "Missing App Store signing sync in Fastfile" >&2; exit 1; }
grep -q 'type: "appstore"' ios/fastlane/Fastfile || { echo "Fastfile signing sync is not scoped to App Store" >&2; exit 1; }
grep -q 'app_store_connect_api_key(' ios/fastlane/Fastfile || { echo "Missing explicit App Store Connect API key setup in Fastfile" >&2; exit 1; }
grep -q 'upload_to_testflight(' ios/fastlane/Fastfile || { echo "Missing TestFlight upload in Fastfile" >&2; exit 1; }
grep -q 'def xcode_container_path' ios/fastlane/Fastfile || { echo "Fastfile missing xcode container path normalization" >&2; exit 1; }
grep -q 'create_keychain(' ios/fastlane/Fastfile || { echo "Fastfile missing CI keychain creation" >&2; exit 1; }
grep -q 'delete_keychain(' ios/fastlane/Fastfile || { echo "Fastfile missing CI keychain cleanup" >&2; exit 1; }
grep -q 'keychain_name' ios/fastlane/Fastfile || { echo "Fastfile missing Match keychain name forwarding" >&2; exit 1; }
grep -q 'keychain_password' ios/fastlane/Fastfile || { echo "Fastfile missing Match keychain password forwarding" >&2; exit 1; }
if awk '/lane :verify_distribution_env/,/].each/' ios/fastlane/Fastfile | grep -q 'MATCH_KEYCHAIN_PASSWORD'; then
  echo "Fastfile must not require MATCH_KEYCHAIN_PASSWORD for standalone signing lanes" >&2
  exit 1
fi

grep -q 'force_legacy_encryption(true)' ios/fastlane/Matchfile || { echo "Matchfile missing legacy encryption compatibility setting" >&2; exit 1; }

grep -q 'permissions:' .github/workflows/ios-testflight.yml || { echo "Workflow missing explicit permissions" >&2; exit 1; }
grep -q 'contents: read' .github/workflows/ios-testflight.yml || { echo "Workflow missing least-privilege contents: read" >&2; exit 1; }
grep -q 'branches: \[main\]' .github/workflows/ios-testflight.yml || { echo "Workflow missing automatic main branch TestFlight trigger" >&2; exit 1; }
grep -q "'ios/\*\*'" .github/workflows/ios-testflight.yml || { echo "Workflow missing iOS path trigger" >&2; exit 1; }
grep -q 'actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd' .github/workflows/ios-testflight.yml || { echo "Workflow missing immutable checkout pin" >&2; exit 1; }
grep -q 'ruby/setup-ruby@97ecb7b512899eb71ab1bf2310a624c6f1589ac6' .github/workflows/ios-testflight.yml || { echo "Workflow missing immutable ruby/setup-ruby pin" >&2; exit 1; }
grep -q "ruby-version: '3.1'" .github/workflows/ios-testflight.yml || { echo "Workflow missing Ruby version compatible with locked Fastlane dependencies" >&2; exit 1; }
grep -q "bundler: '2.5.23'" .github/workflows/ios-testflight.yml || { echo "Workflow missing Ruby 3-compatible Bundler pin" >&2; exit 1; }
grep -Fq 'mktemp /tmp/deja-groove-authkey' .github/workflows/ios-testflight.yml || { echo "Workflow missing unique API key temp path" >&2; exit 1; }
grep -Fq 'chmod 600 "$key_path"' .github/workflows/ios-testflight.yml || { echo "Workflow missing API key permission hardening" >&2; exit 1; }
grep -Fq 'rm -f "${APP_STORE_CONNECT_API_KEY_PATH:-}"' .github/workflows/ios-testflight.yml || { echo "Workflow missing API key cleanup" >&2; exit 1; }
grep -q 'MATCH_GIT_BASIC_AUTHORIZATION' .github/workflows/ios-testflight.yml || { echo "Workflow missing Match git authentication secret" >&2; exit 1; }
grep -q 'MATCH_KEYCHAIN_PASSWORD' .github/workflows/ios-testflight.yml || { echo "Workflow missing CI keychain password secret" >&2; exit 1; }

grep -q 'run: bash .github/scripts/validate-ios-project.sh' .github/workflows/ios-testflight.yml || { echo "Workflow missing executable iOS project validation step" >&2; exit 1; }

grep -q 'DEJA_GROOVE_XCODE_PROJECT' ios/fastlane/Fastfile || { echo "Fastfile missing project forwarding" >&2; exit 1; }
grep -q 'DEJA_GROOVE_XCODE_WORKSPACE' ios/fastlane/Fastfile || { echo "Fastfile missing workspace forwarding" >&2; exit 1; }
grep -q 'ITSAppUsesNonExemptEncryption' ios/DejaGroove/Info.plist || { echo "Info.plist missing export compliance encryption declaration" >&2; exit 1; }

echo "iOS distribution readiness checks passed."
