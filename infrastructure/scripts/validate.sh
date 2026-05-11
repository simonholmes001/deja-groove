#!/usr/bin/env bash
# Lint, validate, and optionally what-if the Bicep deployment for a given environment.
# Usage:
#   ./infrastructure/scripts/validate.sh <env>              # lint + validate
#   ./infrastructure/scripts/validate.sh <env> --what-if    # lint + validate + what-if
#
# Prerequisites: az CLI 2.50+, az bicep installed, az login completed.

set -euo pipefail

ENVIRONMENT="${1:-}"
WHAT_IF="${2:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_DIR="${SCRIPT_DIR}/../bicep"
PARAMS_FILE="${BICEP_DIR}/parameters/${ENVIRONMENT}.bicepparam"
RESOURCE_GROUP="rg-deja-${ENVIRONMENT}"

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------

if [[ -z "${ENVIRONMENT}" ]]; then
  echo "Usage: $0 <dev|staging|prod> [--what-if]" >&2
  exit 1
fi

if [[ ! "${ENVIRONMENT}" =~ ^(dev|staging|prod)$ ]]; then
  echo "Error: environment must be dev, staging, or prod." >&2
  exit 1
fi

if [[ ! -f "${PARAMS_FILE}" ]]; then
  echo "Error: parameter file not found: ${PARAMS_FILE}" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Step 1 — Bicep lint
# ---------------------------------------------------------------------------

echo "==> [1/3] Linting Bicep files..."
az bicep lint --file "${BICEP_DIR}/main.bicep"
echo "    Lint passed."

# ---------------------------------------------------------------------------
# Step 2 — ARM template validation
# ---------------------------------------------------------------------------

echo "==> [2/3] Validating deployment against resource group '${RESOURCE_GROUP}'..."
az deployment group validate \
  --resource-group "${RESOURCE_GROUP}" \
  --template-file "${BICEP_DIR}/main.bicep" \
  --parameters "${PARAMS_FILE}" \
  --output none
echo "    Validation passed."

# ---------------------------------------------------------------------------
# Step 3 — What-if (optional)
# ---------------------------------------------------------------------------

if [[ "${WHAT_IF}" == "--what-if" ]]; then
  echo "==> [3/3] Running what-if for '${ENVIRONMENT}'..."
  az deployment group what-if \
    --resource-group "${RESOURCE_GROUP}" \
    --template-file "${BICEP_DIR}/main.bicep" \
    --parameters "${PARAMS_FILE}"
else
  echo "==> [3/3] Skipping what-if (pass --what-if to enable)."
fi

echo ""
echo "Validation complete for environment: ${ENVIRONMENT}"
