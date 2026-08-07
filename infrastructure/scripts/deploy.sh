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

BLOB_URI="https://${STORAGE_ACCOUNT_NAME}.blob.core.windows.net/${DEPLOYMENT_CONTAINER_NAME}/${PACKAGE_BLOB_NAME}"

is_storage_auth_error() {
  grep -Eqi "required permissions|AuthorizationPermissionMismatch|AuthorizationFailure|AuthenticationFailed|Forbidden|403"
}

upload_function_package() {
  local upload_output

  for attempt in {1..30}; do
    if upload_output="$(az storage blob upload \
      --account-name "${STORAGE_ACCOUNT_NAME}" \
      --container-name "${DEPLOYMENT_CONTAINER_NAME}" \
      --name "${PACKAGE_BLOB_NAME}" \
      --file "${PACKAGE_FILE}" \
      --auth-mode login \
      --overwrite true \
      --output none 2>&1)"; then
      echo "Uploaded Function package to deployment storage."
      return 0
    fi

    if is_storage_auth_error <<< "${upload_output}"; then
      echo "Waiting for deployment principal storage RBAC propagation; attempt ${attempt}/30."
      sleep 20
      continue
    fi

    echo "${upload_output}" >&2
    return 1
  done

  echo "Error: Function package upload still lacks storage data-plane permission after waiting for RBAC propagation." >&2
  echo "Confirm the GitHub Azure client has Storage Blob Data Contributor on storage account ${STORAGE_ACCOUNT_NAME}." >&2
  return 1
}

create_package_sas_uri() {
  local starts_on
  local expires_on
  local sas_token
  local sas_error_file
  local sas_output

  if starts_on="$(date -u -d "15 minutes ago" '+%Y-%m-%dT%H:%MZ' 2>/dev/null)"; then
    expires_on="$(date -u -d "2 hours" '+%Y-%m-%dT%H:%MZ')"
  else
    starts_on="$(date -u -v-15M '+%Y-%m-%dT%H:%MZ')"
    expires_on="$(date -u -v+2H '+%Y-%m-%dT%H:%MZ')"
  fi

  sas_error_file="$(mktemp)"
  trap 'rm -f "${sas_error_file}"' RETURN

  for attempt in {1..30}; do
    if sas_output="$(az storage blob generate-sas \
      --account-name "${STORAGE_ACCOUNT_NAME}" \
      --container-name "${DEPLOYMENT_CONTAINER_NAME}" \
      --name "${PACKAGE_BLOB_NAME}" \
      --permissions r \
      --auth-mode login \
      --as-user \
      --start "${starts_on}" \
      --expiry "${expires_on}" \
      --https-only \
      --output tsv 2>"${sas_error_file}")"; then
      sas_token="${sas_output}"
      if [[ -n "${sas_token}" ]]; then
        echo "${BLOB_URI}?${sas_token}"
        return 0
      fi
    fi

    sas_output="$(cat "${sas_error_file}")"
    : > "${sas_error_file}"

    if is_storage_auth_error <<< "${sas_output}"; then
      echo "Waiting for deployment principal SAS permission propagation; attempt ${attempt}/30." >&2
      sleep 20
      continue
    fi

    if [[ -n "${sas_output}" ]]; then
      echo "${sas_output}" >&2
      return 1
    fi

    echo "Waiting for deployment principal SAS permission propagation; attempt ${attempt}/30." >&2
    sleep 20
  done

  echo "Error: failed to create user-delegation SAS for Function package after waiting for RBAC propagation." >&2
  return 1
}

echo "==> Packaging Function app..."
PACKAGE_FILE="$(DEJA_PACKAGE_VERSION="${DEPLOYMENT_NAME}" "${PACKAGE_SCRIPT}")"
if [[ ! -f "${PACKAGE_FILE}" ]]; then
  echo "Error: Function package was not created: ${PACKAGE_FILE}" >&2
  exit 1
fi

echo "==> Uploading Function package to Flex deployment storage..."
upload_function_package

echo "==> Creating short-lived read SAS for One Deploy package source..."
PACKAGE_URI="$(create_package_sas_uri)"

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
HEALTH_RESPONSE="$(curl --silent --show-error "${HEALTH_ENDPOINT}")"
DEPLOYED_PACKAGE_VERSION="$(jq -r '.deployment.packageVersion // empty' <<< "${HEALTH_RESPONSE}")"
if [[ "${DEPLOYED_PACKAGE_VERSION}" != "${DEPLOYMENT_NAME}" ]]; then
  echo "Error: deployed health marker did not match package version." >&2
  echo "Expected: ${DEPLOYMENT_NAME}" >&2
  echo "Actual: ${DEPLOYED_PACKAGE_VERSION:-<missing>}" >&2
  exit 1
fi
echo "Verified deployed package marker: ${DEPLOYED_PACKAGE_VERSION}"
retry_http_status POST "${SCAN_ENDPOINT}" '^(401|403)$' "protected scan endpoint without function key"

echo "Deployment complete: ${DEPLOYMENT_NAME}"
echo "Scan endpoint: ${SCAN_ENDPOINT}"
