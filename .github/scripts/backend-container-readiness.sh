#!/usr/bin/env bash
set -euo pipefail

required_files=(
  "backend/src/DejaGroove.Api/Dockerfile"
  ".github/workflows/backend-container-publish.yml"
  ".github/workflows/infrastructure-deploy-dev.yaml"
  "infrastructure/bicep/parameters/dev.bicepparam"
)

for path in "${required_files[@]}"; do
  if [ ! -f "$path" ]; then
    echo "Missing required file: $path" >&2
    exit 1
  fi
done

grep -q "docker/login-action@" .github/workflows/backend-container-publish.yml || {
  echo "Missing docker/login-action in backend container workflow." >&2
  exit 1
}
grep -Fq "release_channel must be one of dev|staging|prod" .github/workflows/backend-container-publish.yml || {
  echo "Missing release-channel validation in backend container workflow." >&2
  exit 1
}
grep -q "docker/build-push-action@" .github/workflows/backend-container-publish.yml || {
  echo "Missing docker/build-push-action in backend container workflow." >&2
  exit 1
}
grep -q "aquasecurity/trivy-action@" .github/workflows/backend-container-publish.yml || {
  echo "Missing Trivy vulnerability scan gate in backend container workflow." >&2
  exit 1
}
grep -q "docker buildx imagetools create" .github/workflows/backend-container-publish.yml || {
  echo "Missing channel tag promotion step in backend container workflow." >&2
  exit 1
}

grep -q "DOCKER_IMAGE_REFERENCE" .github/workflows/infrastructure-deploy-dev.yaml || {
  echo "Infrastructure deploy workflow is not wired for DOCKER_IMAGE_REFERENCE." >&2
  exit 1
}
grep -q "workflow_call:" .github/workflows/infrastructure-deploy-dev.yaml || {
  echo "Infrastructure deploy workflow is not callable as reusable workflow." >&2
  exit 1
}
grep -q "docker_image_reference:" .github/workflows/infrastructure-deploy-dev.yaml || {
  echo "Infrastructure deploy reusable input docker_image_reference is missing." >&2
  exit 1
}
grep -q "workflow_call execution requires inputs.docker_image_reference" .github/workflows/infrastructure-deploy-dev.yaml || {
  echo "Infrastructure deploy workflow is not fail-closed for workflow_call missing image reference." >&2
  exit 1
}
grep -q -- '--parameters dockerImageReference="${DOCKER_IMAGE_REFERENCE}"' .github/workflows/infrastructure-deploy-dev.yaml || {
  echo "Infrastructure deploy workflow does not pass dockerImageReference parameter." >&2
  exit 1
}
grep -q 'DOCKER_IMAGE_REFERENCE=${DOCKER_IMAGE_REFERENCE}' .github/workflows/infrastructure-deploy-dev.yaml || {
  echo "Infrastructure deploy workflow does not persist DOCKER_IMAGE_REFERENCE via GITHUB_ENV." >&2
  exit 1
}
grep -q "@sha256:" .github/workflows/infrastructure-deploy-dev.yaml || {
  echo "Infrastructure deploy workflow does not enforce digest-based image references." >&2
  exit 1
}
grep -q "auth.docker.io/token" .github/workflows/infrastructure-deploy-dev.yaml || {
  echo "Infrastructure deploy workflow missing Docker registry token-based manifest validation." >&2
  exit 1
}
grep -q "registry-1.docker.io/v2/" .github/workflows/infrastructure-deploy-dev.yaml || {
  echo "Infrastructure deploy workflow missing Docker registry manifest lookup." >&2
  exit 1
}

if grep -q "param dockerImageReference = 'nginx:latest'" infrastructure/bicep/parameters/dev.bicepparam; then
  echo "Dev dockerImageReference must not be nginx:latest." >&2
  exit 1
fi

echo "Backend container readiness checks passed."
