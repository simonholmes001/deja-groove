#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/.github/scripts/changeset-check.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

new_repo_with_main() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.name "test"
  git -C "$dir" config user.email "test@example.com"
  git -C "$dir" branch -m main
  mkdir -p "$dir/.changeset" "$dir/ios"
  cat > "$dir/.changeset/README.md" <<'EOF'
# readme
EOF
  echo "init" > "$dir/ios/a.txt"
  git -C "$dir" add .
  git -C "$dir" commit -q -m "init"
  git -C "$dir" checkout -q -b feature/test
  echo "$dir"
}

run_check() {
  local repo="$1"
  (
    cd "$repo"
    GITHUB_EVENT_NAME="pull_request" \
    GITHUB_ACTOR="simon" \
    GITHUB_BASE_REF="main" \
    bash "$SCRIPT"
  )
}

test_non_releasable_change_passes() {
  local repo
  repo="$(new_repo_with_main)"
  mkdir -p "$repo/docs"
  echo "doc" > "$repo/docs/readme.md"
  git -C "$repo" add docs/readme.md
  git -C "$repo" commit -q -m "docs"
  run_check "$repo" || fail "non-releasable changes should pass"
}

test_releasable_without_changeset_fails() {
  local repo
  repo="$(new_repo_with_main)"
  echo "code" >> "$repo/ios/a.txt"
  git -C "$repo" add ios/a.txt
  git -C "$repo" commit -q -m "ios change"
  if run_check "$repo"; then
    fail "releasable changes without changeset should fail"
  fi
}

test_releasable_with_changeset_passes() {
  local repo
  repo="$(new_repo_with_main)"
  echo "code" >> "$repo/ios/a.txt"
  cat > "$repo/.changeset/test.md" <<'EOF'
---
"deja-groove": patch
---
ios fix
EOF
  git -C "$repo" add ios/a.txt .changeset/test.md
  git -C "$repo" commit -q -m "ios change with changeset"
  run_check "$repo" || fail "releasable changes with changeset should pass"
}

test_non_pr_event_skips() {
  local repo
  repo="$(new_repo_with_main)"
  (
    cd "$repo"
    GITHUB_EVENT_NAME="push" \
    GITHUB_ACTOR="simon" \
    GITHUB_BASE_REF="main" \
    bash "$SCRIPT"
  ) || fail "non-PR event should skip"
}

test_non_releasable_change_passes
test_releasable_without_changeset_fails
test_releasable_with_changeset_passes
test_non_pr_event_skips

echo "changeset-check tests passed."
