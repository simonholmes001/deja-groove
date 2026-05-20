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
grep -q 'images: \${{ secrets.DOCKERHUB_USERNAME }}/deja-groove-api' "$WORKFLOW" || { echo "Wrong image naming contract" >&2; exit 1; }
grep -q 'type=raw,value=${{ env.RELEASE_CHANNEL }}-latest' "$WORKFLOW" || { echo "Missing promotion tag contract" >&2; exit 1; }
grep -q 'aquasecurity/trivy-action@79c9ab38587148a04b4bb5f683ffec8395e26b2f' "$WORKFLOW" || { echo "Missing pinned trivy scan gate" >&2; exit 1; }
grep -q 'severity: HIGH,CRITICAL' "$WORKFLOW" || { echo "Missing vulnerability severity gate" >&2; exit 1; }
grep -Eq 'uses: actions/checkout@[0-9a-f]{40}' "$WORKFLOW" || { echo "actions/checkout must be SHA pinned" >&2; exit 1; }
grep -Eq 'uses: docker/setup-buildx-action@[0-9a-f]{40}' "$WORKFLOW" || { echo "setup-buildx-action must be SHA pinned" >&2; exit 1; }
grep -Eq 'uses: docker/login-action@[0-9a-f]{40}' "$WORKFLOW" || { echo "login-action must be SHA pinned" >&2; exit 1; }
grep -Eq 'uses: docker/metadata-action@[0-9a-f]{40}' "$WORKFLOW" || { echo "metadata-action must be SHA pinned" >&2; exit 1; }
grep -Eq 'uses: docker/build-push-action@[0-9a-f]{40}' "$WORKFLOW" || { echo "build-push-action must be SHA pinned" >&2; exit 1; }

echo "backend-container-publish workflow tests passed."
