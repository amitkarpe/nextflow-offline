# ECR operator helpers

Create or return one pipeline ECR repository:

```text
AWS_PROFILE=dev AWS_REGION=ap-southeast-1 ECR_TTL=31-12-27 \
  ./scripts/ops/create_ecr.sh sarek
```

Approved pipeline names are `demo`, `bamtofastq`, `rnaseq`, and `sarek`.
Existing repositories are only described. New repositories use immutable tags,
scan on push, and the required project tags. Keep `ENV` local; use
`ENV.example` as its template.

`mirror_sarek_ecr_images.sh` reuses the historical four-column image-manifest
contract and copies with `COPY_ENGINE=skopeo`. It is the reusable preparation
loop for `nextflow/sarek`; run `--dry-run` before copying a new manifest.

Provenance for future agents: retain the manifest/evidence shape from
`../offline/common/aws-validation/mirror-ecr-images-with-crane-container.sh`.
Do not reuse that script's Docker/Crane engine here because this lane requires
registry-to-registry Skopeo transfer without a local container image store.
