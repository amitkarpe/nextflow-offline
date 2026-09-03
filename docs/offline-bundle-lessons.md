# Offline bundle lessons

This note records the practical lessons behind the fast Nextflow offline-bundle proof.

For the current validation hierarchy and claim boundaries, see `docs/validation-strategy.md`.

## The important distinction

The pipeline source can be small while its container images are large. The `nf-core/demo` 1.0.2 proof used three images totalling about 620 MiB. Image import, not processing the tiny reads, was the slow part.

The upstream demo test profile is not an offline input profile. Its `conf/test.config` points `params.input` at a public samplesheet:

<https://raw.githubusercontent.com/nf-core/demo/master/conf/test.config>

That samplesheet points at more public FASTQ URLs:

<https://raw.githubusercontent.com/nf-core/test-datasets/viralrecon/samplesheet/samplesheet_test_illumina_amplicon.csv>

Using that profile unchanged would make runtime depend on public network access. If upstream parity is needed, stage the samplesheet and every required FASTQ locally first. For the normal smoke check, use one approved tiny paired-input fixture instead.

## What went wrong previously

1. The first preparation started from the public pipeline path before the existing private cache was inventoried.
2. A public revision/image path caused multi-gigabyte image export and storage pressure even though the workflow itself was small.
3. The upstream test profile was treated as if it described local test data; it actually contains a remote input URL.
4. Resource settings were copied manually into a generated config instead of using a repo-owned `offline_smoke` profile.
5. An offline consumer initially selected the host's Nextflow framework version. Pin `NXF_VER` to the framework bundled with the bundle.
6. Early validation mixed bundle correctness, S3 transfer, and real offline-server acceptance into one expensive loop. These are different questions and should use different validation levels.

## Fast standard

Use `offline/build_offline_bundle.sh` with:

- the pinned workflow/revision;
- the existing tiny local fixture;
- Podman as the supported smoke engine;
- `offline_smoke` plus the Podman profile;
- `NXF_OFFLINE=true`, `NXF_PLUGIN_AUTOINSTALL=false`, and explicit `-offline`;
- an empty bundle output directory outside Git;
- `PUBLISH_S3=no` for the normal engineering loop.

The builder may generate `manifests/files.sha256` for later transfer validation, but checksum verification and S3 publication are not mandatory parts of every fast smoke iteration.

For a stronger fast proof, relocate/copy the finished bundle to a **different absolute local path on the same online server** and run only from that relocated copy. This catches embedded build-path dependencies without requiring S3 or a second server.

Call this **offline emulation**. It does not prove that the host itself is air-gapped.

The fast proof must load portable archives from the relocated bundle even if the same images already exist in Podman; otherwise the smoke can accidentally validate only the host cache. `LOAD_BUNDLE_IMAGES=no` is an explicit escape hatch for a non-proof local iteration.

The generated samplesheet uses paths relative to the bundle root, and the run starts from that root. This keeps the bundle portable when moved to a different local directory or later transferred to an offline server.

Keep the offline profile's container registry prefix aligned with the `RepoTags` in the staged archives. Clearing the prefix can turn a fully qualified image into a different short name and make archive matching fail.

Keep pipeline parameter files scope-specific. The demo builder consumes `params_demo_offline.json`; deferred Sarek scripts consume `params_sarek_offline.json`, including Sarek's reference-selection settings. Do not let a demo smoke change overwrite the deferred Sarek contract.

The historical `scrnaseq` Docker runner accepts both legacy `.tgz` and current `.tar` image archives. The current canonical fast proof remains Podman-only; this compatibility change does not make Docker part of the smoke gate.

## Why `-offline` is not enough by itself

`nextflow -offline` is one control, not proof of physical network isolation.

The useful fast proof combines:

```text
bundle-local workflow/data/refs
bundle-local NXF_HOME/plugins
bundled container archives
NXF_OFFLINE=true
NXF_PLUGIN_AUTOINSTALL=false
explicit nextflow -offline
local executor
Podman task network none
```

A later real offline-server acceptance gate proves the stronger environment claim.

## S3 wording

S3 cache read means downloading existing approved assets during preparation.

S3 publication means uploading a completed bundle as a transfer/release proof.

They are separate actions. The fast engineering proof may read an approved preparation cache but keeps `PUBLISH_S3=no`; publication must be explicit and have a specific validation reason.

## Progressive acceptance

The useful progression is:

1. static checks;
2. same-online-server relocated-bundle offline emulation;
3. bounded S3 publish/readback when transfer evidence is needed;
4. real offline-server pipeline execution when environment acceptance is needed;
5. scale the same bundle contract to additional pipelines such as rnaseq/Sarek.

Do not make every change pay for every level.

Docker smoke, Sarek scale-up, real offline-server execution, and large upstream test datasets are separate work and should not delay the fast loop unless the current milestone explicitly owns them.
