# Pipeline Inventory

Repository: `simonholmes001/deja-groove`

## Active Workflows

### `CI`
- File: `.github/workflows/ci.yaml`
- Purpose: baseline quality gates for PRs and pushes.
- Triggers: push to `main` and `feature/**`, pull requests to `main`.
- Jobs:
  - `Codex Review Script Tests`: runs tests for `.github/scripts/*.test.mjs`.
  - `Node Tests`: detects Node projects in `.`, `cli`, `frontend` and runs tests when present.
  - `.NET Tests`: detects .NET projects in `backend` and `.` and runs tests when present.
- Required secrets: none beyond default GitHub token.

### `Codex PR Review`
- File: `.github/workflows/codex-pr-review.yaml`
- Purpose: automated PR review comment using GPT model.
- Triggers: `pull_request_target` on open/sync/reopen/ready-for-review.
- Notes:
  - Skips draft PRs.
  - Uses `.github/scripts/codex-pr-review.mjs` and `.github/scripts/codex-pr-review-core.mjs`.
  - Configured model: `gpt-5.4`.
- Required secrets:
  - `OPENAI_KEY`

### `Ensure Codex Review Ruleset`
- File: `.github/workflows/ensure-codex-ruleset.yaml`
- Purpose: ensures repository ruleset requires Codex review check on `main`.
- Triggers: push to `main`, manual dispatch.
- Script: `.github/scripts/ensure-codex-ruleset.mjs`.
- Required secrets:
  - `REPO_ADMIN_TOKEN`

### `Auto Sort GitHub Project`
- File: `.github/workflows/auto-sort-project.yml`
- Purpose: keep project items ordered by status + priority swimlane + issue number.
- Triggers: schedule, workflow dispatch, issue events, project item events.
- Required secrets/variables:
  - Secret: `PROJECT_AUTOMATION_TOKEN`
  - Variables: `PROJECT_OWNER`, `PROJECT_NUMBER`

## Local Hook

### `pre-commit`
- File: `.githooks/pre-commit`
- Purpose: local commit guardrails.
- Behavior:
  - Runs Node tests for staged changes in `cli`/`frontend` if projects exist.
  - Runs .NET tests for staged changes in `backend`/root if projects exist.
  - Auto-detects `*.sln` instead of hardcoded solution name.
- Setup helper: `scripts/setup-hooks.sh`

## Consolidation Decisions

- Kept one CI workflow: `ci.yaml`.
- Removed duplicate/overlapping CI file (`ci.yml`).
- Excluded Agon-specific deploy/release/infrastructure workflows because this repository currently does not contain their required project structure and environment contract.
- Preserved reusable, repo-agnostic automation: PR review, ruleset enforcement, project auto-sort, and local pre-commit guardrails.
