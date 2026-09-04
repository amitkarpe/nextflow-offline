# PR #18 final-gate review request

## Objective

Review the final, bounded repair and validation state for PR #18.  Do not
recommend a registry substitution, image mirroring, Sarek runtime execution,
or a new architecture.

## Immutable review target

The immutable commit URL is recorded with this packet in the PR review comment.

PR: https://github.com/amitkarpe/nextflow-offline/pull/18

Protocol: https://gist.github.com/amitkarpe/c8d29ad89cafe3ba178fcae29de3c238

## Repair scope

- Restore executable mode for relocated `workflow/bin` helper scripts before
  the offline runtime. Object-store staging retains bytes but not POSIX modes.
- Require source-bundle hashes before relocation and validate them after copy.
- Use Podman `--network none --pull=never` in generated runtime configuration.
- Remove generated account-specific Sarek ECR manifest output from Git.
- Bound Sarek preview cleanup and record its DAG source when Nextflow writes a
  valid pipeline-info DAG but hangs during launcher shutdown.

## Verified evidence

```text
demo       RESULT=SUCCESS
bamtofastq RESULT=SUCCESS
rnaseq     RESULT=SUCCESS

Each runtime proof:
RELOCATED_BUNDLE=PASS
SOURCE_CHECKSUMS=PASS
CHECKSUMS=PASS
ECR_PRELOAD=PASS
NXF_OFFLINE=true
NXF_PLUGIN_AUTOINSTALL=false
NEXTFLOW_OFFLINE_FLAG=true
PODMAN_NETWORK=none
POST_START_PODMAN_PULLS=NONE
PIPELINE_RC=0
EXPECTED_MULTIQC=PASS
```

```text
Sarek 3.5.1 preview:
PREVIEW_RC=0
PREVIEW_DAG_SOURCE=pipeline-info-fallback
PODMAN_ACTIONS=NONE_OBSERVED
TASK_EXECUTION=NONE_OBSERVED
ACTIVE_IMAGE_COUNT=23
ACTIVE_IMAGE_REGISTRIES=community.wave.seqera.io,quay.io
QUAY_ONLY=FAIL
OFFLINE_SAFE=false
RESULT=BLOCKED
```

The Sarek outcome is deliberate fail-closed behavior: its active preview path
is not Quay-only. No source image was copied, no container was pulled or run,
and no cloud publication occurred in that gate.

## Requested response

State whether the small runtime portability repair and truthful Sarek preview
fallback are acceptable.  If a change is required, give only the smallest
same-PR correction.  Do not approve Sarek image distribution while
`OFFLINE_SAFE=false`.

## Public-safety statement

This packet contains no credentials, account identifiers, private endpoints,
customer data, or raw cloud payloads.
