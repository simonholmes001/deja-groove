#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-}"
MODE="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="${SCRIPT_DIR}/../bicep"
MINIMAL_TEMPLATE="${BICEP_DIR}/minimal-function.bicep"
ONE_DEPLOY_TEMPLATE="${BICEP_DIR}/function-onedeploy.bicep"
PARAMS_FILE="${BICEP_DIR}/parameters/${ENVIRONMENT}.bicepparam"
DEPLOY_LOCATION="${AZURE_LOCATION:-swedencentral}"
EFFECTIVE_PARAMS_FILE=""

if [[ -z "${ENVIRONMENT}" ]]; then
  echo "Usage: $0 <dev> [--lint-only|--what-if]" >&2
  exit 1
fi

if [[ "${ENVIRONMENT}" != "dev" ]]; then
  echo "Error: only dev is supported for the minimal Function bootstrap stage." >&2
  exit 1
fi

case "${MODE}" in
  ""|"--lint-only"|"--what-if") ;;
  *)
    echo "Error: unsupported mode '${MODE}'. Expected --lint-only or --what-if." >&2
    exit 1
    ;;
esac

if [[ ! -f "${MINIMAL_TEMPLATE}" ]]; then
  echo "Minimal Function template is not present yet: ${MINIMAL_TEMPLATE}"
  echo "Skipping Azure validation until the minimum-cost Function infrastructure exists."
  exit 0
fi

if [[ ! -f "${PARAMS_FILE}" ]]; then
  echo "Error: parameter file not found: ${PARAMS_FILE}" >&2
  exit 1
fi

if [[ ! -f "${ONE_DEPLOY_TEMPLATE}" ]]; then
  echo "Error: One Deploy template not found: ${ONE_DEPLOY_TEMPLATE}" >&2
  exit 1
fi

if grep -q "name: 'FUNCTIONS_WORKER_RUNTIME'" "${MINIMAL_TEMPLATE}" "${BICEP_DIR}"/*.bicep; then
  echo "Error: Flex Consumption runtime is configured through functionAppConfig.runtime; do not set FUNCTIONS_WORKER_RUNTIME as an app setting." >&2
  exit 1
fi

if grep -q "functionapp deployment source config-zip" "${SCRIPT_DIR}/deploy.sh"; then
  echo "Error: Flex Consumption deployments must use One Deploy, not classic config-zip." >&2
  exit 1
fi

if [[ "${MODE}" != "--lint-only" && -z "${DISCOGS_TOKEN:-}" ]]; then
  echo "Error: DISCOGS_TOKEN must be set for Discogs metadata enrichment." >&2
  exit 1
fi

echo "==> Linting minimal Function Bicep..."
az bicep lint --file "${MINIMAL_TEMPLATE}"
az bicep lint --file "${ONE_DEPLOY_TEMPLATE}"

echo "==> Building minimal Function Bicep..."
az bicep build --file "${MINIMAL_TEMPLATE}" --outfile /dev/null
az bicep build --file "${ONE_DEPLOY_TEMPLATE}" --outfile /dev/null

create_effective_params_file() {
  EFFECTIVE_PARAMS_FILE="$(mktemp "${BICEP_DIR}/parameters/.${ENVIRONMENT}.XXXXXX.bicepparam")"
  chmod 600 "${EFFECTIVE_PARAMS_FILE}"

  cat > "${EFFECTIVE_PARAMS_FILE}" <<'PARAMS'
using '../minimal-function.bicep'

param environment = 'dev'
param location = 'swedencentral'
param resourceGroupName = 'rg-deja-groove-dev-recognition'
param appBaseName = 'deja-recognition-dev'
param openAiModel = 'gpt-5-mini'
param scanIncludeTimings = true
param enableApplicationInsights = true
param openAiKey = readEnvironmentVariable('OPENAI_KEY', 'validation-placeholder')
param discogsToken = readEnvironmentVariable('DISCOGS_TOKEN', 'validation-discogs-placeholder')
param deploymentPrincipalObjectId = readEnvironmentVariable('DEPLOYMENT_PRINCIPAL_OBJECT_ID', '')
PARAMS
}

cleanup_effective_params_file() {
  if [[ -n "${EFFECTIVE_PARAMS_FILE}" ]]; then
    rm -f "${EFFECTIVE_PARAMS_FILE}"
  fi
}
trap cleanup_effective_params_file EXIT
create_effective_params_file

if [[ "${MODE}" == "--lint-only" ]]; then
  echo "Lint/build complete for environment: ${ENVIRONMENT}"
  exit 0
fi

echo "==> Subscription-scope validate..."
az deployment sub validate \
  --location "${DEPLOY_LOCATION}" \
  --template-file "${MINIMAL_TEMPLATE}" \
  --parameters "${EFFECTIVE_PARAMS_FILE}" \
  --output none

if [[ "${MODE}" == "--what-if" ]]; then
  echo "==> Subscription-scope what-if..."
  az deployment sub what-if \
    --name "deja-minimal-function-${ENVIRONMENT}-whatif-$(date -u +%Y%m%dT%H%M%SZ)" \
    --location "${DEPLOY_LOCATION}" \
    --template-file "${MINIMAL_TEMPLATE}" \
    --parameters "${EFFECTIVE_PARAMS_FILE}" \
    --result-format ResourceIdOnly \
    --no-pretty-print \
    --output none
fi

echo "Validation complete for environment: ${ENVIRONMENT}"
