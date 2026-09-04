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

`generate_sarek_ecr_manifest.sh` builds that manifest from the retained
historical Sarek 3.4.4 22-image inventory. Run it before the mirror loop when
the source list changes.

`run_ecr_distribution.sh` is the generic operator entrypoint. It supports the
approved pipeline names and defaults to plan-only mode. `--execute` is required
before it invokes Skopeo; it does not create ECR repositories.

`run_all_ecr_distributions.sh` sequentially drives the retained historical
demo, bamtofastq, and rnaseq Quay inventories. It is plan-only by default.
With `--execute`, it creates only missing per-pipeline repositories through
`create_ecr.sh`, then calls the generic runner once per pipeline. It writes an
aggregate `RESULT.md`, `status.tsv`, and `.done`/`.failed` marker. Set
`CODEX_QUEUE_THREAD` only for a verified session UUID; otherwise completion is
signalled by durable evidence, desktop notification, and terminal bell.

The home-local pipeline E2E preparation uses `offline/pipeline_e2e.tsv`,
`offline/discover_pipeline_e2e.sh`, and `offline/run_all_pipeline_discovery.sh`.
It stages only private S3 workflow/data assets, installs per-bundle plugins,
and fails closed unless every inspected process container has an exact mapping
to the immutable per-pipeline ECR manifest. It does not run Podman or tasks.
`watch_pipeline_e2e_discovery.sh` is a read-only tmux progress display for
that parallel preparation evidence directory.

Provenance for future agents: retain the manifest/evidence shape from
`../offline/common/aws-validation/mirror-ecr-images-with-crane-container.sh`.
Do not reuse that script's Docker/Crane engine here because this lane requires
registry-to-registry Skopeo transfer without a local container image store.
