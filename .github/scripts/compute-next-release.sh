#!/usr/bin/env bash
set -euo pipefail

LATEST_TAG="$(git tag --list 'v*' --sort=-version:refname | head -n1)"
if [[ -z "${LATEST_TAG}" ]]; then
  LATEST_TAG="v0.0.0"
fi

echo "latest_tag=${LATEST_TAG}" >> "$GITHUB_OUTPUT"

CHANGED_CHANGESETS="$(
  git diff --name-only "${LATEST_TAG}"..HEAD -- '.changeset/*.md' \
    | grep -v '^\.changeset/README\.md$' \
    | sort -u || true
)"

if [[ -z "${CHANGED_CHANGESETS}" ]]; then
  echo "should_release=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "Changed changesets since ${LATEST_TAG}:"
echo "${CHANGED_CHANGESETS}"

BUMP="patch"
while IFS= read -r file; do
  [[ -z "${file}" ]] && continue
  if grep -Eqi '\bmajor\b' "${file}"; then
    BUMP="major"
    break
  fi
  if grep -Eqi '\bminor\b' "${file}"; then
    BUMP="minor"
  fi
done <<< "${CHANGED_CHANGESETS}"

VERSION="${LATEST_TAG#v}"
IFS='.' read -r MAJOR MINOR PATCH <<< "${VERSION}"
MAJOR="${MAJOR:-0}"
MINOR="${MINOR:-0}"
PATCH="${PATCH:-0}"

case "${BUMP}" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
  *)
    echo "Unsupported bump type: ${BUMP}" >&2
    exit 1
    ;;
esac

NEXT_TAG="v${MAJOR}.${MINOR}.${PATCH}"
echo "should_release=true" >> "$GITHUB_OUTPUT"
echo "bump=${BUMP}" >> "$GITHUB_OUTPUT"
echo "next_tag=${NEXT_TAG}" >> "$GITHUB_OUTPUT"
