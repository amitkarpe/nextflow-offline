# REQUEST — Issue #17 Sarek scale-up

## Repository / tracking

- Repository: `amitkarpe/nextflow-offline`
- Base branch: `main`
- Issue: https://github.com/amitkarpe/nextflow-offline/issues/17
- Implementation branch: `feature/issue-17-sarek-scale-up`
- Implementation PR: create exactly one Draft PR from this branch to `main`

## User decision

Issue #12 / PR #14 is complete and merged. The user has explicitly chosen **Sarek as the next implementation milestone**.

`AGENTS.md` may still contain wording that Sarek is a later task. That wording described the pre-Issue-17 state. For task ordering only, this request + Issue #17 supersede that stale sentence. All other repository rules in `AGENTS.md`, `CONTEXT.md`, `SPEC.md`, and `docs/validation-strategy.md` remain mandatory.

## Objective

Scale the proven canonical `offline/**` bundle contract from `nf-core/demo` to:

```text
PIPELINE=nf-core/sarek
REVISION=3.10.0
CONTAINER_ENGINE=podman
PUBLISH_S3=no
```

The first target is a **same-online-server relocated Level-1 offline-emulation proof**, not an AWS/offline-server proof.

## Architecture that must be preserved

```text
ONLINE SERVER
  -> prepare pinned Sarek 3.10.0
  -> materialize tiny valid input + all required refs locally
  -> stage bundle-local Nextflow plugins/cache
  -> inventory exact required containers
  -> require quay.io-only container sources for the selected path
  -> create portable Podman-loadable archives in bundle
  -> PUBLISH_S3=no
  -> relocate complete bundle to fresh different path
  -> isolated empty Podman store
  -> load only relocated bundle archives
  -> bundle-local NXF_HOME
  -> NXF_OFFLINE=true
  -> NXF_PLUGIN_AUTOINSTALL=false
  -> explicit nextflow -offline
  -> Podman task --network none
  -> minimal Sarek path PASS / truthful terminal state
```

Do not revive the old closed Issue #1 ECR-first architecture.

## Read before implementation

1. `AGENTS.md`
2. `CONTEXT.md`
3. `SPEC.md`
4. `docs/validation-strategy.md`
5. Issue #17
6. merged PR #14 implementation and evidence
7. existing Sarek reference files:
   - `offline/prepare_sarek_offline_test.sh`
   - `offline/run_sarek_offline.sh`
   - `offline/params_sarek_offline.json`

The old Sarek scripts are reference/compatibility material only. Their mandatory ECR behavior is not the target architecture.

## Preferred implementation surface

Reuse/extend the canonical path where practical:

- `offline/build_offline_bundle.sh`
- `offline/test_bundle_offline_local.sh`
- `scripts/fetch_and_save_images.sh`
- `offline/offline_test.conf`
- `offline/params_sarek_offline.json`

A small Sarek-specific helper or wrapper is allowed when the pipeline genuinely needs a different samplesheet/reference preparation shape. Do not create a second bundle contract.

Do not modify `docs/ops/**`.

## First gate — cheap inventory before expensive downloads

Before large image pulls/archives:

1. inspect Sarek 3.10.0 with the smallest valid execution path;
2. determine the exact unique container inventory needed by that path;
3. report image count and registry distribution;
4. assert all required image references are `quay.io/...`.

If any required image is not on `quay.io`, stop and report:

```text
RESULT=BLOCKED
OFFLINE_SAFE=false
reason=non-quay required image(s)
```

Do not silently switch to Docker Hub, GHCR, Wave, ECR, Nexus, or another revision.

## Sarek data/reference requirements

Do not reuse the demo three-column input parser blindly.

Inspect Sarek 3.10.0 and materialize the smallest valid non-production test path:

- correct Sarek samplesheet columns;
- one tiny sample where valid;
- all required reference assets copied into `data/refs/`;
- explicit local paths in generated params/config;
- no runtime dependency on `testdata.nf-core.sarek`, nf-core test-dataset URLs, institutional config URLs, schema downloads, plugin downloads, or public reference URLs.

The existing `tools=strelka` setting is only a starting hypothesis. Confirm the smallest valid path from repository/upstream truth before relying on it.

## Offline controls

Relocated runtime must include:

```text
NXF_OFFLINE=true
NXF_PLUGIN_AUTOINSTALL=false
validate_params=false
custom_config_base=null
custom_config_version=null
pipelines_testdata_base_path=null
```

Plus:

- explicit `-offline`;
- bundle-local `NXF_HOME`;
- local executor;
- Podman only;
- archives loaded from relocated bundle into an initially empty isolated Podman store;
- task `--network none`;
- no public runtime downloads.

## Scale safeguards

Sarek can be much larger than demo. Keep safeguards KISS:

- image count before pulls;
- disk free-space preflight;
- aggregate archive size reported;
- fail clearly on insufficient disk;
- use preparation cache only when safe;
- final proof must still load from the relocated bundle archives, not trust host cache.

Add resumability only if an actual failure demonstrates a need.

## Required validation

Run at least:

```bash
/usr/bin/bash -n <all changed shell scripts>
```

Validate changed JSON/config/samplesheet material with focused commands.

Do not add a broad CI framework.

## Expected evidence

Post compact evidence in the existing PR:

```text
PIPELINE=nf-core/sarek
REVISION=3.10.0
PUBLISH_S3=no

SHELL_STATIC=PASS
CONFIG_VALIDATION=PASS
SAMPLESHEET_VALIDATION=PASS

IMAGE_COUNT=<n>
IMAGE_REGISTRIES=quay.io
QUAY_ONLY=PASS
IMAGE_ARCHIVE_BYTES=<bytes>
DISK_PREFLIGHT=PASS

BUILD_RC=<rc>
REQUIRED_BUNDLE_PATHS=PASS|FAIL
CHECKSUMS=PASS|FAIL
RELOCATED_BUNDLE=PASS|FAIL

PODMAN_STORE_INITIAL=EMPTY
PODMAN_ARCHIVES_LOADED=<n>
IMAGE_TAG_MAPPING=PASS|FAIL

NXF_HOME=bundle-local
NXF_OFFLINE=true
NXF_PLUGIN_AUTOINSTALL=false
NEXTFLOW_OFFLINE_FLAG=true
PODMAN_NETWORK=none

PIPELINE_RC=<rc>
EXPECTED_SAREK_STAGES=PASS|PARTIAL|FAIL
PUBLIC_RUNTIME_DOWNLOADS=NONE_OBSERVED|BLOCKED

RESULT=SUCCESS|PARTIAL|BLOCKED|FAILED
```

If full Sarek runtime is too expensive after a correct complete bundle is produced, return `PARTIAL` with exact remaining work. Do not overclaim.

## Non-goals

Do not add:

- S3 publication/readback for Sarek;
- separate offline server / EC2;
- ECR/ACR/Nexus publication;
- Docker runtime;
- Skopeo as a canonical dependency;
- CodeBuild/CodePipeline;
- CloudOS;
- Terraform/CDK/CloudFormation;
- production/clinical data;
- rnaseq or another pipeline;
- broad Ops/SOP work.

## Collaboration rule

Work only in the existing Issue #17 and its single Draft PR. Do not create a replacement Issue, branch, or PR. If architecture must change, report the blocker in the existing PR and wait for ChatGPT review.
