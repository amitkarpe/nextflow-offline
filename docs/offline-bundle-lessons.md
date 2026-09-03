# Offline bundle lessons

This note records the fast path for future small Nextflow smoke tests.

## The important distinction

The pipeline source can be small while its container images are large. The
`nf-core/demo` 1.0.2 proof used three images totalling about 620 MiB. Image
import, not processing the tiny reads, was the slow part.

The upstream demo test profile is not an offline input profile. Its
`conf/test.config` points `params.input` at a public samplesheet:

<https://raw.githubusercontent.com/nf-core/demo/master/conf/test.config>

That samplesheet points at four more public FASTQ URLs:

<https://raw.githubusercontent.com/nf-core/test-datasets/viralrecon/samplesheet/samplesheet_test_illumina_amplicon.csv>

Using that profile unchanged would make the runtime depend on public network
access. If upstream parity is needed, stage the samplesheet and every FASTQ
locally first. For the normal smoke check, use one approved tiny paired-input
fixture instead.

## What went wrong previously

1. The first preparation started from the public pipeline path before the
   existing private cache was inventoried.
2. A public revision/image path caused multi-gigabyte image export and storage
   pressure even though the workflow itself was small.
3. The upstream test profile was treated as if it described local test data;
   it actually contains a remote input URL.
4. Resource settings were copied manually into a generated config instead of
   using a repo-owned `offline_smoke` profile.
5. An offline consumer initially selected the host's Nextflow framework
   version. Pin `NXF_VER` to the framework bundled with the bundle.

## Fast standard

Use `offline/build_offline_bundle.sh` with:

- `SOURCE_MODE=s3-cache`;
- the pinned workflow/revision;
- the existing tiny local fixture;
- Podman as the only supported smoke engine;
- `offline_smoke` plus the Podman profile;
- `NXF_OFFLINE=true`, `NXF_PLUGIN_AUTOINSTALL=false`, and `-offline`;
- an empty bundle output directory outside Git.

The builder may generate `manifests/files.sha256` for later transfer
validation, but checksum verification is not part of the fast smoke gate.

The fast proof must load the portable archives from the bundle even if the
same images already exist in Podman; otherwise the smoke can accidentally
validate only the host cache. `LOAD_BUNDLE_IMAGES=no` is an explicit escape
hatch for a non-proof local iteration. Keep the image cache keyed by pipeline
and revision so repeat runs do not rediscover assets.

The generated samplesheet uses paths relative to the bundle root, and the
builder runs from that root. This keeps the bundle portable when transferred
to a different local directory.

Keep the offline profile's container registry prefix aligned with the
`RepoTags` in the staged archives. Clearing the prefix can turn a fully
qualified image into a different short name and make archive matching fail.

Keep pipeline parameter files scope-specific. The demo builder consumes
`params_demo_offline.json`; the deferred Sarek scripts consume
`params_sarek_offline.json`, including Sarek's reference-selection settings.
Do not let a demo smoke change overwrite the deferred Sarek contract.

The historical `scrnaseq` Docker runner accepts both legacy `.tgz` and current
`.tar` image archives. New Phase 1 proof remains Podman-only; this compatibility
change does not make Docker part of the smoke gate.

## S3 wording

S3 cache read means downloading existing approved assets for preparation.
S3 publication means uploading the completed bundle for an offline consumer.
They are separate actions. The fast proof reads the cache; publication remains
explicit and must name its exact destination.

## Future acceptance

The minimum useful proof is:

1. the cached builder completes;
2. the Podman offline smoke completes with exit 0;
3. the bundle contains workflow, plugin/cache, local input, references, image
   archives, manifests, and the generated offline config/profile;
4. no runtime input or image source is a public URL.

Docker smoke, Sarek scale-up, offline EC2 execution, and large upstream test
datasets are separate work and should not delay this fast path.
