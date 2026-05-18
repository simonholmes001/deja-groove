#!/usr/bin/env bash
set -euo pipefail

parse_bump_from_frontmatter() {
  local file="$1"
  local frontmatter
  frontmatter="$(sed -n '/^---[[:space:]]*$/,/^---[[:space:]]*$/p' "${file}" | sed '1d;$d' || true)"
  echo "${frontmatter}" \
    | grep -E ':[[:space:]]*(major|minor|patch)[[:space:]]*$' \
    | head -n1 \
    | sed -E 's/.*:[[:space:]]*(major|minor|patch)[[:space:]]*$/\1/' || true
}

LATEST_TAG="$(git tag --list 'v*' --sort=-version:refname | head -n1 || true)"
DIFF_BASE=""
if [[ -z "${LATEST_TAG}" ]]; then
  DIFF_BASE="$(git rev-list --max-parents=0 HEAD | tail -n1)"
  LATEST_TAG="none"
else
  DIFF_BASE="${LATEST_TAG}"
fi

echo "latest_tag=${LATEST_TAG}" >> "$GITHUB_OUTPUT"

CHANGED_CHANGESETS="$(
  git diff --name-only "${DIFF_BASE}"..HEAD -- '.changeset/*.md' \
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
  bump="$(parse_bump_from_frontmatter "${file}")"
  if [[ "${bump}" == "major" ]]; then
    BUMP="major"
    break
  fi
  if [[ "${bump}" == "minor" ]]; then
    BUMP="minor"
  fi
done <<< "${CHANGED_CHANGESETS}"

if [[ "${LATEST_TAG}" == "none" ]]; then
  VERSION="0.0.0"
else
  VERSION="${LATEST_TAG#v}"
fi
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
