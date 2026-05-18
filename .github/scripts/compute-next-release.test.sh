#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="${ROOT}/.github/scripts/compute-next-release.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_equals() {
  local expected="$1"
  local actual="$2"
  local msg="$3"
  [[ "${expected}" == "${actual}" ]] || fail "${msg} (expected='${expected}' actual='${actual}')"
}

run_script_in_repo() {
  local repo="$1"
  local out="$repo/out.txt"
  (
    cd "$repo"
    GITHUB_OUTPUT="$out" bash "$SCRIPT"
  )
  cat "$out"
}

new_repo() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.name "test"
  git -C "$dir" config user.email "test@example.com"
  mkdir -p "$dir/.changeset"
  cat > "$dir/.changeset/README.md" <<'EOF'
# readme
EOF
  echo "init" > "$dir/file.txt"
  git -C "$dir" add .
  git -C "$dir" commit -q -m "init"
  echo "$dir"
}

parse_output() {
  local content="$1" key="$2"
  echo "$content" | awk -F= -v k="$key" '$1==k {print $2}'
}

test_no_changesets_no_release() {
  local repo out
  repo="$(new_repo)"
  out="$(run_script_in_repo "$repo")"
  assert_equals "false" "$(parse_output "$out" "should_release")" "no changesets should not release"
}

test_patch_minor_major_precedence() {
  local repo out
  repo="$(new_repo)"

  cat > "$repo/.changeset/patch.md" <<'EOF'
---
"deja-groove": patch
---
patch change
EOF
  cat > "$repo/.changeset/minor.md" <<'EOF'
---
"deja-groove": minor
---
minor change
EOF
  cat > "$repo/.changeset/major.md" <<'EOF'
---
"deja-groove": major
---
major change
EOF
  git -C "$repo" add .changeset/patch.md .changeset/minor.md .changeset/major.md
  git -C "$repo" commit -q -m "add changesets"

  out="$(run_script_in_repo "$repo")"
  assert_equals "true" "$(parse_output "$out" "should_release")" "changesets should release"
  assert_equals "major" "$(parse_output "$out" "bump")" "major should win precedence"
  assert_equals "v1.0.0" "$(parse_output "$out" "next_tag")" "no prior tags + major -> v1.0.0"
}

test_readme_ignored() {
  local repo out
  repo="$(new_repo)"
  echo "docs" >> "$repo/.changeset/README.md"
  git -C "$repo" add .changeset/README.md
  git -C "$repo" commit -q -m "touch readme"
  out="$(run_script_in_repo "$repo")"
  assert_equals "false" "$(parse_output "$out" "should_release")" "README-only changeset change should not release"
}

test_frontmatter_parse_not_body_words() {
  local repo out
  repo="$(new_repo)"
  git -C "$repo" tag -a v0.2.0 -m v0.2.0

  cat > "$repo/.changeset/body-words.md" <<'EOF'
---
"deja-groove": patch
---
This mentions a major refactor and minor tweaks in prose only.
EOF
  git -C "$repo" add .changeset/body-words.md
  git -C "$repo" commit -q -m "add patch with body words"
  out="$(run_script_in_repo "$repo")"
  assert_equals "patch" "$(parse_output "$out" "bump")" "body words must not alter bump"
  assert_equals "v0.2.1" "$(parse_output "$out" "next_tag")" "patch bump should be v0.2.1"
}

test_no_changesets_no_release
test_patch_minor_major_precedence
test_readme_ignored
test_frontmatter_parse_not_body_words

echo "compute-next-release tests passed."
