#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

assert_contains() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! grep -Fq "${pattern}" "${REPO_ROOT}/${file}"; then
    echo "Error: expected ${description} in ${file}." >&2
    exit 1
  fi
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if grep -Fq "${pattern}" "${REPO_ROOT}/${file}"; then
    echo "Error: unexpected ${description} in ${file}." >&2
    exit 1
  fi
}

assert_contains "functions/recognition-proxy/src/index.ts" "DISCOGS_TOKEN app setting is required" "runtime fail-fast Discogs guard"
assert_not_contains "functions/recognition-proxy/src/index.ts" "NoopAlbumEnrichment" "Noop Discogs fallback runtime path"

assert_contains "infrastructure/scripts/deploy.sh" "DISCOGS_TOKEN must be set for Discogs metadata enrichment" "deploy-time Discogs guard"
assert_contains "infrastructure/scripts/deploy.sh" "readEnvironmentVariable('DISCOGS_TOKEN')" "required deployment Discogs parameter"
assert_not_contains "infrastructure/scripts/deploy.sh" "readEnvironmentVariable('DISCOGS_TOKEN', '')" "optional deployment Discogs parameter"

assert_contains "infrastructure/scripts/validate.sh" "DISCOGS_TOKEN must be set for Discogs metadata enrichment" "validation-time Discogs guard"
assert_not_contains "infrastructure/bicep/minimal-function.bicep" "param discogsToken string = ''" "optional minimal Bicep Discogs token"
assert_not_contains "infrastructure/bicep/recognition-function.bicep" "param discogsToken string = ''" "optional Function Bicep Discogs token"
assert_contains "infrastructure/bicep/recognition-function.bicep" "name: 'DISCOGS_TOKEN'" "Function App Discogs app setting"

assert_contains "functions/recognition-proxy/src/artworkFallback.ts" "withAppleMusicSearchLink" "Apple Music search-link fallback"
assert_contains "functions/recognition-proxy/test/artworkFallback.test.ts" "adds Apple Music listening link when Discogs artwork is complete" "Discogs plus Apple Music link regression test"

echo "Guard tests passed."
