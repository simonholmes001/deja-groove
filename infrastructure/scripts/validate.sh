#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"
WHAT_IF="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="${SCRIPT_DIR}/../bicep"
PARAMS_FILE="${BICEP_DIR}/parameters/dev.bicepparam"
DEPLOY_LOCATION="swedencentral"

if [[ -z "${ENVIRONMENT}" ]]; then
  echo "Usage: $0 <dev> [--what-if]" >&2
  exit 1
fi
if [[ "${ENVIRONMENT}" != "dev" ]]; then
  echo "Error: only dev is supported in this bootstrap stage." >&2
  exit 1
fi
if [[ ! -f "${PARAMS_FILE}" ]]; then
  echo "Error: parameter file not found: ${PARAMS_FILE}" >&2
  exit 1
fi

POSTGRES_ADMIN_LOGIN="${AZURE_POSTGRES_ADMIN_LOGIN:-}"
POSTGRES_ADMIN_PASSWORD="${AZURE_POSTGRES_ADMIN_PASSWORD:-}"
if [[ -z "${POSTGRES_ADMIN_LOGIN}" || -z "${POSTGRES_ADMIN_PASSWORD}" ]]; then
  echo "Error: AZURE_POSTGRES_ADMIN_LOGIN and AZURE_POSTGRES_ADMIN_PASSWORD must be set." >&2
  exit 1
fi

echo "==> [1/4] Linting Bicep files..."
az bicep lint --file "${BICEP_DIR}/main.bicep"

echo "==> [2/4] Sanity-checking APIM policies..."
bash "${SCRIPT_DIR}/check-apim-policy.sh"

echo "==> [3/4] Subscription-scope validate..."
az deployment sub validate \
  --location "${DEPLOY_LOCATION}" \
  --template-file "${BICEP_DIR}/main.bicep" \
  --parameters "${PARAMS_FILE}" \
  --parameters postgresAdministratorLogin="${POSTGRES_ADMIN_LOGIN}" \
  --parameters postgresAdministratorLoginPassword="${POSTGRES_ADMIN_PASSWORD}" \
  --output none

if [[ "${WHAT_IF}" == "--what-if" ]]; then
  echo "==> [4/4] Subscription-scope what-if..."
  az deployment sub what-if \
    --name "deja-dev-whatif-$(date -u +%Y%m%dT%H%M%SZ)" \
    --location "${DEPLOY_LOCATION}" \
    --template-file "${BICEP_DIR}/main.bicep" \
    --parameters "${PARAMS_FILE}" \
    --parameters postgresAdministratorLogin="${POSTGRES_ADMIN_LOGIN}" \
    --parameters postgresAdministratorLoginPassword="${POSTGRES_ADMIN_PASSWORD}"
else
  echo "==> [4/4] Skipping what-if (pass --what-if to enable)."
fi

echo "Validation complete for environment: ${ENVIRONMENT}"
