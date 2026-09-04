# ECR operator helpers

Create or return one pipeline ECR repository:

```text
AWS_PROFILE=dev AWS_REGION=ap-southeast-1 ECR_TTL=31-12-27 \
  ./scripts/ops/create_ecr.sh sarek
```

Pipeline keys use lowercase letters, digits, and hyphens. Existing repositories
are only described. New repositories use immutable tags,
scan on push, and the required project tags. Keep `ENV` local; use
`ENV.example` as its template.

`mirror_ecr_images.sh` reuses the four-column image-manifest contract and
copies with `COPY_ENGINE=skopeo`. It is the reusable preparation loop; run
`--dry-run` before copying a new manifest.

`generate_ecr_manifest.sh` builds that manifest from an exact discovered image
list. Historical pipeline lists are known-good reference/cache only: discovery
or Sarek preview remains the source of truth.

`run_ecr_distribution.sh` is the generic operator entrypoint. It supports the
approved pipeline names and defaults to plan-only mode. `--execute` is required
before it invokes Skopeo; it does not create ECR repositories.

The online-server offline-emulation pipeline preparation uses `offline/pipeline_e2e.tsv`,
and `offline/discover_pipeline_e2e.sh`.
It resolves private S3 from local `scripts/ops/ENV` `S3_ROOT`, stages
workflow/data assets, installs per-bundle plugins, and generates its manifest
from inspected containers. It does not run Podman or tasks.
`offline/run_pipeline_e2e.sh` is the generic strict runtime half. It consumes
one successful discovery bundle, relocates it, preloads only mapped ECR images
into an isolated Podman store, then enforces bundle-local Nextflow state,
explicit `-offline`, and Podman task network isolation. It rejects insufficient
disk and any Podman pull after the strict Nextflow start.

Provenance for future agents: retain the manifest/evidence shape from
`../offline/common/aws-validation/mirror-ecr-images-with-crane-container.sh`.
Do not reuse that script's Docker/Crane engine here because this lane requires
registry-to-registry Skopeo transfer without a local container image store.
