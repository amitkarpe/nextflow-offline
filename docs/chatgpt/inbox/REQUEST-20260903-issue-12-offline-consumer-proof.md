# ChatGPT implementation packet — Issue #12

Canonical repository: `amitkarpe/nextflow-offline`
Canonical branch: `main`
Implementation branch: `feature/issue-12-offline-consumer-proof`
Owning Issue: https://github.com/amitkarpe/nextflow-offline/issues/12

## Goal

Prove that the already-published `nf-core/demo` 1.0.2 bundle can be consumed on a separate **offline server** without any public runtime dependency.

This is Phase 2 only. Do not start Sarek.

## Phase 1 anchors already merged

- PR #6 — portable magic-bundle builder + local Podman offline smoke
- PR #11 — bounded S3 publication/readback proof
- PR #13 — bounded S3 preflight pagination hardening
- Phase 1 summary — Issue #5 closed completed

Published proof prefix:

```text
s3://trust-team/nextflow-offline/bundles/demo-1.0.2/issue-10-publish-proof-20260903-170603/
```

Authorized AWS profile for the proof:

```text
AWS_PROFILE=dev
```

## Exactly one objective

On one authorized non-production **offline server**:

1. sync the exact published bundle from S3 to a fresh local directory;
2. verify the required bundle paths;
3. optionally verify `manifests/files.sha256` if this remains KISS;
4. load only the bundled container archives into Podman;
5. recover `workflow/bin/*` executable bits if needed;
6. use the bundle-local Nextflow plugin/cache state;
7. run `nf-core/demo` 1.0.2 from the bundle root with explicit offline controls;
8. capture sanitized evidence showing the transferred bundle completes without public runtime downloads.

## Preferred implementation shape

Keep this small. Reuse the merged bundle contract. Preferred new helper:

```text
offline/consume_published_bundle.sh
```

The helper should be parameterized through environment variables, with high-fidelity defaults such as:

```text
AWS_PROFILE=dev
SOURCE_PREFIX=s3://trust-team/nextflow-offline/bundles/demo-1.0.2/issue-10-publish-proof-20260903-170603/
BUNDLE_ROOT=<fresh local path>
PIPELINE=nf-core/demo
REVISION=1.0.2
```

Do not add YAML or another framework.

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

Runtime assumptions:

- Podman only;
- local executor;
- explicit `nextflow ... -offline`;
- bundle-local `NXF_HOME`;
- bundled workflow/config/data/refs/plugins only;
- `podman load` from `containers/*.tar`;
- task `--network none` where already supplied by the merged `offline_smoke` profile.

## KISS consumer flow

```text
aws s3 sync <SOURCE_PREFIX> <BUNDLE_ROOT>/
  -> required path checks
  -> optional sha256sum -c manifests/files.sha256
  -> podman load containers/*.tar
  -> chmod +x -c workflow/bin/* if present
  -> cd <BUNDLE_ROOT>
  -> NXF_OFFLINE=true
  -> NXF_PLUGIN_AUTOINSTALL=false
  -> NXF_HOME=$PWD/plugins/nextflow-home
  -> nextflow run $PWD/workflow ... -offline
```

The local destination must be a different absolute path from the online-server build location so portability is actually tested.

## Acceptance criteria

### Transfer

- [ ] exact Phase 1 S3 proof prefix is used;
- [ ] S3 sync exits `0`;
- [ ] local destination is fresh and relocates the bundle;
- [ ] `workflow/`, `containers/`, `plugins/`, `data/`, `offline/`, `manifests/`, and `README.txt` are present;
- [ ] S3 objects are not modified or deleted.

### Runtime

- [ ] all required container archives load with Podman;
- [ ] no public registry pull is needed;
- [ ] bundle-local plugin/cache state is used;
- [ ] `NXF_OFFLINE=true` is effective;
- [ ] `NXF_PLUGIN_AUTOINSTALL=false` is effective;
- [ ] explicit `-offline` is present;
- [ ] pipeline exits `0`;
- [ ] expected demo stages complete, including FASTQC, SEQTK_TRIM, and MULTIQC for the pinned revision;
- [ ] expected output is produced from the transferred bundle.

### Offline boundary

If the proof uses EC2, record sanitized evidence that:

- approved private S3 access succeeds;
- no public IP/general public runtime path is intended;
- GitHub, quay.io, and Docker Hub are not required by the successful run.

Do not treat a failed `curl` alone as proof. The pipeline itself must complete from the bundle.

## No-go gates

Stop and report in this existing PR if:

1. the bundle requires a public runtime download;
2. a required plugin is absent from the bundle;
3. a required image cannot be loaded from the bundle archives;
4. any path still depends on the original online-server build location;
5. Docker is required instead of Podman;
6. the bundle contract must materially change;
7. broader AWS/network/IAM mutation is required beyond the explicitly authorized offline-server test.

Do not create a replacement PR or silently change architecture.

## Explicitly out of scope

- Sarek;
- ECR/ACR/Nexus publication;
- CodeBuild/CodePipeline;
- CloudOS;
- Terraform/CDK/CloudFormation;
- Docker smoke;
- multi-pipeline framework;
- production/clinical data;
- general Ops/SOP work.

## Evidence format

Finish with one truthful terminal state: `SUCCESS`, `PARTIAL`, `BLOCKED`, `FAILED`, or `UNKNOWN_PENDING`.

Recommended compact evidence:

```text
PIPELINE=nf-core/demo
REVISION=1.0.2
AWS_PROFILE=dev
SOURCE_PREFIX=s3://trust-team/nextflow-offline/bundles/demo-1.0.2/issue-10-publish-proof-20260903-170603/
S3_PULL_RC=0
REQUIRED_BUNDLE_PATHS=PASS
CHECKSUMS=PASS|SKIPPED
PODMAN_ARCHIVES_LOADED=3
NXF_OFFLINE=true
NXF_PLUGIN_AUTOINSTALL=false
PIPELINE_RC=0
PUBLIC_RUNTIME_DOWNLOADS=NONE_OBSERVED
RESULT=SUCCESS
```

Never commit credentials, account IDs, ARNs, private endpoint identifiers, IPs, customer/clinical data, or raw cloud payloads.

## Codex operating instruction

Work only inside this existing branch / Draft PR for Issue #12. Preserve unrelated work. If implementation needs an architectural deviation, report it in the PR and stop for ChatGPT/Amit review instead of creating another Issue/branch/PR.
