# Specification: generic Nextflow offline-emulation path

## Goal

Prepare a pinned workflow and tiny approved data online, mirror its exact
discovered images to one private ECR repository, then prove a relocated local
runtime uses no public runtime dependency.

```text
offline/pipeline_e2e.tsv
  -> offline/discover_pipeline_e2e.sh
  -> scripts/ops/run_ecr_distribution.sh
  -> scripts/ops/generate_pipeline_ecr_overrides.sh
  -> offline/run_pipeline_e2e.sh
```

## Descriptor Contract

Each row names a stable key, nf-core pipeline/revision, relative workflow/data
S3 keys, a reference inventory, and one supported tiny fixture. `--plan`
validates a row without AWS, Nextflow, Podman, image work, or task execution.
This is the onboarding gate for a future pipeline before an online discovery.

## Runtime Contract

The relocated proof uses only the prepared bundle and private ECR preload:

- bundle-local workflow, data, plugins, manifests, and generated ECR override;
- fresh isolated Podman storage;
- `NXF_HOME` inside the bundle;
- `NXF_OFFLINE=true` and `NXF_PLUGIN_AUTOINSTALL=false`;
- explicit Nextflow `-offline`;
- Podman `--network none --pull=never` for tasks;
- source checksums made before relocation and verified after copying.

The proof is **offline emulation** on the online server. It does not prove the
host lacks an internet route.

## Boundaries

- `PUBLISH_S3`, ECR creation, and image mirroring are explicit operator steps.
- Source discovery/preview is truth. `offline/reference/` is not runtime input.
- `docs/ops/**` stays a distinct colleague-facing handoff.
- Sarek remains preview-gated and fail-closed; no runtime or mirroring follows
  from a static inventory alone.
- Do not add Docker, a generic framework, CI/CD, IaC, UI, or public runtime
  downloads to this focused contract.
