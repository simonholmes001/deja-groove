#!/usr/bin/env bash
set -euo pipefail

WORKFLOW=".github/workflows/backend-container-publish.yml"

[ -f "$WORKFLOW" ] || { echo "Missing workflow: $WORKFLOW" >&2; exit 1; }

grep -q '^name: Backend Container Publish' "$WORKFLOW" || { echo "Wrong workflow name" >&2; exit 1; }
grep -q 'push:' "$WORKFLOW" || { echo "Missing push trigger" >&2; exit 1; }
grep -q 'branches: \[main\]' "$WORKFLOW" || { echo "Missing main branch trigger" >&2; exit 1; }
grep -q 'release_channel:' "$WORKFLOW" || { echo "Missing release channel input" >&2; exit 1; }
grep -q '"backend/\*\*"' "$WORKFLOW" || { echo "Missing backend path trigger" >&2; exit 1; }
grep -q 'push: true' "$WORKFLOW" || { echo "Build is not configured to push" >&2; exit 1; }
grep -q 'file: backend/src/DejaGroove.Api/Dockerfile' "$WORKFLOW" || { echo "Wrong Dockerfile path" >&2; exit 1; }
grep -q 'release_channel must be one of dev|staging|prod' "$WORKFLOW" || { echo "Missing release channel validation contract" >&2; exit 1; }
grep -q 'IMAGE_REPO: \${{ secrets.DOCKERHUB_USERNAME }}/deja-groove-api' "$WORKFLOW" || { echo "Wrong image naming contract" >&2; exit 1; }
grep -q 'tags: \${{ env.IMAGE_REPO }}:sha-\${{ github.sha }}' "$WORKFLOW" || { echo "Missing immutable sha publish tag contract" >&2; exit 1; }
grep -q 'outputs:' "$WORKFLOW" || { echo "Missing publish job outputs block" >&2; exit 1; }
grep -q 'image_ref: \${{ steps.image_ref.outputs.value }}' "$WORKFLOW" || { echo "Missing image_ref output contract" >&2; exit 1; }
grep -q 'id: build' "$WORKFLOW" || { echo "Missing build step id for digest capture" >&2; exit 1; }
grep -q 'id: image_ref' "$WORKFLOW" || { echo "Missing image_ref capture step" >&2; exit 1; }
grep -q 'value=\${IMAGE_REPO}@\${{ steps.build.outputs.digest }}' "$WORKFLOW" || { echo "Missing digest-based image_ref capture contract" >&2; exit 1; }
grep -q 'image-ref: \${{ steps.image_ref.outputs.value }}' "$WORKFLOW" || { echo "Missing scan-on-digest-reference contract" >&2; exit 1; }
grep -q 'docker buildx imagetools create' "$WORKFLOW" || { echo "Missing post-scan promotion step" >&2; exit 1; }
grep -q '\${IMAGE_REPO}:\${RELEASE_CHANNEL}-latest' "$WORKFLOW" || { echo "Missing channel-latest promotion contract" >&2; exit 1; }
grep -q 'aquasecurity/trivy-action@915b19bbe73b92a6cf82a1bc12b087c9a19a5fe2' "$WORKFLOW" || { echo "Missing pinned trivy scan gate" >&2; exit 1; }
grep -q 'deploy-dev:' "$WORKFLOW" || { echo "Missing deploy-dev chaining job" >&2; exit 1; }
grep -q 'uses: ./.github/workflows/infrastructure-deploy-dev.yaml' "$WORKFLOW" || { echo "Missing reusable deploy workflow call" >&2; exit 1; }
grep -q 'docker_image_reference: \${{ needs.publish.outputs.image_ref }}' "$WORKFLOW" || { echo "Missing deploy image_ref handoff contract" >&2; exit 1; }
grep -Fq "if: \${{ github.event_name == 'workflow_dispatch' && inputs.release_channel == 'dev' }}" "$WORKFLOW" || { echo "Missing deploy gating condition contract" >&2; exit 1; }
grep -q 'secrets:' "$WORKFLOW" || { echo "Missing reusable workflow secret mapping" >&2; exit 1; }
grep -q 'AZURE_CLIENT_ID: \${{ secrets.AZURE_CLIENT_ID }}' "$WORKFLOW" || { echo "Missing explicit AZURE_CLIENT_ID secret mapping" >&2; exit 1; }
grep -q 'severity: HIGH,CRITICAL' "$WORKFLOW" || { echo "Missing vulnerability severity gate" >&2; exit 1; }
grep -Eq 'uses: actions/checkout@[0-9a-f]{40}' "$WORKFLOW" || { echo "actions/checkout must be SHA pinned" >&2; exit 1; }
grep -Eq 'uses: docker/setup-buildx-action@[0-9a-f]{40}' "$WORKFLOW" || { echo "setup-buildx-action must be SHA pinned" >&2; exit 1; }
grep -Eq 'uses: docker/login-action@[0-9a-f]{40}' "$WORKFLOW" || { echo "login-action must be SHA pinned" >&2; exit 1; }
grep -Eq 'uses: docker/build-push-action@[0-9a-f]{40}' "$WORKFLOW" || { echo "build-push-action must be SHA pinned" >&2; exit 1; }

echo "backend-container-publish workflow tests passed."
