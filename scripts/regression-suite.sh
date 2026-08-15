#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Running Swift package regression tests"
(
  cd "${ROOT_DIR}/ios/DejaGrooveApp"
  swift test
)

echo "==> Running recognition proxy contract/regression tests"
(
  cd "${ROOT_DIR}/functions/recognition-proxy"
  npm test
)

echo "==> Running iOS app assembly smoke checks"
"${ROOT_DIR}/scripts/smoke-ios-app-assembly.sh"

echo "Regression suite passed."
