#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="${SCRIPT_DIR}/../bicep"
MINIMAL_TEMPLATE="${BICEP_DIR}/minimal-function.bicep"
ONE_DEPLOY_TEMPLATE="${BICEP_DIR}/function-onedeploy.bicep"
PARAMS_FILE="${BICEP_DIR}/parameters/${ENVIRONMENT}.bicepparam"
PACKAGE_SCRIPT="${SCRIPT_DIR}/package-function.sh"
DEPLOY_LOCATION="${AZURE_LOCATION:-swedencentral}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEPLOYMENT_NAME="deja-minimal-function-${ENVIRONMENT:-unknown}-${TIMESTAMP}"
PACKAGE_BLOB_NAME="released-package.zip"
DEPLOYMENT_PRINCIPAL_OBJECT_ID="${AZURE_CLIENT_OBJECT_ID:-}"

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

if [[ ! -f "${ONE_DEPLOY_TEMPLATE}" ]]; then
  echo "Error: One Deploy template not found: ${ONE_DEPLOY_TEMPLATE}" >&2
  exit 1
fi

if [[ -z "${OPENAI_KEY:-}" ]]; then
  echo "Error: OPENAI_KEY must be set for the Function App configuration." >&2
  exit 1
fi

echo "==> Running minimal Function validation..."
"${SCRIPT_DIR}/validate.sh" "${ENVIRONMENT}"

if [[ -z "${DEPLOYMENT_PRINCIPAL_OBJECT_ID}" && -n "${AZURE_CLIENT_ID:-}" ]]; then
  DEPLOYMENT_PRINCIPAL_OBJECT_ID="$(az ad sp show --id "${AZURE_CLIENT_ID}" --query id --output tsv 2>/dev/null || true)"
  if [[ -z "${DEPLOYMENT_PRINCIPAL_OBJECT_ID}" ]]; then
    echo "Warning: could not resolve deployment principal object ID from AZURE_CLIENT_ID; storage upload requires pre-existing blob data permission." >&2
  fi
fi

echo "==> Deploying ${DEPLOYMENT_NAME} (subscription scope)..."
DEPLOYMENT_OUTPUTS="$(az deployment sub create \
  --name "${DEPLOYMENT_NAME}" \
  --location "${DEPLOY_LOCATION}" \
  --template-file "${MINIMAL_TEMPLATE}" \
  --parameters "${PARAMS_FILE}" \
  --parameters openAiKey="${OPENAI_KEY}" \
  --parameters deploymentPrincipalObjectId="${DEPLOYMENT_PRINCIPAL_OBJECT_ID}" \
  --query properties.outputs \
  --output json)"

FUNCTION_APP_NAME="$(jq -r '.functionAppName.value' <<< "${DEPLOYMENT_OUTPUTS}")"
RESOURCE_GROUP_NAME="$(jq -r '.resourceGroupName.value' <<< "${DEPLOYMENT_OUTPUTS}")"
STORAGE_ACCOUNT_NAME="$(jq -r '.storageAccountName.value' <<< "${DEPLOYMENT_OUTPUTS}")"
DEPLOYMENT_CONTAINER_NAME="$(jq -r '.deploymentContainerName.value' <<< "${DEPLOYMENT_OUTPUTS}")"
SCAN_ENDPOINT="$(jq -r '.scanEndpoint.value' <<< "${DEPLOYMENT_OUTPUTS}")"
HEALTH_ENDPOINT="$(jq -r '.healthEndpoint.value' <<< "${DEPLOYMENT_OUTPUTS}")"

if [[ -z "${FUNCTION_APP_NAME}" || "${FUNCTION_APP_NAME}" == "null" ]]; then
  echo "Error: Bicep deployment did not return functionAppName." >&2
  exit 1
fi
if [[ -z "${RESOURCE_GROUP_NAME}" || "${RESOURCE_GROUP_NAME}" == "null" ]]; then
  echo "Error: Bicep deployment did not return resourceGroupName." >&2
  exit 1
fi
if [[ -z "${STORAGE_ACCOUNT_NAME}" || "${STORAGE_ACCOUNT_NAME}" == "null" ]]; then
  echo "Error: Bicep deployment did not return storageAccountName." >&2
  exit 1
fi
if [[ -z "${DEPLOYMENT_CONTAINER_NAME}" || "${DEPLOYMENT_CONTAINER_NAME}" == "null" ]]; then
  echo "Error: Bicep deployment did not return deploymentContainerName." >&2
  exit 1
fi

PACKAGE_URI="https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${DEPLOYMENT_CONTAINER_NAME}/${PACKAGE_BLOB_NAME}"

echo "==> Packaging Function app..."
PACKAGE_FILE="$("${PACKAGE_SCRIPT}")"
if [[ ! -f "${PACKAGE_FILE}" ]]; then
  echo "Error: Function package was not created: ${PACKAGE_FILE}" >&2
  exit 1
fi

echo "==> Uploading Function package to Flex deployment storage..."
az storage blob upload \
  --account-name "${STORAGE_ACCOUNT_NAME}" \
  --container-name "${DEPLOYMENT_CONTAINER_NAME}" \
  --name "${PACKAGE_BLOB_NAME}" \
  --file "${PACKAGE_FILE}" \
  --auth-mode login \
  --overwrite true \
  --output none

echo "==> Publishing Function package to ${FUNCTION_APP_NAME} with One Deploy..."
az deployment group create \
  --name "${DEPLOYMENT_NAME}-code" \
  --resource-group "${RESOURCE_GROUP_NAME}" \
  --template-file "${ONE_DEPLOY_TEMPLATE}" \
  --parameters functionAppName="${FUNCTION_APP_NAME}" packageUri="${PACKAGE_URI}" \
  --output none

retry_http_status() {
  local method="$1"
  local url="$2"
  local expected_regex="$3"
  local description="$4"
  local status

  for attempt in {1..12}; do
    status="$(curl --silent --show-error --output /dev/null --write-out "%{http_code}" --request "${method}" "${url}" || true)"
    if [[ "${status}" =~ ${expected_regex} ]]; then
      echo "Verified ${description}: HTTP ${status}"
      return 0
    fi
    echo "Waiting for ${description}; attempt ${attempt}/12 returned HTTP ${status}."
    sleep 5
  done

  echo "Error: ${description} did not return expected HTTP status. Last status: ${status}" >&2
  return 1
}

echo "==> Verifying deployed Function endpoints..."
retry_http_status GET "${HEALTH_ENDPOINT}" '^200$' "health endpoint"
retry_http_status POST "${SCAN_ENDPOINT}" '^(401|403)$' "protected scan endpoint without function key"

echo "Deployment complete: ${DEPLOYMENT_NAME}"
echo "Scan endpoint: ${SCAN_ENDPOINT}"
