# Current Context

## Current Truth

- Repository: offline Nextflow demonstration scripts.
- Current baseline: existing `scrnaseq` cache, image-load, and offline-run
  path; no end-to-end runtime proof was produced by this documentation change.
- Active documentation branch: `chore/repo-foundation`.
- Next target: define and prove one Sarek offline happy path.

## Next Action

Before any Sarek execution, record the exact Sarek revision, input class,
pipeline asset cache, container-image cache, command, and proof output in
`SPEC.md` or a task-specific update.

## Boundaries

- No public download during the offline proof.
- No production data, credentials, or cloud mutation in this repository
  foundation task.
