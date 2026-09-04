# nextflow-offline

Small, repeatable offline-emulation proof for pinned nf-core pipelines.

```text
pipeline descriptor
  -> online workflow/data/plugin discovery
  -> exact image manifest
  -> Skopeo copy to private ECR
  -> generated Nextflow ECR overrides
  -> relocated Podman offline-emulation runtime
```

The repository currently registers `demo`, `bamtofastq`, and `rnaseq` in
`offline/pipeline_e2e.tsv`. Add a row first; do not copy a pipeline-specific
shell script.

## Fast no-network descriptor check

```bash
/usr/bin/bash offline/discover_pipeline_e2e.sh --pipeline demo --plan
```

This validates the registry row only. It does not contact AWS, run Nextflow,
use Podman, or copy images.

## Online discovery

With local `scripts/ops/ENV` containing the approved `AWS_PROFILE`,
`AWS_REGION`, and `S3_ROOT`:

```bash
/usr/bin/bash offline/discover_pipeline_e2e.sh \
  --pipeline demo \
  --bundle-root /path/to/empty/demo-bundle
```

Discovery stages the pinned workflow/data, creates bundle-local plugin state,
uses `nextflow inspect`, and writes the exact image manifest plus generated ECR
override. It does not run Podman tasks.

## Explicit image distribution

Create/describe the destination repository only when approved, then plan or
execute the Skopeo copy from discovery output:

```bash
/usr/bin/bash scripts/ops/run_ecr_distribution.sh \
  --pipeline demo \
  --source-list /path/to/demo-bundle/manifests/discovered-source-images.txt
```

Add `--execute` only for an approved mirror operation. The copy is
registry-to-registry; it does not use Docker or a local Podman image cache.

## Relocated runtime proof

After discovery and ECR preload are complete:

```bash
/usr/bin/bash offline/run_pipeline_e2e.sh \
  --pipeline demo \
  --prepared-bundle /path/to/demo-bundle \
  --test-root /different/empty/demo-offline-test
```

It copies to the different path, verifies source checksums, preloads only the
mapped private ECR images into a fresh Podman store, then runs with bundle-local
`NXF_HOME`, `NXF_OFFLINE=true`, disabled plugin autoinstall, explicit
`nextflow -offline`, and task `--network none --pull=never`.

This proves **offline emulation** on an online server. It does not claim the
host is physically air-gapped.

## Separate Magic Script

`docs/ops/**` is a standalone colleague-facing demo handoff. It remains
separate from the canonical descriptor/ECR/runtime implementation.

See `AGENTS.md`, `CONTEXT.md`, `SPEC.md`, and `docs/validation-strategy.md`
before changing the contract.
