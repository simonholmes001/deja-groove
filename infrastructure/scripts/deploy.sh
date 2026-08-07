#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="${SCRIPT_DIR}/../bicep"
MINIMAL_TEMPLATE="${BICEP_DIR}/minimal-function.bicep"
PARAMS_FILE="${BICEP_DIR}/parameters/${ENVIRONMENT}.bicepparam"
PACKAGE_SCRIPT="${SCRIPT_DIR}/package-function.sh"
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
  echo "Create it before running Azure deployment." >&2
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
DEPLOYMENT_OUTPUTS="$(az deployment sub create \
  --name "${DEPLOYMENT_NAME}" \
  --location "${DEPLOY_LOCATION}" \
  --template-file "${MINIMAL_TEMPLATE}" \
  --parameters "${PARAMS_FILE}" \
  --parameters openAiKey="${OPENAI_KEY}" \
  --query properties.outputs \
  --output json)"

FUNCTION_APP_NAME="$(jq -r '.functionAppName.value' <<< "${DEPLOYMENT_OUTPUTS}")"
RESOURCE_GROUP_NAME="$(jq -r '.resourceGroupName.value' <<< "${DEPLOYMENT_OUTPUTS}")"
SCAN_ENDPOINT="$(jq -r '.scanEndpoint.value' <<< "${DEPLOYMENT_OUTPUTS}")"

if [[ -z "${FUNCTION_APP_NAME}" || "${FUNCTION_APP_NAME}" == "null" ]]; then
  echo "Error: Bicep deployment did not return functionAppName." >&2
  exit 1
fi
if [[ -z "${RESOURCE_GROUP_NAME}" || "${RESOURCE_GROUP_NAME}" == "null" ]]; then
  echo "Error: Bicep deployment did not return resourceGroupName." >&2
  exit 1
fi

echo "==> Packaging Function app..."
PACKAGE_FILE="$("${PACKAGE_SCRIPT}")"
if [[ ! -f "${PACKAGE_FILE}" ]]; then
  echo "Error: Function package was not created: ${PACKAGE_FILE}" >&2
  exit 1
fi

echo "==> Publishing Function package to ${FUNCTION_APP_NAME}..."
az functionapp deployment source config-zip \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --name "${FUNCTION_APP_NAME}" \
  --src "${PACKAGE_FILE}" \
  --build-remote false \
  --output table

echo "Deployment complete: ${DEPLOYMENT_NAME}"
echo "Scan endpoint: ${SCAN_ENDPOINT}"
