# Current Context

## Current Truth

- The canonical path is descriptor discovery -> ECR manifest -> Skopeo copy -> generated ECR override -> relocated Podman offline-emulation runtime.
- Registered pipelines are `demo`, `bamtofastq`, and `rnaseq` in `offline/pipeline_e2e.tsv`.
- Source-image discovery is truth. Files under `offline/reference/` are comparison/cache evidence only.
- The generic runtime uses a fresh Podman store, ECR preload, bundle-local `NXF_HOME`, `NXF_OFFLINE=true`, disabled plugin autoinstall, explicit `-offline`, and Podman `--network none --pull=never`.
- `docs/ops/**` remains a separate, validated colleague-facing Magic Script handoff.
- Sarek has only a preview active-path compatibility gate. Its current result is blocked because active images are not Quay-only. No Sarek runtime or image mirroring is authorized by default.

## Default Validation

1. Static script, descriptor, and config checks.
2. `discover_pipeline_e2e.sh --plan` for a descriptor.
3. Online discovery only when assets need refreshing.
4. Explicit ECR distribution only when image publication is required.
5. One relocated Podman runtime regression when changing the runtime contract.

This is **offline emulation** on an online server, not physical air-gap proof.

## Boundaries

- Keep generated bundles, logs, image data, and credentials outside Git.
- Do not make S3 transfer, ECR mirroring, or Sarek runtime part of an ordinary edit.
- Do not add a framework, CI platform, IaC, UI, or another workflow architecture.
