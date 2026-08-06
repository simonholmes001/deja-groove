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

Releases are automated from `main` by `.github/workflows/release.yml`.

- Every releasable PR must include a changeset file under `.changeset/`.
- The release workflow computes the next semantic version from pending
  changeset files and publishes a GitHub Release with generated notes.
- If no pending changeset files exist since the last tag, no release is made.

## Prerequisites for readable notes

Release notes are only as good as PR hygiene. Every PR must:

- Have a clear, user-meaningful title (it becomes a changelog line).
- Carry exactly one primary `type:*` label so it lands in the right
  category. Categories are defined in [`.github/release.yml`](../../.github/release.yml).
- Include a changeset file (`.changeset/*.md`) for releasable changes.

## Triggering a release

1. Merge PRs with valid changeset files into `main`.
2. GitHub Actions `Release` workflow runs automatically on push to `main`.
3. Manual dispatch is intentionally disabled to prevent duplicate releases from
   already-processed changesets.

## Baseline release (`v0.0.0`)

The first release is `v0.0.0`, tagged at the current tip of `main`, marking
the ground-zero point from which all subsequent release notes are diffed.
Its notes describe the state of the iOS app, local-first runtime direction,
minimal Azure Function proxy path, and release automation baseline rather than
a delta.

## Out of scope

iOS signed/notarized build distribution and App Store / TestFlight release
flow are tracked separately, not by this process.
