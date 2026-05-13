#!/usr/bin/env bash
# Deploy Bicep IaC to a target environment.
# Usage: ./infrastructure/scripts/deploy.sh <env>
#
# Runs validate.sh first. Prod deployments require an explicit confirmation prompt.
# Prerequisites: az CLI 2.50+, az bicep installed, az login completed.

set -euo pipefail

ENVIRONMENT="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="${SCRIPT_DIR}/../bicep"
PARAMS_FILE="${BICEP_DIR}/parameters/${ENVIRONMENT}.bicepparam"
RESOURCE_GROUP="rg-deja-${ENVIRONMENT}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEPLOYMENT_NAME="deja-${ENVIRONMENT}-${TIMESTAMP}"

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

if [[ -z "${ENVIRONMENT}" ]]; then
  echo "Usage: $0 <dev|staging|prod>" >&2
  exit 1
fi

if [[ ! "${ENVIRONMENT}" =~ ^(dev|staging|prod)$ ]]; then
  echo "Error: environment must be dev, staging, or prod." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Secure parameters — must be supplied via environment variables.
# ---------------------------------------------------------------------------

POSTGRES_ADMIN_LOGIN="${AZURE_POSTGRES_ADMIN_LOGIN:-}"
POSTGRES_ADMIN_PASSWORD="${AZURE_POSTGRES_ADMIN_PASSWORD:-}"

if [[ -z "${POSTGRES_ADMIN_LOGIN}" ]]; then
  echo "Error: AZURE_POSTGRES_ADMIN_LOGIN environment variable is not set." >&2
  echo "  Export it before running this script, e.g.:" >&2
  echo "    export AZURE_POSTGRES_ADMIN_LOGIN=<login>" >&2
  exit 1
fi

if [[ -z "${POSTGRES_ADMIN_PASSWORD}" ]]; then
  echo "Error: AZURE_POSTGRES_ADMIN_PASSWORD environment variable is not set." >&2
  echo "  Export it before running this script, e.g.:" >&2
  echo "    export AZURE_POSTGRES_ADMIN_PASSWORD=<password>" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Prod confirmation gate
# ---------------------------------------------------------------------------

if [[ "${ENVIRONMENT}" == "prod" ]]; then
  echo ""
  echo "WARNING: You are about to deploy to PRODUCTION."
  echo "Resource group: ${RESOURCE_GROUP}"
  echo ""
  read -r -p "Run what-if first, then type 'deploy-prod' to confirm: " CONFIRM
  if [[ "${CONFIRM}" != "deploy-prod" ]]; then
    echo "Aborted." >&2
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Pre-flight: validate before deploying
# ---------------------------------------------------------------------------

echo "==> Running pre-flight validation..."
"${SCRIPT_DIR}/validate.sh" "${ENVIRONMENT}"
echo ""

# ---------------------------------------------------------------------------
# Deploy — incremental mode only; complete mode is never used
# ---------------------------------------------------------------------------

echo "==> Deploying '${DEPLOYMENT_NAME}' to resource group '${RESOURCE_GROUP}'..."
az deployment group create \
  --name "${DEPLOYMENT_NAME}" \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${BICEP_DIR}/main.bicep" \
  --parameters "${PARAMS_FILE}" \
  --parameters postgresAdministratorLogin="${POSTGRES_ADMIN_LOGIN}" \
  --parameters postgresAdministratorLoginPassword="${POSTGRES_ADMIN_PASSWORD}" \
  --mode Incremental \
  --output table

echo ""
echo "Deployment complete: ${DEPLOYMENT_NAME}"
echo "Review history: az deployment group list --resource-group ${RESOURCE_GROUP} --output table"
