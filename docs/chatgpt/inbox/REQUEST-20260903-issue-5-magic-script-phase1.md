# Codex implementation packet: Issue #5 Phase 1

## Authority

- Repository: `amitkarpe/nextflow-offline`
- Canonical branch: `main`
- Implementation Issue: #5
- Implementation branch: `feature/issue-5-magic-script-phase1`
- Target PR base: `main`

This packet exists to keep Codex implementation bounded inside one existing Draft PR.

## Goal

Implement Phase 1 of Issue #5 only: one simple `build_offline_bundle.sh` “magic script” that runs on an **online server**, prepares a complete portable offline bundle for one tiny nf-core pipeline, validates that bundle with Nextflow offline mode, and uploads the complete bundle to S3.

The immediate deliverable is the bundle builder + concise documentation/demo. Running the bundle on a separate offline server is deferred.

## Terminology

Use only:

- **online server** — may access public sources during bundle preparation
- **offline server** — no public internet; consumes only pre-staged assets

Do not use personal-device terms in project documentation.

## Phase 1 scope

Prefer `nf-core/demo` unless repository truth shows another tiny nf-core pipeline is materially more suitable.

Implement/refactor a KISS interface around:

```text
offline/
  build_offline_bundle.sh
  bundle.env
  params_offline.json
```

The builder should, from one invocation:

1. validate tools and config;
2. pin pipeline + revision;
3. use temporary storage outside Git;
4. download pipeline assets using `nf-core pipelines download` where practical;
5. include the selected tiny test input and required references;
6. discover required container images;
7. pull those images with Podman on the online server;
8. save portable container archives inside the bundle;
9. pre-stage required Nextflow plugins/cache;
10. generate offline params/config that prevent known remote nf-core/plugin dependencies;
11. generate inventory, release metadata, and checksums;
12. produce one self-contained bundle directory;
13. run a local `nextflow ... -offline` smoke validation using only the prepared bundle;
14. upload/sync the complete bundle to S3.

Use ordinary tools first: nf-core tools, Nextflow, Podman, AWS CLI. Do not add extra transfer tooling without a demonstrated need.

## Target bundle contract

```text
<bundle>/
  workflow/
  containers/
  plugins/
  data/
    reads/
    refs/
  offline/
    params_offline.json
    offline_test.conf
  manifests/
    pipeline.env
    images.txt
    files.sha256
    release.env
  README.txt
```

Heavy generated content must stay outside Git.

## Offline hardening to preserve

At minimum preserve these controls where applicable:

```text
NXF_OFFLINE=true
NXF_PLUGIN_AUTOINSTALL=false
validate_params=false
custom_config_base=null
custom_config_version=null
pipelines_testdata_base_path=null
```

Pipeline-specific remote dependencies should be discovered and pre-staged/disabled by the builder, not left as manual runtime steps.

## Reuse guidance

Inspect existing work before implementation:

- merged Sarek scaffold already in this repository;
- `mytestlab123/offline` for common/per-pipeline structure;
- `mytestlab123/pipeline` for historical pipeline ideas;
- `amitkarpe/rnaseq` for pipeline download and S3 push/pull patterns.

Reuse only what makes Phase 1 simpler. Do not copy older architecture blindly.

## Acceptance criteria

- [ ] One command/config builds the selected tiny-pipeline bundle.
- [ ] Pipeline revision is pinned.
- [ ] Pipeline source is included.
- [ ] Test input/reference assets are included.
- [ ] Required container images are included as portable archives.
- [ ] Required plugin/cache content is included if needed.
- [ ] Offline runtime config blocks known remote nf-core/plugin dependencies.
- [ ] Manifest + checksums are generated.
- [ ] Local Nextflow offline-mode smoke validation succeeds using the bundle.
- [ ] The complete bundle is uploaded to S3.
- [ ] No heavy generated content is committed to Git.
- [ ] README explains the “magic script” flow for another engineer.

## No-go gates

Stop and report in Issue #5 / this Draft PR instead of silently changing direction if:

1. `nf-core/demo` is unsuitable and another pipeline must be selected;
2. the chosen pipeline cannot be bundled without a public runtime dependency;
3. portable image export cannot be achieved with the Podman-based approach;
4. Phase 1 requires a new external service;
5. CodeBuild, ECR, CloudOS, IaC, or live infrastructure changes become mandatory merely to prove the builder;
6. the builder becomes hard-coded to one pipeline instead of parameter-driven;
7. heavy generated assets would need to be committed to Git.

## Deferred

- offline-server/EC2 runtime proof;
- Sarek bundle scale-up;
- ECR optimization;
- CodeBuild/CodePipeline automation;
- CloudOS integration;
- multi-pipeline catalogue/framework;
- production Ops/SOP work.

## Codex workflow

Work only in the existing branch/PR for this milestone. Do not create a replacement Issue or PR. Keep directly related implementation, tests, documentation, and fixes in the same PR.

Use truthful terminal states: `SUCCESS`, `PARTIAL`, `BLOCKED`, `FAILED`, or `UNKNOWN_PENDING`.
