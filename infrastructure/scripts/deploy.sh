#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="${SCRIPT_DIR}/../bicep"
PARAMS_FILE="${BICEP_DIR}/parameters/dev.bicepparam"
DEPLOY_LOCATION="swedencentral"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEPLOYMENT_NAME="deja-dev-${TIMESTAMP}"

if [[ -z "${ENVIRONMENT}" ]]; then
  echo "Usage: $0 <dev>" >&2
  exit 1
fi
if [[ "${ENVIRONMENT}" != "dev" ]]; then
  echo "Error: only dev is supported in this bootstrap stage." >&2
  exit 1
fi

POSTGRES_ADMIN_LOGIN="${AZURE_POSTGRES_ADMIN_LOGIN:-}"
POSTGRES_ADMIN_PASSWORD="${AZURE_POSTGRES_ADMIN_PASSWORD:-}"
if [[ -z "${POSTGRES_ADMIN_LOGIN}" || -z "${POSTGRES_ADMIN_PASSWORD}" ]]; then
  echo "Error: AZURE_POSTGRES_ADMIN_LOGIN and AZURE_POSTGRES_ADMIN_PASSWORD must be set." >&2
  exit 1
fi

echo "==> Running pre-flight validation..."
"${SCRIPT_DIR}/validate.sh" "dev"

echo "==> Deploying ${DEPLOYMENT_NAME} (subscription scope)..."
az deployment sub create \
  --name "${DEPLOYMENT_NAME}" \
  --location "${DEPLOY_LOCATION}" \
  --template-file "${BICEP_DIR}/main.bicep" \
  --parameters "${PARAMS_FILE}" \
  --parameters postgresAdministratorLogin="${POSTGRES_ADMIN_LOGIN}" \
  --parameters postgresAdministratorLoginPassword="${POSTGRES_ADMIN_PASSWORD}" \
  --output table

echo "Deployment complete: ${DEPLOYMENT_NAME}"
