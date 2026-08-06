# Branch Protection Baseline (GitHub)

Repository: `simonholmes001/deja-groove`  
Target branch: `main`

This baseline aligns with local hook and CI guardrails.

## 1. Open Branch Protection Settings

1. Go to `Settings` -> `Branches`
2. Under **Branch protection rules**, click **Add rule**
3. Branch name pattern: `main`

## 2. Required Rule Settings

Enable the following:

- `Require a pull request before merging`
- `Require approvals` (minimum: 1)
- `Dismiss stale pull request approvals when new commits are pushed`
- `Require status checks to pass before merging`
- `Require branches to be up to date before merging`
- `Require conversation resolution before merging`
- `Do not allow bypassing the above settings` (for admins too, if desired)
- `Restrict force pushes`
- `Restrict deletions`

## 3. Required Status Checks

After CI has run at least once, select these checks:

- `Node Tests (., cli, frontend)` or the matrix-generated equivalents under `Node Tests`
- `Swift Tests`
- `Changeset Check`
- `Codex Review`
- `Codex Review Script Tests`
- `PR Title (Conventional Commits)`
- `Branch Name`
- `Validate Dev Function Proxy`
- `Minimal Function Bicep Lint`

Note: the retired .NET backend is no longer part of the active repository. Do not require legacy `.NET Tests` checks.

## 4. Optional Hardening

Recommended additional controls:

- Enable `Require signed commits`
- Enable `Require linear history`
- Add CODEOWNERS and `Require review from Code Owners`
- Add environment protection rules for deployment workflows

## 5. Verify

1. Create a test PR with a failing test and confirm merge is blocked.
2. Fix tests and confirm merge is unblocked only after checks pass.
3. Confirm direct push to `main` is blocked for non-admin users (or all users if strict mode).
