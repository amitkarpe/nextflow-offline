# Current Context

## Current Truth

- Repository: portable/offline Nextflow bundle demonstration.
- Phase 1 is complete: the canonical `offline/` builder can create the `nf-core/demo` 1.0.2 bundle, run a local Podman offline smoke, and publish/read back a bounded bundle from S3 when explicitly requested.
- S3 publication is opt-in and is **not** part of the normal fast validation loop.
- Current canonical implementation milestone: Issue #12 / PR #14 — same-**online server** offline emulation using a freshly built bundle relocated to a different local path.
- Separate experimental lane: Issue #7 / PR #8 — standalone colleague-facing `docs/ops/**` Magic Script validation. It is not yet merged/proven and must remain isolated from the canonical `offline/` implementation.
- Existing `scrnaseq` and Sarek files remain preserved. Sarek is later pipeline scale-up, not the immediate default task.

## Current Validation Direction

Use progressive evidence rather than repeating the most expensive proof every time:

```text
Level 0  static checks
   ->
Level 1  same-online-server offline emulation  [default]
   ->
Level 2  bounded S3 publish/readback           [occasional]
   ->
Level 3  real offline-server execution         [acceptance gate]
   ->
Level 4  pipeline scale-up: rnaseq/Sarek/etc.
```

The default engineering loop is Level 1:

1. build a fresh bundle with `PUBLISH_S3=no`;
2. relocate/copy it to a different absolute local path;
3. load only its bundled container archives into Podman;
4. use bundle-local workflow/data/refs/plugin cache;
5. set `NXF_OFFLINE=true` and `NXF_PLUGIN_AUTOINSTALL=false`;
6. run with explicit Nextflow `-offline` and the existing local/offline smoke profile;
7. keep Podman task networking disabled where defined by that profile.

This is **offline emulation**. It does not prove that the host itself has no internet route.

## Next Action

Complete Issue #12 / PR #14 and record one truthful same-server relocated-bundle proof.

Do not start Sarek or require another S3 publication merely to complete that fast validation milestone.

## Boundaries

- Public access is allowed during online preparation when the selected source mode requires it.
- The offline-emulation/runtime portion must use only staged bundle assets and must not require public test data, plugin downloads, or public image pulls.
- `nextflow -offline` alone is not sufficient evidence; preserve the full offline control set.
- S3 publication/readback is a separate transfer/release proof and must be explicit.
- A real **offline server** proof remains a later acceptance gate.
- No production/clinical data, credentials, or private environment identifiers belong in Git.
