#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/.github/scripts/backend-container-readiness.sh"

make_repo() {
  local dir
  dir="$(mktemp -d)"
  mkdir -p "$dir/.github/scripts" "$dir/.github/workflows" "$dir/backend/src/DejaGroove.Api" "$dir/infrastructure/bicep/parameters"
  cp "$SCRIPT" "$dir/.github/scripts/backend-container-readiness.sh"
  chmod +x "$dir/.github/scripts/backend-container-readiness.sh"
  echo "$dir"
}

write_publish_workflow_stub() {
  local path="$1"
  cat > "$path" <<'WF'
name: Backend Container Publish
# release_channel must be one of dev|staging|prod
jobs:
  publish:
    steps:
      - uses: docker/login-action@v3
      - uses: docker/build-push-action@v6
      - uses: aquasecurity/trivy-action@79c9ab38587148a04b4bb5f683ffec8395e26b2f
      # docker buildx imagetools create
WF
}

test_passes_with_required_wiring() {
  local repo
  repo="$(make_repo)"

  cat > "$repo/backend/src/DejaGroove.Api/Dockerfile" <<'DF'
FROM mcr.microsoft.com/dotnet/aspnet:9.0
DF

  write_publish_workflow_stub "$repo/.github/workflows/backend-container-publish.yml"

  cat > "$repo/.github/workflows/infrastructure-deploy-dev.yaml" <<'WF'
name: Infrastructure Deploy (Dev)
# @sha256:
# must match <namespace>/<image>:<tag> or <namespace>/<image>:<64-hex>
# auth.docker.io/token
# registry-1.docker.io/v2/
# python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))'
workflow_call:
  inputs:
    docker_image_reference:
      required: false
      type: string
# workflow_call execution requires inputs.docker_image_reference
jobs:
  deploy-dev:
    steps:
      - name: Deploy
        run: |
          az deployment sub create \
            --parameters dockerImageReference="${DOCKER_IMAGE_REFERENCE}"
          echo "DOCKER_IMAGE_REFERENCE=${DOCKER_IMAGE_REFERENCE}" >> "$GITHUB_ENV"
WF

  cat > "$repo/infrastructure/bicep/parameters/dev.bicepparam" <<'PARAM'
using '../main.bicep'
param dockerImageReference = 'simonholmes001/deja-groove-api:dev'
PARAM

  (
    cd "$repo"
    bash .github/scripts/backend-container-readiness.sh
  )

  rm -rf "$repo"
}

test_fails_when_dockerfile_missing() {
  local repo
  repo="$(make_repo)"

  write_publish_workflow_stub "$repo/.github/workflows/backend-container-publish.yml"

  cat > "$repo/.github/workflows/infrastructure-deploy-dev.yaml" <<'WF'
name: Infrastructure Deploy (Dev)
# @sha256:
# must match <namespace>/<image>:<tag> or <namespace>/<image>:<64-hex>
# auth.docker.io/token
# registry-1.docker.io/v2/
# python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))'
workflow_call:
  inputs:
    docker_image_reference:
      required: false
      type: string
# workflow_call execution requires inputs.docker_image_reference
jobs:
  deploy-dev:
    steps:
      - name: Deploy
        run: |
          az deployment sub create \
            --parameters dockerImageReference="simonholmes001/deja-groove-api:dev"
          echo "DOCKER_IMAGE_REFERENCE=simonholmes001/deja-groove-api:dev" >> "$GITHUB_ENV"
WF

  cat > "$repo/infrastructure/bicep/parameters/dev.bicepparam" <<'PARAM'
using '../main.bicep'
param dockerImageReference = 'simonholmes001/deja-groove-api:dev'
PARAM

  set +e
  (
    cd "$repo"
    bash .github/scripts/backend-container-readiness.sh >/tmp/backend-container-readiness.out 2>&1
  )
  local rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    echo "expected non-zero exit when Dockerfile is missing" >&2
    cat /tmp/backend-container-readiness.out >&2 || true
    rm -rf "$repo"
    exit 1
  fi

  grep -q "Missing required file: backend/src/DejaGroove.Api/Dockerfile" /tmp/backend-container-readiness.out || {
    echo "expected missing Dockerfile message" >&2
    cat /tmp/backend-container-readiness.out >&2 || true
    rm -rf "$repo"
    exit 1
  }

  rm -rf "$repo"
}

test_fails_when_dev_param_still_placeholder() {
  local repo
  repo="$(make_repo)"

  cat > "$repo/backend/src/DejaGroove.Api/Dockerfile" <<'DF'
FROM mcr.microsoft.com/dotnet/aspnet:9.0
DF

  write_publish_workflow_stub "$repo/.github/workflows/backend-container-publish.yml"

  cat > "$repo/.github/workflows/infrastructure-deploy-dev.yaml" <<'WF'
name: Infrastructure Deploy (Dev)
# @sha256:
# must match <namespace>/<image>:<tag> or <namespace>/<image>:<64-hex>
# auth.docker.io/token
# registry-1.docker.io/v2/
# python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))'
workflow_call:
  inputs:
    docker_image_reference:
      required: false
      type: string
# workflow_call execution requires inputs.docker_image_reference
jobs:
  deploy-dev:
    steps:
      - name: Deploy
        run: |
          az deployment sub create \
            --parameters dockerImageReference="${DOCKER_IMAGE_REFERENCE}"
          echo "DOCKER_IMAGE_REFERENCE=${DOCKER_IMAGE_REFERENCE}" >> "$GITHUB_ENV"
WF

  cat > "$repo/infrastructure/bicep/parameters/dev.bicepparam" <<'PARAM'
using '../main.bicep'
param dockerImageReference = 'nginx:latest'
PARAM

  set +e
  (
    cd "$repo"
    bash .github/scripts/backend-container-readiness.sh >/tmp/backend-container-readiness.out 2>&1
  )
  local rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    echo "expected non-zero exit for placeholder dev docker image" >&2
    cat /tmp/backend-container-readiness.out >&2 || true
    rm -rf "$repo"
    exit 1
  fi

  grep -q "must not be nginx:latest" /tmp/backend-container-readiness.out || {
    echo "expected placeholder guard message" >&2
    cat /tmp/backend-container-readiness.out >&2 || true
    rm -rf "$repo"
    exit 1
  }

  rm -rf "$repo"
}

test_fails_when_deploy_workflow_missing_env_wiring() {
  local repo
  repo="$(make_repo)"

  cat > "$repo/backend/src/DejaGroove.Api/Dockerfile" <<'DF'
FROM mcr.microsoft.com/dotnet/aspnet:9.0
DF

  write_publish_workflow_stub "$repo/.github/workflows/backend-container-publish.yml"

  cat > "$repo/.github/workflows/infrastructure-deploy-dev.yaml" <<'WF'
name: Infrastructure Deploy (Dev)
# @sha256:
# must match <namespace>/<image>:<tag> or <namespace>/<image>:<64-hex>
# auth.docker.io/token
# registry-1.docker.io/v2/
# python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))'
workflow_call:
  inputs:
    docker_image_reference:
      required: false
      type: string
# workflow_call execution requires inputs.docker_image_reference
jobs:
  deploy-dev:
    steps:
      - name: Deploy
        run: |
          az deployment sub create \
            --parameters dockerImageReference="simonholmes001/deja-groove-api:dev"
          echo "DOCKER_IMAGE_REFERENCE=simonholmes001/deja-groove-api:dev" >> "$GITHUB_ENV"
WF

  cat > "$repo/infrastructure/bicep/parameters/dev.bicepparam" <<'PARAM'
using '../main.bicep'
param dockerImageReference = 'simonholmes001/deja-groove-api:dev'
PARAM

  set +e
  (
    cd "$repo"
    bash .github/scripts/backend-container-readiness.sh >/tmp/backend-container-readiness.out 2>&1
  )
  local rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    echo "expected non-zero exit for missing DOCKER_IMAGE_REFERENCE wiring" >&2
    cat /tmp/backend-container-readiness.out >&2 || true
    rm -rf "$repo"
    exit 1
  fi

  grep -Eq "not wired for DOCKER_IMAGE_REFERENCE|does not pass dockerImageReference parameter" /tmp/backend-container-readiness.out || {
    echo "expected DOCKER_IMAGE_REFERENCE wiring message" >&2
    cat /tmp/backend-container-readiness.out >&2 || true
    rm -rf "$repo"
    exit 1
  }

  rm -rf "$repo"
}

test_fails_when_deploy_workflow_missing_parameter_passthrough() {
  local repo
  repo="$(make_repo)"

  cat > "$repo/backend/src/DejaGroove.Api/Dockerfile" <<'DF'
FROM mcr.microsoft.com/dotnet/aspnet:9.0
DF

  write_publish_workflow_stub "$repo/.github/workflows/backend-container-publish.yml"

  cat > "$repo/.github/workflows/infrastructure-deploy-dev.yaml" <<'WF'
name: Infrastructure Deploy (Dev)
# @sha256:
# must match <namespace>/<image>:<tag> or <namespace>/<image>:<64-hex>
# auth.docker.io/token
# registry-1.docker.io/v2/
# python3 -c 'import json,sys; print(json.load(sys.stdin).get("token",""))'
workflow_call:
  inputs:
    docker_image_reference:
      required: false
      type: string
# workflow_call execution requires inputs.docker_image_reference
jobs:
  deploy-dev:
    steps:
      - name: Deploy
        env:
          DOCKER_IMAGE_REFERENCE: value
        run: |
          az deployment sub create
WF

  cat > "$repo/infrastructure/bicep/parameters/dev.bicepparam" <<'PARAM'
using '../main.bicep'
param dockerImageReference = 'simonholmes001/deja-groove-api:dev'
PARAM

  set +e
  (
    cd "$repo"
    bash .github/scripts/backend-container-readiness.sh >/tmp/backend-container-readiness.out 2>&1
  )
  local rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    echo "expected non-zero exit for missing parameter passthrough" >&2
    cat /tmp/backend-container-readiness.out >&2 || true
    rm -rf "$repo"
    exit 1
  fi

  grep -q "does not pass dockerImageReference parameter" /tmp/backend-container-readiness.out || {
    echo "expected dockerImageReference passthrough message" >&2
    cat /tmp/backend-container-readiness.out >&2 || true
    rm -rf "$repo"
    exit 1
  }

  rm -rf "$repo"
}

test_passes_with_required_wiring

test_fails_when_dockerfile_missing

test_fails_when_dev_param_still_placeholder

test_fails_when_deploy_workflow_missing_env_wiring

test_fails_when_deploy_workflow_missing_parameter_passthrough

echo "backend-container-readiness tests passed."
