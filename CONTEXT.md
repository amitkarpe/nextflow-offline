# Current Context

## Current Truth

- Repository: offline Nextflow demonstration scripts.
- Current baseline: existing `scrnaseq` cache, image-load, and offline-run
  path; no end-to-end runtime proof was produced by this documentation change.
- Active implementation branch: `feature/issue-1-sarek-offline`.
- Draft PR: #3 targeting `main`.
- Current commit: `f1f1ebc` (Sarek bundle scaffold and offline contract).
- Static validation passes; no AWS or runtime proof has been produced.

## Next Action

Before any Sarek execution, stage the pinned `3.10.0` bundle, plugin cache,
non-production input, local references, and private-ECR image map. Then run
`offline/run_sarek_offline.sh` only from the endpoint-isolated EC2 test lane.

## Boundaries

- No public download during the offline proof.
- No production data, credentials, or cloud mutation in this repository-only
  implementation phase. AWS/runtime evidence remains `UNKNOWN_PENDING`.
