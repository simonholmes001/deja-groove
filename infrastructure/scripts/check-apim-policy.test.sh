#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/infrastructure/scripts/check-apim-policy.sh"

make_repo() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/infrastructure/scripts" "$dir/infrastructure/bicep/modules/apim"
  cp "$SCRIPT" "$dir/infrastructure/scripts/check-apim-policy.sh"
  chmod +x "$dir/infrastructure/scripts/check-apim-policy.sh"
  echo "$dir"
}

write_apim_file() {
  local path="$1"
  cat > "$path" <<'BICEP'
var mainApiPassthroughPolicyXml = '<policies><inbound><base /><set-backend-service base-url="{{backend-url}}/v1" /><rate-limit-by-key calls="30" renewal-period="60" counter-key="@(context.Request.IpAddress)" remaining-calls-header-name="X-RateLimit-Remaining" retry-after-header-name="Retry-After" /></inbound><backend><base /></backend><outbound><base /><set-header name="X-RateLimit-Limit" exists-action="override"><value>30</value></set-header></outbound><on-error><base /><set-header name="X-RateLimit-Limit" exists-action="override"><value>30</value></set-header></on-error></policies>'
var mainApiJwtPolicyXml = '<policies><inbound><base /><set-backend-service base-url="{{backend-url}}/v1" /><validate-jwt header-name="Authorization"><openid-config url="https://example/.well-known/openid-configuration" /><required-claims><claim name="aud" match="any"><value>x</value></claim></required-claims></validate-jwt><rate-limit-by-key calls="30" renewal-period="60" counter-key="@(context.Request.Claims.GetValueOrDefault(&quot;sub&quot;, context.Request.IpAddress))" remaining-calls-header-name="X-RateLimit-Remaining" retry-after-header-name="Retry-After" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>'
BICEP
}

run_expect_pass() {
  local repo="$1"
  local out_file
  out_file="$(mktemp)"
  (
    cd "$repo"
    bash infrastructure/scripts/check-apim-policy.sh >"$out_file" 2>&1
  )
  rm -f "$out_file"
}

run_expect_fail_contains() {
  local repo="$1"
  local expected="$2"
  local out_file
  out_file="$(mktemp)"

  set +e
  (
    cd "$repo"
    bash infrastructure/scripts/check-apim-policy.sh >"$out_file" 2>&1
  )
  local rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    echo "expected check-apim-policy.sh to fail" >&2
    cat "$out_file" >&2 || true
    rm -f "$out_file"
    exit 1
  fi

  grep -q "$expected" "$out_file" || {
    echo "expected error output to contain: $expected" >&2
    cat "$out_file" >&2 || true
    rm -f "$out_file"
    exit 1
  }
  rm -f "$out_file"
}

test_passes_for_valid_policy() {
  local repo
  repo="$(make_repo)"
  write_apim_file "$repo/infrastructure/bicep/modules/apim/apim.bicep"
  run_expect_pass "$repo"
  rm -rf "$repo"
}

test_fails_for_connection_ip_expression() {
  local repo
  repo="$(make_repo)"
  write_apim_file "$repo/infrastructure/bicep/modules/apim/apim.bicep"
  printf "\nvar bad = 'context.Connection.IpAddress'\n" >> "$repo/infrastructure/bicep/modules/apim/apim.bicep"
  run_expect_fail_contains "$repo" "Unsupported APIM policy expression found"
  rm -rf "$repo"
}

test_fails_when_passthrough_rewrite_missing() {
  local repo
  repo="$(make_repo)"
  write_apim_file "$repo/infrastructure/bicep/modules/apim/apim.bicep"
  sed -i.bak 's|<set-backend-service base-url="{{backend-url}}/v1" />||' "$repo/infrastructure/bicep/modules/apim/apim.bicep"
  rm -f "$repo/infrastructure/bicep/modules/apim/apim.bicep.bak"
  run_expect_fail_contains "$repo" "Missing APIM passthrough policy backend rewrite to /v1"
  rm -rf "$repo"
}

test_fails_when_jwt_rewrite_missing() {
  local repo
  repo="$(make_repo)"
  write_apim_file "$repo/infrastructure/bicep/modules/apim/apim.bicep"
  sed -i.bak 's|<set-backend-service base-url="{{backend-url}}/v1" />||g' "$repo/infrastructure/bicep/modules/apim/apim.bicep"
  sed -i.bak2 's|var mainApiPassthroughPolicyXml = '\''<policies><inbound><base />|var mainApiPassthroughPolicyXml = '\''<policies><inbound><base /><set-backend-service base-url="{{backend-url}}/v1" />|' "$repo/infrastructure/bicep/modules/apim/apim.bicep"
  rm -f "$repo/infrastructure/bicep/modules/apim/apim.bicep.bak"
  rm -f "$repo/infrastructure/bicep/modules/apim/apim.bicep.bak2"
  run_expect_fail_contains "$repo" "Missing APIM JWT policy backend rewrite to /v1"
  rm -rf "$repo"
}

test_fails_when_jwt_ip_fallback_missing() {
  local repo
  repo="$(make_repo)"
  write_apim_file "$repo/infrastructure/bicep/modules/apim/apim.bicep"
  perl -pi.bak -e 's|context\.Request\.Claims\.GetValueOrDefault\(&quot;sub&quot;, context\.Request\.IpAddress\)|context.Request.Claims.GetValueOrDefault(&quot;sub&quot;, &quot;&quot;)|g' "$repo/infrastructure/bicep/modules/apim/apim.bicep"
  rm -f "$repo/infrastructure/bicep/modules/apim/apim.bicep.bak"
  run_expect_fail_contains "$repo" "Missing request IP fallback key in the JWT-on APIM policy branch"
  rm -rf "$repo"
}

test_fails_for_return_response() {
  local repo
  repo="$(make_repo)"
  write_apim_file "$repo/infrastructure/bicep/modules/apim/apim.bicep"
  printf "\nvar bad2 = '<return-response />'\n" >> "$repo/infrastructure/bicep/modules/apim/apim.bicep"
  run_expect_fail_contains "$repo" "must forward to the backend; mock return-response policies are not allowed"
  rm -rf "$repo"
}

test_fails_when_apim_file_missing() {
  local repo
  repo="$(make_repo)"
  run_expect_fail_contains "$repo" "APIM module not found"
  rm -rf "$repo"
}

test_passes_for_valid_policy
test_fails_for_connection_ip_expression
test_fails_when_passthrough_rewrite_missing
test_fails_when_jwt_rewrite_missing
test_fails_when_jwt_ip_fallback_missing
test_fails_for_return_response
test_fails_when_apim_file_missing

echo "check-apim-policy tests passed."
