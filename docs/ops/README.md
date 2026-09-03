# Nextflow offline “magic script” — ops handoff

Copy this folder by itself. It is intentionally isolated from the repository's main `offline/` implementation and from Codex PR #6.

## Flow

```text
ONLINE SERVER
  pipeline + revision + pipelines.tsv + testdata.tsv
              |
              v
       magic-online.sh
       - nf-core download
       - materialize test data / refs
       - pre-stage Nextflow plugin cache
       - nextflow inspect
       - Skopeo registry -> docker-archive
       - manifest + checksums
              |
              v
s3://trust-team/nextflow-offline/bundles/<pipeline>-<revision>/magic-v1/
              |
              v
OFFLINE SERVER
       magic-offline.sh
       - S3 sync
       - checksum validation
       - podman load
       - optional nextflow -offline
```

## Why these tools

- **Skopeo**: direct registry-to-archive copy; no local pull/tag/save cycle is needed. Set `IMAGE_MODE=registry` for direct registry-to-registry copy to an ECR/ACR/Nexus-style target after authenticating Skopeo.
- **Podman**: loads archives and executes containers on the offline server.
- **Buildah**: not required here. Use it only if a future pipeline needs a custom image build or mutation.
- **AWS CLI**: moves generated bundle files to/from S3. Skopeo does not have an `s3://` image transport.

Current nf-core tooling also supports Docker/Podman-oriented offline container downloads. This folder keeps Skopeo explicit because it matches the established direct-copy workflow and avoids depending on a local Docker daemon.

## Files

- `magic.env.example` — defaults; copy to `.env`
- `pipelines.tsv` — pipeline + revision + profiles
- `testdata.tsv` — explicit asset catalogue
- `magic-online.sh` — build + validate + S3 publish
- `validate-bundle.sh` — structure/checksum/offline-config validation
- `magic-offline.sh` — S3 pull + Podman load + optional run
- `params_offline.json`, `offline_test.conf` — remote-dependency hardening
- `examples/` — tiny samplesheets and one-argument-per-line run files

## Default demo

```bash
cp magic.env.example .env
./magic-online.sh
```

Defaults:

```text
AWS_PROFILE=dev
S3_ROOT=s3://trust-team/nextflow-offline
PIPELINE=demo
REVISION=1.0.2
IMAGE_MODE=archive
```

The default target is deliberately non-destructive:

```text
s3://trust-team/nextflow-offline/bundles/demo-1.0.2/magic-v1/
```

Override `S3_BUNDLE_URI` in `.env` when an exact destination is required.

## Online prerequisites

```text
nf-core
nextflow
jq
curl
skopeo
aws
```

The builder downloads pipeline source with `nf-core pipelines download --container-system none`, materializes the selected test assets, points `NXF_HOME` into the bundle so online `nextflow inspect` can populate required plugin cache content, discovers container references, and uses Skopeo to write portable Docker archives preserving the original image name/tag.

nf-core `test` profiles normally reference online test data, so this folder uses `test,podman` only for **online discovery**. Offline execution uses local materialized inputs plus the ordinary `podman` profile.

## Offline server

Stage + verify + load images:

```bash
./magic-offline.sh
```

Run the bundled pipeline too:

```bash
RUN_PIPELINE=yes ./magic-offline.sh
```

Runtime hardening includes:

```text
NXF_OFFLINE=true
NXF_PLUGIN_AUTOINSTALL=false
custom_config_base=null
custom_config_version=null
pipelines_testdata_base_path=null
validate_params=false
```

## RNA-seq example

The catalogue reuses the existing tiny S3 data:

```text
s3://trust-team/nextflow-offline/data/rnaseq-tiny-20260624/
```

Run:

```bash
PIPELINE=rnaseq REVISION=3.18.0 ./magic-online.sh
```

The example samplesheet uses the standard `sample,fastq_1,fastq_2,strandedness` columns and passes bundled FASTA/GTF explicitly.

## Test data

`testdata.tsv` supports:

```text
https://...   public download on the online server
s3://...      existing S3 object using AWS profile dev
repo://...    file shipped in this docs/ops folder
```

The seeded demo input follows the nf-core test-datasets samplesheet pattern. RNA-seq uses the already-staged tiny data. `nf-test` is useful later for assertion-level workflow tests but is not required to demonstrate bundle preparation.

## Add another pipeline

1. Add a row to `pipelines.tsv`.
2. Add minimal assets to `testdata.tsv`.
3. Add `examples/<pipeline>-samplesheet.csv` and `examples/<pipeline>.run.args`.
4. Run with `PIPELINE=<name> REVISION=<version> ./magic-online.sh`.

Keep missing assets visible: the script should fail rather than depend on public downloads at offline runtime.

## Safety

- Generated bundles stay under `/tmp` and S3, never Git.
- Do not commit `.env` if it contains anything sensitive.
- `AWS_PROFILE=dev` assumes credentials are already configured.
- No AWS infrastructure is created or modified by these scripts; only S3 object transfer occurs in archive mode.
