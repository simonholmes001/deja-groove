# Branch Protection — Déjà Groove

Repository: `simonholmes001/deja-groove`  
Target branch: `main`

## Applying Protection (Automated)

Branch protection is applied via script — do not configure it manually through the UI.

```sh
# Preview what will be applied
./scripts/apply-branch-protection.sh --dry-run

# Apply to the repository
./scripts/apply-branch-protection.sh
```

Requires the `gh` CLI authenticated with `repo` admin scope.

## Enforced Rules

| Rule | Setting |
|------|---------|
| PR required before merging | ✅ Enabled |
| Required approvals | 1 |
| Require CODEOWNERS review | ✅ Enabled (`.github/CODEOWNERS`) |
| Dismiss stale reviews on new commits | ✅ Enabled |
| Required status checks (strict) | See below |
| Conversation resolution required | ✅ Enabled |
| Linear history required | ✅ Enabled |
| Force pushes blocked | ✅ Enabled |
| Branch deletion blocked | ✅ Enabled |
| Enforce for admins | ✅ Enabled |

## Required Status Checks

Branch protection requires **all three** checks to pass before merge:

| Check | Workflow | What it validates |
|-------|----------|-------------------|
| `CI Pass` | `.github/workflows/ci.yaml` | Gate job — passes only when backend + iOS jobs pass or are skipped |
| `Branch Name` | `.github/workflows/pr-checks.yaml` | Branch matches `<type>/<description>` pattern |
| `PR Title (Conventional Commits)` | `.github/workflows/pr-checks.yaml` | PR title follows Conventional Commits format |

`CI Pass` is the single gate for build and test results. Adding new CI jobs only requires wiring them into `ci-pass`, not updating branch protection rules.

## Workflows Overview

```
.github/
  workflows/
    ci.yaml          — Build + test (backend .NET 9, iOS Xcode detect)
    pr-checks.yaml   — PR hygiene (branch name, PR title format)
  CODEOWNERS         — Review routing
scripts/
  apply-branch-protection.sh  — Idempotent protection setup via gh API
  setup-hooks.sh              — Install local pre-commit hooks
.githooks/
  pre-commit         — Local guardrail: runs .NET tests on staged backend changes
```

## Local Development Setup

Install pre-commit hooks (run once after cloning):

```sh
./scripts/setup-hooks.sh
```

## Verifying Protection is Active

1. Create a PR with a failing test — confirm merge is blocked.
2. Fix the test — confirm merge becomes available only after all checks pass.
3. Attempt a direct push to `main` — confirm it is rejected.

