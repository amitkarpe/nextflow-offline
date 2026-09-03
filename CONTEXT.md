# Current Context

## Current Truth

- Repository: offline Nextflow demonstration scripts.
- Active direction: Issue #5 Phase 1 portable bundle builder.
- Default proof target: cached `nf-core/demo` revision `1.0.2` with Podman.
- Default input: `s3://trust-team/nextflow-offline/data/rnaseq-tiny-20260624/`.
- S3 publication is opt-in and is not run by default.
- Existing `scrnaseq` and Sarek files remain preserved/deferred.

## Next Action

Run `offline/build_offline_bundle.sh` in an online-server lane with an empty
`BUNDLE_ROOT`, then inspect the generated manifests and offline smoke result.

## Boundaries

- Public access is allowed only during online preparation.
- The offline smoke must use only the bundle and `-offline`.
- No production/clinical data, credentials, or unapproved S3 publication.
