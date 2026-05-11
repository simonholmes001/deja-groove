#!/bin/sh
# apply-branch-protection.sh
#
# Applies branch protection rules to `main` via the GitHub API.
# Requires: gh CLI authenticated with repo admin scope.
#
# Usage:
#   ./scripts/apply-branch-protection.sh
#   ./scripts/apply-branch-protection.sh --dry-run
#
set -eu

OWNER="simonholmes001"
REPO="deja-groove"
BRANCH="main"

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

echo "🔒 Applying branch protection to ${OWNER}/${REPO}:${BRANCH}"

if ! gh auth status >/dev/null 2>&1; then
  echo "❌ gh CLI is not authenticated. Run: gh auth login"
  exit 1
fi

PROTECTION_JSON=$(cat <<'EOF'
{
  "required_status_checks": {
    "strict": true,
    "checks": [
      { "context": "CI Pass" },
      { "context": "Branch Name" },
      { "context": "PR Title (Conventional Commits)" }
    ]
  },
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "require_code_owner_reviews": true,
    "required_approving_review_count": 1,
    "require_last_push_approval": false
  },
  "restrictions": null,
  "required_linear_history": true,
  "allow_force_pushes": false,
  "allow_deletions": false,
  "block_creations": false,
  "required_conversation_resolution": true,
  "lock_branch": false,
  "allow_fork_syncing": false
}
EOF
)

if [ "$DRY_RUN" = "true" ]; then
  echo ""
  echo "--- DRY RUN: would apply the following protection rules ---"
  echo "$PROTECTION_JSON"
  echo "---"
  echo "Run without --dry-run to apply."
  exit 0
fi

echo "$PROTECTION_JSON" | gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "/repos/${OWNER}/${REPO}/branches/${BRANCH}/protection" \
  --input -

echo ""
echo "✅ Branch protection applied to ${OWNER}/${REPO}:${BRANCH}"
echo ""
echo "Enforced rules:"
echo "  • PR required before merging (1 approval, CODEOWNERS review)"
echo "  • Stale reviews dismissed on new commits"
echo "  • Required status checks (strict — branch must be up to date):"
echo "      - CI Pass"
echo "      - Branch Name"
echo "      - PR Title (Conventional Commits)"
echo "  • Conversation resolution required"
echo "  • Linear history required"
echo "  • Force pushes blocked"
echo "  • Branch deletion blocked"
echo "  • Rules enforced for admins"
