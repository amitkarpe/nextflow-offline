# Nextflow offline bundle demo

This repository contains a small Phase 1 “magic script” for preparing one
portable offline bundle. It defaults to the existing private S3 cache for
`nf-core/demo` revision `1.0.2`, with the existing `rnaseq-tiny-20260624`
fixture and Podman image archives.

The two environments are deliberately separate:

- **online server:** downloads the pinned workflow, configs, plugins, input
  data, and container images;
- **offline server:** receives the finished bundle, loads local image archives,
  and runs Nextflow with `-offline`.

## Build on the online server

Prerequisites: Bash, Nextflow, `jq`, Podman (or Docker), AWS CLI with the
approved `dev` profile, and access to the private S3 prefixes during
preparation. Choose an empty output directory outside Git.

```bash
cd /path/to/nextflow-offline-demo
BUNDLE_ROOT=/path/to/bundles/demo-1.0.2 \
  /usr/bin/bash offline/build_offline_bundle.sh
```

The default script reads the pinned workflow and image archives from the
existing S3 cache, copies the selected tiny FASTQ/reference fixture, installs
the required Nextflow plugin in the bundle, loads the bundle image archives
into Podman, performs a local offline smoke run, and writes
`manifests/files.sha256`. No public image pull is needed. Set
`LOAD_BUNDLE_IMAGES=no` only when intentionally skipping the bundle-load proof.

Configuration defaults can be overridden in `offline/bundle.env` or the
environment:

```bash
PIPELINE=nf-core/demo REVISION=1.0.2 PROFILE=podman \
  SOURCE_MODE=s3-cache DATA_S3_PREFIX=s3://trust-team/nextflow-offline/data/rnaseq-tiny-20260624 \
  CONTAINER_ENGINE=podman BUNDLE_ROOT=/path/to/empty/bundle \
  /usr/bin/bash offline/build_offline_bundle.sh
```

To prepare a new public revision instead, set `SOURCE_MODE=public` and use an
empty bundle path. The builder stages the HTTP test samplesheet from the
downloaded pipeline's `conf/test.config` and its FASTQ files into the bundle
before the smoke run. That path is slower because it pulls every image.

S3 publication is disabled by default. For a bounded proof, use an exact empty
test prefix. The builder rejects a non-empty prefix unless
`PUBLISH_REQUIRE_EMPTY=no` is explicitly set:

```bash
AWS_PROFILE=dev PUBLISH_S3=yes \
  PUBLISH_PREFIX=s3://bucket/prefix/issue-10-test/ \
  BUNDLE_ROOT=/path/to/empty/bundle \
  /usr/bin/bash offline/build_offline_bundle.sh

AWS_PROFILE=dev /usr/bin/bash offline/verify_published_bundle.sh \
  s3://bucket/prefix/issue-10-test/
```

## Consume on the offline server

Transfer the complete bundle directory, then load every archive:

```bash
cd /path/to/bundle
for image in containers/*.tar containers/*.tgz; do
  [ -f "$image" ] || continue
  podman load -i "$image"
done
```

Run using only local bundle assets:

```bash
NXF_VER=25.10.4 NXF_OFFLINE=true NXF_PLUGIN_AUTOINSTALL=false \
  NXF_HOME="$PWD/plugins/nextflow-home" \
  nextflow run "$PWD/workflow" -profile podman,offline_smoke \
  -params-file "$PWD/offline/params_offline.json" \
  -c "$PWD/offline/offline_test.conf" \
  --input "$PWD/data/reads/samplesheet.csv" \
  --outdir "$PWD/results" -work-dir "$PWD/work" -offline -resume
```

The fast path is Podman-only. Docker support remains an unvalidated future
option and is not part of this smoke proof.

The existing `scrnaseq` scripts are preserved as historical examples. Sarek
is a later phase and is not claimed as proven by this demo.
