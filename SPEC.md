# Specification: portable Nextflow offline bundle, Phase 1

## Goal

Build one complete, portable bundle on an **online server** and validate a
tiny nf-core pipeline locally in offline mode. The default is the existing
`nf-core/demo` revision `1.0.2` cache in the team's private S3 prefix.

An **offline server** consumes only the transferred bundle. It must not use
public networking, download, pull, install, or call AWS/S3/ECR at runtime.

## Authorization

The online build may read the approved private S3 cache, use public plugin
sources when a plugin is not already cached, and use the local tools Nextflow,
Podman or Docker, `jq`, and AWS CLI. A `SOURCE_MODE=public` fallback may use
`nf-core` and public pipeline/container sources. This authorization ends before
the offline smoke test.

No credentials, clinical data, production data, or environment-specific
secrets may enter Git or the bundle.

## Interface

```text
offline/build_offline_bundle.sh
offline/bundle.env
offline/params_offline.json
```

Run the builder from the online server with an empty `BUNDLE_ROOT` outside the
repository. Its default `SOURCE_MODE=s3-cache` reads the existing demo bundle
and the existing `rnaseq-tiny-20260624` fixture, stages the required plugin,
discovers images, reuses portable image archives, runs `nextflow ... -offline`,
and writes metadata/checksums. `SOURCE_MODE=public` retains the nf-core download
and image-pull path for a new pinned revision.

S3 publication is opt-in only. Set `PUBLISH_S3=yes` and an exact `S3_ROOT`;
the builder syncs to `<S3_ROOT>/<pipeline-name>/<revision>/`. The default is
`PUBLISH_S3=no`.

## Bundle contract

```text
<bundle>/
  workflow/                 pinned pipeline source
  configs/                  centralised configs, when supplied by the pipeline
  containers/*.tar          portable Podman/Docker archives
  plugins/nextflow-home/    Nextflow framework and plugin cache
  data/reads/               S3-sourced tiny FASTQ and samplesheet
  data/refs/                S3-sourced local references
  offline/                  params, custom smoke profile, smoke output
  manifests/                image, plugin, version, release, and SHA-256 data
  README.txt                offline transfer/load/run instructions
```

## Acceptance

- one configured command builds the default tiny pipeline bundle from the
  approved S3 cache;
- pipeline revision and all source/config/plugin/image/input assets are
  present below `BUNDLE_ROOT`;
- `NXF_OFFLINE=true`, `NXF_PLUGIN_AUTOINSTALL=false`, local executor, and the
  offline config are used for the smoke test;
- every exported image archive is a valid tar and is listed with its image ID
  and SHA-256 checksum;
- a SHA-256 manifest is generated for optional later transfer validation;
- local Nextflow offline smoke validation exits zero;
- generated bundle content stays outside Git;
- optional S3 publication is explicit and its destination is recorded.

## No-go and deferred work

Stop if the selected tiny pipeline cannot be bundled without a public runtime
dependency, image export fails, or a new external service is required.

Offline-server/EC2 proof, Sarek scale-up, ECR optimization, CodeBuild,
CloudOS, multi-pipeline catalogues, and production Ops/SOP work are deferred.
Existing `scrnaseq` scripts remain historical and are not changed by this
Phase 1 path.
