#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="${ROOT_DIR}/ios/DejaGroove.xcodeproj"
SCHEME="${SCHEME:-DejaGroove}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DESTINATION="${DESTINATION:-generic/platform=iOS Simulator}"

echo "==> Resolving ${SCHEME} ${CONFIGURATION} build settings"
BUILD_SETTINGS="$(xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -showBuildSettings 2>/dev/null)"

runtime_mode="$(awk -F '= ' '/DEJA_GROOVE_RUNTIME_MODE =/ {print $2; exit}' <<< "${BUILD_SETTINGS}")"
proxy_url="$(awk -F '= ' '/DEJA_GROOVE_RECOGNITION_PROXY_BASE_URL =/ {print $2; exit}' <<< "${BUILD_SETTINGS}")"
proxy_key="$(awk -F '= ' '/DEJA_GROOVE_RECOGNITION_PROXY_KEY =/ {print $2; exit}' <<< "${BUILD_SETTINGS}")"

if [[ "${runtime_mode}" != "local_proxy" ]]; then
  echo "Error: expected DEJA_GROOVE_RUNTIME_MODE=local_proxy, got '${runtime_mode}'." >&2
  exit 1
fi

if [[ -z "${proxy_url}" || "${proxy_url}" != https://* || "${proxy_url}" == *".example"* ]]; then
  echo "Error: recognition proxy URL is missing, non-HTTPS, or still points to an example host." >&2
  exit 1
fi

if [[ -z "${proxy_key}" || "${proxy_key}" == REPLACE_* ]]; then
  echo "Error: recognition proxy key is missing or still a placeholder." >&2
  exit 1
fi

echo "==> Building ${SCHEME} for ${DESTINATION}"
xcodebuild -project "${PROJECT}" -scheme "${SCHEME}" -configuration "${CONFIGURATION}" -destination "${DESTINATION}" build >/tmp/dejagroove-ios-smoke-build.log

if [[ "${CHECK_FUNCTION_HEALTH:-1}" == "1" ]]; then
  health_url="${proxy_url%/}/health"
  echo "==> Checking recognition proxy health at ${health_url}"
  status="$(curl --silent --show-error --max-time 20 --output /tmp/dejagroove-ios-smoke-health.json --write-out '%{http_code}' "${health_url}")"
  if [[ "${status}" != "200" ]]; then
    echo "Error: recognition proxy health returned HTTP ${status}." >&2
    exit 1
  fi
fi

echo "iOS app assembly smoke checks passed."
