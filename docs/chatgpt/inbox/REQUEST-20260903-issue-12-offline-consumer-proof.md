# ChatGPT implementation packet — Issue #12

Canonical repository: `amitkarpe/nextflow-offline`
Canonical branch: `main`
Implementation branch: `feature/issue-12-offline-consumer-proof`
Owning Issue: https://github.com/amitkarpe/nextflow-offline/issues/12
Owning Draft PR: https://github.com/amitkarpe/nextflow-offline/pull/14

## Goal

Build and validate the portable `nf-core/demo` 1.0.2 bundle on the **same online server**, then relocate it to a different fresh local path and run it with strict offline-emulation controls.

This is the fast development validation loop. **Do not require S3 publication, S3 download, or a second offline server in this issue.**

This is Phase 2 only. Do not start Sarek.

## Merged anchors

- PR #6 — portable bundle builder + Podman offline smoke
- PR #11 — one bounded S3 publication/readback proof
- PR #13 — bounded S3 preflight hardening
- Issue #5 — Phase 1 completed

## Exactly one objective

On the same online server:

1. build a fresh `nf-core/demo` 1.0.2 bundle using the canonical `offline/build_offline_bundle.sh`;
2. explicitly keep `PUBLISH_S3=no`;
3. relocate/copy the completed bundle to a different fresh absolute path;
4. validate required bundle paths;
5. load the relocated bundle's container archives into Podman;
6. recover `workflow/bin/*` executable bits if required;
7. use only the relocated bundle's workflow, configs, data, refs and plugin/cache state;
8. run from the relocated bundle root with strict offline controls;
9. capture compact sanitized evidence of success.

## Preferred implementation

Keep this KISS. Reuse the merged builder and existing `offline_smoke` profile. Add only the smallest helper if useful, for example:

```text
offline/test_bundle_offline_local.sh
```

A preferred flow is:

```bash
BUILD_ROOT=/tmp/nextflow-demo-build
TEST_ROOT=/tmp/nextflow-demo-offline-test

PUBLISH_S3=no BUNDLE_ROOT="$BUILD_ROOT" \
  /usr/bin/bash offline/build_offline_bundle.sh

cp -a "$BUILD_ROOT" "$TEST_ROOT"
cd "$TEST_ROOT"

for image in containers/*.tar; do
  [ -f "$image" ] || continue
  podman load -i "$image"
done

chmod +x -c workflow/bin/* 2>/dev/null || true

export NXF_HOME="$PWD/plugins/nextflow-home"
export NXF_OFFLINE=true
export NXF_PLUGIN_AUTOINSTALL=false

nextflow run "$PWD/workflow" \
  -profile podman,offline_smoke \
  -params-file "$PWD/offline/params_offline.json" \
  -c "$PWD/offline/offline_test.conf" \
  --input data/reads/samplesheet.csv \
  --outdir ./results \
  -work-dir ./work \
  -offline
```

Codex may improve exact mechanics after inspecting current `main`, but must not change the architecture silently.

## Required runtime contract

Preserve:

```text
NXF_OFFLINE=true
NXF_PLUGIN_AUTOINSTALL=false
validate_params=false
custom_config_base=null
custom_config_version=null
pipelines_testdata_base_path=null
```

Also preserve:

- Podman only;
- local executor;
- explicit Nextflow `-offline`;
- bundle-local `NXF_HOME`;
- bundled workflow/config/data/refs/plugins only;
- `podman load` from bundled archives;
- task `--network none` through the existing `offline_smoke` profile;
- no Docker;
- no S3 publication/download for the normal proof.

## Acceptance criteria

- [ ] fresh demo bundle build exits `0`;
- [ ] `PUBLISH_S3=no`;
- [ ] relocated test path differs from build path;
- [ ] `workflow/`, `containers/`, `plugins/`, `data/`, `offline/`, `manifests/`, `README.txt` are present;
- [ ] all required archives load with Podman;
- [ ] bundle-local `NXF_HOME` is used;
- [ ] `NXF_OFFLINE=true`;
- [ ] `NXF_PLUGIN_AUTOINSTALL=false`;
- [ ] explicit `-offline`;
- [ ] Podman tasks retain `--network none`;
- [ ] FASTQC, SEQTK_TRIM and MULTIQC (or equivalent pinned demo stages) complete;
- [ ] pipeline exits `0`;
- [ ] no S3 publication/download or separate offline server is needed to claim Issue #12 success.

## What this proves / does not prove

This proves a fast, repeatable **offline-emulation** validation on the online server and catches bundle portability, plugin, container and path errors.

It does **not** prove the host has physically no internet route. A real offline-server/air-gapped test remains a later release acceptance gate.

## No-go gates

Stop and report in this existing PR if:

1. the relocated bundle requires a public runtime download;
2. a required plugin is absent;
3. a required image cannot be loaded from the bundle archives;
4. any path still depends on the original build location;
5. Docker is required instead of Podman;
6. the bundle contract must materially change;
7. S3/offline-server/AWS infrastructure work becomes required merely to pass this fast validation.

Do not create a replacement Issue, branch or PR.

## Explicitly out of scope

- Sarek;
- S3 publish/download proof in this milestone;
- separate offline server / EC2 proof;
- ECR/ACR/Nexus;
- Docker;
- CodeBuild/CodePipeline;
- CloudOS;
- Terraform/CDK/CloudFormation;
- multi-pipeline framework;
- production/clinical data;
- general Ops/SOP work.

## Evidence format

Finish with `SUCCESS`, `PARTIAL`, `BLOCKED`, `FAILED`, or `UNKNOWN_PENDING`.

Recommended compact evidence:

```text
PIPELINE=nf-core/demo
REVISION=1.0.2
BUILD_RC=0
PUBLISH_S3=no
BUILD_ROOT=<sanitized temp path>
TEST_ROOT=<different sanitized temp path>
REQUIRED_BUNDLE_PATHS=PASS
PODMAN_ARCHIVES_LOADED=<count>
NXF_OFFLINE=true
NXF_PLUGIN_AUTOINSTALL=false
PODMAN_NETWORK=none
PIPELINE_RC=0
RESULT=SUCCESS
```

Never commit credentials, account IDs, ARNs, private endpoints, IPs, customer/clinical data or raw cloud payloads.

## Codex operating instruction

Work only inside this existing branch / Draft PR #14 for Issue #12. Preserve unrelated work. If an architectural deviation is required, report it in PR #14 and stop for ChatGPT/Amit review.
