#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="${SCRIPT_DIR}/../bicep"
MINIMAL_TEMPLATE="${BICEP_DIR}/minimal-function.bicep"
PARAMS_FILE="${BICEP_DIR}/parameters/${ENVIRONMENT}.bicepparam"
DEPLOY_LOCATION="${AZURE_LOCATION:-swedencentral}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEPLOYMENT_NAME="deja-minimal-function-${ENVIRONMENT:-unknown}-${TIMESTAMP}"

if [[ -z "${ENVIRONMENT}" ]]; then
  echo "Usage: $0 <dev>" >&2
  exit 1
fi

if [[ "${ENVIRONMENT}" != "dev" ]]; then
  echo "Error: only dev is supported for the minimal Function bootstrap stage." >&2
  exit 1
fi

if [[ ! -f "${MINIMAL_TEMPLATE}" ]]; then
  echo "Error: minimal Function template is not present yet: ${MINIMAL_TEMPLATE}" >&2
  echo "Create it under issue #169 before running Azure deployment." >&2
  exit 1
fi

if [[ ! -f "${PARAMS_FILE}" ]]; then
  echo "Error: parameter file not found: ${PARAMS_FILE}" >&2
  exit 1
fi

if [[ -z "${OPENAI_KEY:-}" ]]; then
  echo "Error: OPENAI_KEY must be set for the Function App configuration." >&2
  exit 1
fi

echo "==> Running minimal Function validation..."
"${SCRIPT_DIR}/validate.sh" "${ENVIRONMENT}"

echo "==> Deploying ${DEPLOYMENT_NAME} (subscription scope)..."
az deployment sub create \
  --name "${DEPLOYMENT_NAME}" \
  --location "${DEPLOY_LOCATION}" \
  --template-file "${MINIMAL_TEMPLATE}" \
  --parameters "${PARAMS_FILE}" \
  --parameters openAiKey="${OPENAI_KEY}" \
  --output table

echo "Deployment complete: ${DEPLOYMENT_NAME}"
