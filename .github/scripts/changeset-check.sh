#!/usr/bin/env bash
set -euo pipefail

if [[ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]]; then
  echo "Changeset check runs only for pull_request events."
  exit 0
fi

if [[ "${GITHUB_ACTOR:-}" == "dependabot[bot]" ]]; then
  echo "Skipping changeset check for dependabot."
  exit 0
fi

BASE_REF="${GITHUB_BASE_REF:-main}"
git fetch origin "${BASE_REF}" --depth=1

CHANGED_FILES="$(git diff --name-only "origin/${BASE_REF}"...HEAD)"
echo "Changed files:"
echo "${CHANGED_FILES}"

RELEASABLE_CHANGED="$(
  echo "${CHANGED_FILES}" | grep -E '^(backend/|ios/|infrastructure/|frontend/|cli/|scripts/)' || true
)"

if [[ -z "${RELEASABLE_CHANGED}" ]]; then
  echo "No releasable code paths changed."
  exit 0
fi

CHANGESET_FILES="$(
  echo "${CHANGED_FILES}" | grep -E '^\.changeset/[^/]+\.md$' | grep -v '^\.changeset/README\.md$' || true
)"

if [[ -n "${CHANGESET_FILES}" ]]; then
  echo "Changeset file detected:"
  echo "${CHANGESET_FILES}"
  exit 0
fi

echo "::error::Releasable changes detected without a changeset file."
echo "::error::Add one file under .changeset/ (excluding README.md)."
echo "::error::See .changeset/README.md for the required format."
exit 1
