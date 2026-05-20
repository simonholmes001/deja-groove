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
  if [ "$(grep -Fxc "$pattern" "$GITIGNORE")" -ne 1 ]; then
    echo "Ignore pattern must appear exactly once: $pattern" >&2
    exit 1
  fi
done

must_be_ignored=(
  ".worktrees/scratch/file.txt"
  "ios/.DS_Store"
  "ios/DejaGroove.xcodeproj/project.xcworkspace/contents.xcworkspacedata"
  "ios/DejaGroove.xcodeproj/xcuserdata/user.xcuserdatad/UserInterfaceState.xcuserstate"
  "ios/DejaGrooveApp/.swiftpm/xcode/package.xcworkspace/contents.xcworkspacedata"
)

for path in "${must_be_ignored[@]}"; do
  if ! git check-ignore -q "$path"; then
    echo "Expected path to be ignored: $path" >&2
    exit 1
  fi
done

must_not_be_ignored=(
  "README.md"
  "ios/DejaGroove/Info.plist"
  "ios/DejaGrooveApp/Sources/DejaGrooveApp/App/DejaGrooveRootView.swift"
)

for path in "${must_not_be_ignored[@]}"; do
  if git check-ignore -q "$path"; then
    echo "Expected path to remain tracked (not ignored): $path" >&2
    exit 1
  fi
done

if grep -Eq '^ios/\*\*$' "$GITIGNORE"; then
  echo "Detected over-broad ignore pattern: ios/**" >&2
  exit 1
fi

echo "gitignore iOS artifact behavior test passed."
