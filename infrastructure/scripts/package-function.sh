#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FUNCTION_DIR="${REPO_ROOT}/functions/recognition-proxy"
OUTPUT_DIR="${REPO_ROOT}/.artifacts"
PACKAGE_FILE="${OUTPUT_DIR}/recognition-proxy.zip"

if [[ ! -f "${FUNCTION_DIR}/package.json" ]]; then
  echo "Error: Function project not found: ${FUNCTION_DIR}" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"

pushd "${FUNCTION_DIR}" >/dev/null
if [[ -f package-lock.json ]]; then
  npm ci --workspaces=false
else
  npm install
fi
npm run build
npm prune --omit=dev
rm -f "${PACKAGE_FILE}"
zip -qr "${PACKAGE_FILE}" host.json package.json package-lock.json node_modules dist
popd >/dev/null

echo "${PACKAGE_FILE}"
