# Changesets

Add one changeset file for every PR that should trigger a release.

Format:

```md
---
"deja-groove": patch
---

Short release note summary for this PR.
```

Allowed bump values: `patch`, `minor`, `major`.

Notes:
- Use `patch` for fixes and internal improvements.
- Use `minor` for new features.
- Use `major` only for intentionally breaking changes.
- Docs-only and CI-only PRs do not need a changeset.
