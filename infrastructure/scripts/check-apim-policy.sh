#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APIM_BICEP_FILE="${SCRIPT_DIR}/../bicep/modules/apim/apim.bicep"

if [[ ! -f "${APIM_BICEP_FILE}" ]]; then
  echo "Error: APIM module not found: ${APIM_BICEP_FILE}" >&2
  exit 1
fi

if grep -Fq 'context.Connection.IpAddress' "${APIM_BICEP_FILE}"; then
  echo "Error: Unsupported APIM policy expression found: context.Connection.IpAddress" >&2
  echo "Use context.Request.IpAddress in APIM policy expressions." >&2
  exit 1
fi

if ! grep -Eq '^var mainApiPassthroughPolicyXml = .+context\.Request\.IpAddress' "${APIM_BICEP_FILE}"; then
  echo "Error: Missing request IP rate-limit key in the JWT-off APIM policy branch." >&2
  exit 1
fi

if ! grep -Eq '^var mainApiJwtPolicyXml = .+GetValueOrDefault\(&quot;sub&quot;, context\.Request\.IpAddress\)' "${APIM_BICEP_FILE}"; then
  echo "Error: Missing request IP fallback key in the JWT-on APIM policy branch." >&2
  exit 1
fi

if grep -Fq 'return-response' "${APIM_BICEP_FILE}"; then
  echo "Error: APIM health endpoint must forward to the backend; mock return-response policies are not allowed." >&2
  exit 1
fi

echo "APIM policy sanity check passed."
