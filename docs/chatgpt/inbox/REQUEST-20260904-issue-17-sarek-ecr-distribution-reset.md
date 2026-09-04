# REQUEST — Reset Issue #17 to Sarek-first ECR distribution

Repository: `amitkarpe/nextflow-offline`
Issue: #17
PR: #18

## Decision

Continue **Sarek-first** inside existing Issue #17 / PR #18.

The earlier Quay-only gate was useful discovery, but it is no longer the architecture acceptance rule. Historical Sarek work used mixed upstream/proxy sources. The offline requirement is that runtime needs no public registry, not that every upstream image originally came from `quay.io`.

## Runtime contract

Preferred default:

```text
S3
  -> workflow/config/params/plugins/data/refs/manifests

private ECR
  -> container images
  -> repositories named per pipeline:
     nextflow/demo
     nextflow/bamtofastq
     nextflow/rnaseq
     nextflow/sarek
```

Offline runtime may use only the prepared S3 bundle and private ECR. No public registry is required at runtime.

## Online preparation image sources

Allowed source/import paths, in preference order as available in the environment:

1. approved direct Quay sources, including existing `quay.io/trustsg/**` repositories;
2. private Nexus registry proxy, including the existing Quay proxy;
3. other explicitly approved upstream source required by the pinned historical Sarek compatibility set.

Use `skopeo copy docker://SOURCE docker://PRIVATE_ECR_DEST` where practical to avoid loading full images into local Podman storage.

This is an explicit exception to the earlier canonical-lane "no Skopeo" assumption. Skopeo is authorized here for registry-to-registry preparation only. Podman remains the runtime engine.

## Compatibility principle

Do not pin only the Sarek revision. Treat one working Sarek environment as a compatibility tuple:

```text
Sarek revision
Nextflow version
Java version
nf-core tools version
Nextflow plugin versions
selected params/profile
reference/test-data revision
container tags/digests
```

Prefer historical known-good evidence before trying newer combinations. Existing historical work under `mytestlab123/offline` is reference material.

## Current evidence

Sarek 3.5.1 preview discovery remains valid evidence:

```text
PREVIEW_RC=0
ACTIVE_PROCESSES=49
UNRESOLVED_PROCESSES=0
ACTIVE_IMAGE_COUNT=23
ACTIVE_IMAGE_REGISTRIES=community.wave.seqera.io,quay.io
```

Do not interpret mixed source registries as an offline-runtime failure by itself.

## Next bounded task

Keep work in PR #18. Do not create a replacement PR.

1. Record the historical known-good Sarek environment(s), especially the `mytestlab123/offline/sarek` configuration and dates.
2. Select one candidate compatibility set for the next Sarek run.
3. Define deterministic image mapping into `nextflow/sarek` in DEV ECR.
4. Implement/validate direct `skopeo copy` registry-to-ECR for one small known image first.
5. As an **optional low-priority connectivity probe**, test whether the DEV online preparation environment can read an existing `quay.io/trustsg/**` image. Use `skopeo inspect` or an equivalent non-destructive read before any bulk copy.
6. Also record whether the private Nexus Quay proxy can serve the equivalent source image.
7. Do not bulk-copy the full Sarek image set until the candidate compatibility tuple is selected.

## ECR naming

Prefer pipeline repositories:

```text
nextflow/demo
nextflow/bamtofastq
nextflow/rnaseq
nextflow/sarek
```

For Sarek, preserve source image identity in a manifest mapping:

```text
source_image\ttarget_ecr_image\tdigest
```

Do not depend on local Podman storage for registry-to-registry transfer.

## Supported distribution modes

Keep these as explicit project options, but do not implement all at once:

```text
A. S3 only
   workflow/data/plugins + portable container archives

B. S3 + ECR                  # preferred default
   workflow/data/plugins -> S3
   containers -> private ECR

C. S3 + ECR + private Nexus source
   Nexus proxy -> skopeo copy -> ECR

D. S3 + ECR + approved Quay/trustsg source
   quay.io/trustsg -> skopeo copy -> ECR
```

Nexus/Quay are online preparation sources; ECR is the preferred offline runtime registry.

## Non-goals for the next task

- no VPC endpoint/EC2 networking proof yet;
- no bulk Sarek image migration yet;
- no CodeBuild/CloudOS/IaC;
- no new demo/rnaseq implementation PR;
- no production/clinical data.

## Evidence expected

```text
PIPELINE=nf-core/sarek
COMPATIBILITY_SET=<documented>
ECR_REPOSITORY=nextflow/sarek
IMAGE_SOURCE_MODE=quay-trustsg|nexus-proxy|approved-upstream
SKOPEO_REGISTRY_TO_ECR=PASS|FAIL|NOT_RUN
DEV_QUAY_TRUSTSG_READ=PASS|FAIL|NOT_RUN
DEV_NEXUS_READ=PASS|FAIL|NOT_RUN
PUBLIC_RUNTIME_REGISTRY_REQUIRED=false
RESULT=SUCCESS|PARTIAL|BLOCKED
```
