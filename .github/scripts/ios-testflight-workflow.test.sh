#!/usr/bin/env bash
set -euo pipefail

WORKFLOW=".github/workflows/ios-testflight.yml"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[ -f "$WORKFLOW" ] || fail "workflow not found"

grep -q 'name: Validate required secrets' "$WORKFLOW" || fail "missing secret validation step"
grep -q 'Set only one of DEJA_GROOVE_XCODE_PROJECT or DEJA_GROOVE_XCODE_WORKSPACE' "$WORKFLOW" || fail "missing both-set guard"
grep -q 'Either DEJA_GROOVE_XCODE_PROJECT or DEJA_GROOVE_XCODE_WORKSPACE is required' "$WORKFLOW" || fail "missing neither-set guard"
grep -q 'Missing required secret: APP_STORE_CONNECT_API_KEY_BASE64' "$WORKFLOW" || fail "missing base64 secret guard"
grep -q 'key_path="$(mktemp /tmp/deja-groove-authkey.XXXXXX.p8)"' "$WORKFLOW" || fail "missing mktemp key path"
grep -q 'chmod 600 "\$key_path"' "$WORKFLOW" || fail "missing API key permission hardening"
grep -q 'run: rm -f "${APP_STORE_CONNECT_API_KEY_PATH:-}"' "$WORKFLOW" || fail "missing API key cleanup"
grep -q 'uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd' "$WORKFLOW" || fail "missing immutable checkout pin"
grep -q 'uses: ruby/setup-ruby@97ecb7b512899eb71ab1bf2310a624c6f1589ac6' "$WORKFLOW" || fail "missing immutable ruby setup pin"

echo "ios-testflight workflow tests passed."
