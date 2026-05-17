# Release Process

Repository: `simonholmes001/deja-groove`
Target branch: `main`

Déjà Groove uses **GitHub Releases** as the single source of truth for what
shipped and when. Each release is an annotated git tag plus a published
GitHub Release whose notes are generated from merged pull requests.

There is intentionally **no hand-maintained `CHANGELOG.md`**: the GitHub
Releases page is the changelog. Revisit this only if a changelog needs to be
consumed outside GitHub (e.g. bundled in the iOS app or an SDK).

## Versioning

Semantic Versioning with a `v` prefix on the tag: `vMAJOR.MINOR.PATCH`.

While the product is pre-production we stay on `0.x`, which signals that
public contracts (API, schema) are not yet stable:

- `0.0.0` — baseline. Ground zero; nothing formally released yet.
- `0.MINOR.0` — a coherent set of new features has landed on `main`.
- `0.0.PATCH` — fixes only, no new features.

Promotion to `1.0.0` is a deliberate decision (stable public API + GA), not
an automatic consequence of feature count.

## Cadence

Release **when a meaningful, coherent set of changes has merged to `main`** —
not on a fixed date and not per-PR. Because multiple streams (backend, iOS,
infra, API) merge to `main`, batching keeps release notes readable.

## Prerequisites for readable notes

Release notes are only as good as PR hygiene. Every PR must:

- Have a clear, user-meaningful title (it becomes a changelog line).
- Carry exactly one primary `type:*` label so it lands in the right
  category. Categories are defined in [`.github/release.yml`](../../.github/release.yml).

## Cutting a release

> Tagging and publishing a release are release-impacting actions. Confirm the
> intended scope before running these steps.

1. Ensure `main` is green and at the commit you intend to release:
   ```
   git fetch origin --prune
   git switch main && git merge --ff-only origin/main
   ```
2. Choose the next version per the rules above (e.g. `v0.1.0`).
3. Create an annotated tag and push it:
   ```
   git tag -a v0.1.0 -m "v0.1.0"
   git push origin v0.1.0
   ```
4. Draft the release from the tag, letting GitHub generate the notes:
   ```
   gh release create v0.1.0 --target main --title "v0.1.0" --generate-notes --draft
   ```
5. Review the draft in the GitHub UI (**Releases** → the draft). Reword
   noisy lines, add a short human "Highlights" section at the top if useful,
   recategorize PRs by fixing their labels and regenerating if needed.
6. Publish the release.

## Baseline release (`v0.0.0`)

The first release is `v0.0.0`, tagged at the current tip of `main`, marking
the ground-zero point from which all subsequent release notes are diffed.
Its notes describe the state of the platform at that point (collection
schema, APIM baseline, auth/identity validation, scan workflow, IaC
bootstrap) rather than a delta.

## Out of scope

iOS signed/notarized build distribution and App Store / TestFlight release
flow are tracked separately, not by this process.
