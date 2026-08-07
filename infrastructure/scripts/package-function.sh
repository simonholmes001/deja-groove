#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FUNCTION_DIR="${REPO_ROOT}/functions/recognition-proxy"
OUTPUT_DIR="${REPO_ROOT}/.artifacts"
PACKAGE_FILE="${OUTPUT_DIR}/recognition-proxy.zip"
PACKAGE_VERSION="${DEJA_PACKAGE_VERSION:-local}"

if [[ ! -f "${FUNCTION_DIR}/package.json" ]]; then
  echo "Error: Function project not found: ${FUNCTION_DIR}" >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIR}"

pushd "${FUNCTION_DIR}" >/dev/null
if [[ -f package-lock.json ]]; then
  npm ci --workspaces=false >&2
else
  npm install >&2
fi
npm run build >&2
printf '{"packageVersion":"%s"}\n' "${PACKAGE_VERSION}" > dist/deployment-marker.json
npm prune --omit=dev >&2
rm -f "${PACKAGE_FILE}"
zip -qr "${PACKAGE_FILE}" host.json package.json package-lock.json node_modules dist >&2
popd >/dev/null

echo "${PACKAGE_FILE}"
