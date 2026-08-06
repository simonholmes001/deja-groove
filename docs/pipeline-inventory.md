# Pipeline Inventory

Repository: `simonholmes001/deja-groove`

## Active Workflows

### `CI`
- File: `.github/workflows/ci.yaml`
- Purpose: baseline quality gates for PRs and pushes.
- Triggers: push to `main` and `feature/**`, pull requests to `main`.
- Jobs:
  - `Changeset Check`: requires a changeset for releasable PR changes.
  - `Codex Review Script Tests`: runs tests for `.github/scripts/*.test.mjs`.
  - `Repository Script Tests`: runs shell-script tests for release, changeset,
    iOS, and repository hygiene scripts.
  - `Node Tests`: detects Node projects in `.`, `cli`, `frontend` and runs tests when present.
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

### `Infrastructure Validate (PR)`
- File: `.github/workflows/infrastructure-validate.yaml`
- Purpose: validates infra changes before merge.
- Triggers: pull requests to `main` with changes under `infrastructure/**`,
  `functions/**`, or minimal infra workflow files.
- Jobs:
  - `Validate Dev Function Proxy`
- Required secrets:
  - `AZURE_CLIENT_ID`
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`
  - `OPENAI_KEY` when full validation/deploy is enabled

### `Minimal Azure Function Deploy (Dev)`
- File: `.github/workflows/infrastructure-deploy-dev.yaml`
- Purpose: deploys the minimal Azure Function recognition proxy to dev.
- Triggers: push to `main` for minimal infra/function changes and manual dispatch.
- Key checks:
  - Validate `OPENAI_KEY`
  - Run `infrastructure/scripts/deploy.sh dev`
- Required secrets:
  - `AZURE_CLIENT_ID`
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`
  - `OPENAI_KEY`

## Local Hook

### `pre-commit`
- File: `.githooks/pre-commit`
- Purpose: local commit guardrails.
- Behavior:
  - Runs Node tests for staged changes in `cli`/`frontend` if projects exist.
  - Runs Swift tests for `ios/DejaGrooveAuth` and `ios/DejaGrooveApp`.
- Setup helper: `scripts/setup-hooks.sh`

## Consolidation Decisions

- Kept one CI workflow: `ci.yaml`.
- Removed duplicate/overlapping CI file (`ci.yml`).
- Removed the retired .NET backend source, tests, Docker, APIM/App Service, and PostgreSQL guardrails.
- Preserved reusable, repo-agnostic automation: PR review, ruleset enforcement, project auto-sort, and local pre-commit guardrails.
