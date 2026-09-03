# Nextflow offline bundle demo

This repository demonstrates a KISS path for preparing and validating portable Nextflow offline bundles.

The default proof target is `nf-core/demo` revision `1.0.2` with Podman. Heavy workflow assets, data, plugins/cache, and container archives stay outside Git.

## Current project direction

Use progressive validation instead of repeating the most expensive proof on every change:

```text
Level 0  static checks
   ->
Level 1  same-online-server offline emulation  [default fast loop]
   ->
Level 2  bounded S3 publish/readback           [occasional transfer proof]
   ->
Level 3  real offline-server execution         [acceptance gate]
   ->
Level 4  pipeline scale-up: rnaseq/Sarek/etc.
```

See `docs/validation-strategy.md` for what each level proves.

Current canonical implementation milestone:

- Issue #12 / PR #14 — fast same-**online server** relocated-bundle offline-emulation proof for the canonical `offline/` implementation.

Validated colleague-facing handoff:

- `docs/ops/**` — merged through PR #8 after a successful `nf-core/demo` 1.0.2 relocated offline-emulation proof. The proof loaded all three portable image archives into isolated Podman storage, preserved image names/tags, used bundle-local Nextflow state, explicit `-offline`, and task network isolation. S3 publication was not part of that proof.

These are separate implementation paths. Do not silently combine them; promote shared ideas only through focused reviewed changes.

Sarek is a later scale-up milestone, not the immediate default task.

## Terminology

- **online server** — prepares assets and may access approved public/private sources;
- **offline server** — consumes pre-staged assets without public internet dependency;
- **offline emulation** — runs a relocated bundle on the same online server with strict offline controls.

Offline emulation is useful for fast engineering validation, but it does **not** prove that the host itself has no internet route.

## Build on the online server

Prerequisites for the current canonical path: Bash, Nextflow, `jq`, Podman, AWS CLI when using the private S3 cache, and access to the selected preparation sources.

Choose an empty bundle directory outside Git:

```bash
cd /path/to/nextflow-offline

PUBLISH_S3=no \
BUNDLE_ROOT=/tmp/nextflow-demo-build \
  /usr/bin/bash offline/build_offline_bundle.sh
```

The default `SOURCE_MODE=s3-cache` reads the pinned demo workflow/image cache and tiny approved fixture, stages bundle-local plugin/cache state, loads bundled image archives, runs the repo-owned Podman offline smoke, and writes manifests/checksums.

A `SOURCE_MODE=public` preparation fallback exists for a new pinned revision. Any public test data discovered during preparation must be staged locally before runtime validation.

## Fast validation: same online server

This is the preferred developer/PR loop.

Build with:

```text
PUBLISH_S3=no
```

Then relocate/copy the complete bundle to a different fresh local path and run only from that relocated copy.

Required runtime controls:

```bash
export NXF_HOME="$PWD/plugins/nextflow-home"
export NXF_OFFLINE=true
export NXF_PLUGIN_AUTOINSTALL=false
```

Load bundled archives:

```bash
for image in containers/*.tar containers/*.tgz; do
  [ -f "$image" ] || continue
  podman load -i "$image"
done
```

If executable bits were lost during a transfer/copy path:

```bash
chmod +x -c workflow/bin/* 2>/dev/null || true
```

Run from the relocated bundle root:

```bash
NXF_VER=25.10.4 \
NXF_OFFLINE=true \
NXF_PLUGIN_AUTOINSTALL=false \
NXF_HOME="$PWD/plugins/nextflow-home" \
  nextflow run "$PWD/workflow" \
  -profile podman,offline_smoke \
  -params-file "$PWD/offline/params_offline.json" \
  -c "$PWD/offline/offline_test.conf" \
  --input data/reads/samplesheet.csv \
  --outdir ./results \
  -work-dir ./work \
  -offline
```

The `offline_smoke` profile uses the local executor and Podman task network isolation. The fast proof should use only bundled workflow/config/data/refs/plugins/images.

`nextflow -offline` is one control in this proof; by itself it is not evidence of an air-gapped host.

## Standalone colleague-facing Magic Script

The merged `docs/ops/**` path is intended to be copied as a small handoff package. Start with:

```bash
cd docs/ops
cp magic.env.example .env
PUBLISH_S3=no ./magic-online.sh
```

Its demo path has already passed same-online-server relocated-bundle offline emulation. See `docs/ops/README.md` for its own workflow and constraints.

Do not treat its optional S3 publication path as proven merely because the local proof passed; validate transfer behavior separately when that feature is needed.

## Optional S3 transfer/release proof

S3 publication is **not required for every engineering test**.

Use it only when the task owns a transfer/release proof:

```bash
AWS_PROFILE=dev \
PUBLISH_S3=yes \
PUBLISH_PREFIX=s3://bucket/prefix/bounded-test/ \
BUNDLE_ROOT=/path/to/empty/bundle \
  /usr/bin/bash offline/build_offline_bundle.sh
```

Read back the published structure without modifying it:

```bash
AWS_PROFILE=dev \
  /usr/bin/bash offline/verify_published_bundle.sh \
  s3://bucket/prefix/bounded-test/
```

The canonical builder rejects a non-empty publication prefix by default.

## Real offline-server acceptance

A later acceptance gate may transfer the prepared bundle to a real **offline server** through an approved path and repeat the run there.

That gate proves something stronger than Level 1: the environment itself has no public runtime dependency. Do not claim this from flags or failed network probes alone; the actual pipeline must complete from the prepared assets.

## Bundle contract

```text
<bundle>/
  workflow/
  configs/                  # when supplied
  containers/
  plugins/nextflow-home/
  data/reads/
  data/refs/
  offline/
  manifests/
  README.txt
```

The core contract is that moving this complete directory must not require the original online-server absolute path.

## Later pipeline scale-up

After the validation/bundle contract is stable, apply the same pattern to pipelines such as rnaseq and Sarek.

Do not create a separate Sarek architecture unless a real reviewed blocker proves the shared bundle contract is insufficient.

The existing `scrnaseq` scripts are preserved as historical examples. Docker support remains outside the current fast proof.
