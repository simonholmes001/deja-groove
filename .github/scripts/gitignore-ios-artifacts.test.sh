#!/usr/bin/env bash
set -euo pipefail

GITIGNORE=".gitignore"

[ -f "$GITIGNORE" ] || { echo "Missing .gitignore" >&2; exit 1; }

required_patterns=(
  ".worktrees/"
  "ios/.DS_Store"
  "ios/DejaGroove.xcodeproj/project.xcworkspace/"
  "ios/DejaGroove.xcodeproj/xcuserdata/"
  "ios/DejaGrooveApp/.swiftpm/"
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fxq "$pattern" "$GITIGNORE"; then
    echo "Missing ignore pattern: $pattern" >&2
    exit 1
  fi
done

echo "gitignore iOS artifact patterns test passed."
