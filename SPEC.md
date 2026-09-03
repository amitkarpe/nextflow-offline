# Specification: portable Nextflow offline bundle and validation model

## Goal

Prepare one complete, portable Nextflow bundle on an **online server** and validate that it can run without public runtime dependencies.

The default proof target remains the existing `nf-core/demo` revision `1.0.2` path with Podman. The repository uses progressive validation so normal engineering changes do not repeatedly pay the cost of S3 transfer or a second server.

## Terminology

- **online server** — prepares assets and may use approved public/private sources;
- **offline server** — consumes pre-staged assets without public internet dependency;
- **offline emulation** — runs a relocated bundle on the same online server with strict offline controls. It is a fast engineering proof, not evidence that the host itself has no internet route.

## Authorization

Online preparation may read approved private S3 caches and, when explicitly selected, public pipeline/plugin/container/test-data sources needed to prepare a pinned bundle.

This authorization does not extend to the offline-emulation/runtime portion of the proof. Runtime must use staged bundle assets only.

No credentials, clinical data, production data, or environment-specific secrets may enter Git or the portable bundle.

## Canonical Interface

```text
offline/build_offline_bundle.sh
offline/bundle.env
offline/params_demo_offline.json
offline/offline_test.conf
```

Run the builder from the online server with an empty `BUNDLE_ROOT` outside the repository.

The default `SOURCE_MODE=s3-cache` uses the existing demo workflow/image cache and tiny approved fixture. `SOURCE_MODE=public` is a preparation fallback for a new pinned revision and must stage any remote test inputs locally before runtime validation.

S3 publication is opt-in:

```text
PUBLISH_S3=no     # default fast engineering loop
PUBLISH_S3=yes    # explicit transfer/release proof only
```

When publication is enabled, use an exact bounded `PUBLISH_PREFIX`. The canonical builder records the destination and rejects an existing object by default.

## Standalone Colleague-Facing Interface

The repository also contains a merged standalone handoff under:

```text
docs/ops/
  magic-online.sh
  magic-offline.sh
  validate-bundle.sh
  magic.env.example
  pipelines.tsv
  testdata.tsv
```

PR #8 validated its `nf-core/demo` 1.0.2 path with a relocated same-online-server offline-emulation proof. That proof established Skopeo archive creation, preserved image names/tags, isolated Podman archive loading, bundle-local Nextflow state, explicit `-offline`, task network isolation, and successful FASTQC/SEQTK_TRIM/MULTIQC execution.

The `docs/ops/**` path remains a standalone colleague-facing handoff. It is not a replacement for the canonical `offline/**` implementation, and the two implementations must not be silently merged.

The PR #8 proof did **not** validate S3 publication for the standalone handoff. Treat that optional behavior as a separate transfer/release concern.

## Bundle Contract

```text
<bundle>/
  workflow/                 pinned pipeline source
  configs/                  centralised configs, when supplied by the pipeline
  containers/*.tar          portable container archives
  plugins/nextflow-home/    bundle-local Nextflow/plugin cache state
  data/reads/               staged tiny FASTQ and samplesheet
  data/refs/                staged local references
  offline/                  params, custom smoke profile, smoke output
  manifests/                image, plugin, version, release, and SHA-256 data
  README.txt                transfer/load/run instructions
```

Generated/heavy bundle content stays outside Git.

## Required Runtime Controls

The fast proof and later offline-server proof must preserve the useful offline controls learned during Phase 1:

```text
NXF_OFFLINE=true
NXF_PLUGIN_AUTOINSTALL=false
validate_params=false
custom_config_base=null
custom_config_version=null
pipelines_testdata_base_path=null
```

Also require for the default Podman proof:

- explicit Nextflow `-offline`;
- bundle-local `NXF_HOME` / plugin cache;
- local executor;
- local bundled workflow/config/data/refs;
- container images satisfied from bundle archives;
- Podman task network isolation through the repo-owned offline smoke profile.

`nextflow -offline` alone is not an air-gap guarantee and must not be presented as one.

## Validation Levels

### Level 0 — static checks

Use for every relevant change:

- `/usr/bin/bash -n` on changed shell scripts;
- JSON/config/TSV parsing or equivalent focused static validation;
- repository diff/whitespace checks where useful.

### Level 1 — fast same-online-server offline emulation

This is the **default developer/PR proof**.

```text
online server
  -> build fresh bundle with PUBLISH_S3=no
  -> relocate/copy bundle to a different fresh local path
  -> load container archives from relocated bundle
  -> use relocated bundle's workflow/data/refs/plugin cache
  -> NXF_OFFLINE=true
  -> NXF_PLUGIN_AUTOINSTALL=false
  -> nextflow -offline
  -> Podman task network none
  -> pipeline PASS
```

Level 1 proves bundle relocatability and self-contained runtime behavior under enforced offline controls. It does not prove physical network isolation of the host.

The standalone `docs/ops/**` demo path has completed this proof. The current canonical implementation milestone remains **Issue #12 / PR #14** for the merged `offline/**` path.

### Level 2 — bounded S3 transfer/release proof

Use occasionally, not for every iteration.

A successful Level 2 proof demonstrates that an exact bundle can be published to a bounded S3 prefix and read back with the required bundle layout intact.

Phase 1 already proved this once for the canonical demo bundle. `offline/verify_published_bundle.sh <exact-s3-prefix>` provides non-destructive readback/inventory validation.

A Level 1 success does not automatically validate another implementation's S3 publication behavior.

### Level 3 — real offline-server acceptance gate

Use when a release/milestone needs actual environment evidence.

Transfer the prepared bundle to an **offline server** through an approved path, then run the pipeline without public runtime dependency. The current bundle proof should run from local bundle assets; S3 may be used as a controlled transfer mechanism before execution when explicitly authorized.

Do not claim Level 3 success from a failed `curl` or from Nextflow flags alone. The actual pipeline must complete from the prepared assets.

### Level 4 — pipeline scale-up

After the bundle/validation contract is stable, apply the same model to additional pipelines such as rnaseq and Sarek.

Sarek-specific work may add scale concerns such as many images, larger references, disk-space checks, resumable preparation, and stronger completeness checks. It must not create a separate bundle architecture unless a reviewed blocker proves the shared contract insufficient.

## Acceptance for the Core Bundle Contract

- pipeline revision and all source/config/plugin/image/input assets needed by the selected proof are present below the bundle root;
- generated samplesheet/input paths remain valid after relocating the bundle;
- required container archives are loadable and preserve the image names needed by Nextflow;
- bundle-local plugin/cache state is usable with plugin autoinstall disabled;
- runtime uses the full offline control set above;
- Level 1 relocated-bundle smoke exits zero for the default demo path;
- SHA-256 inventory is generated for optional transfer validation;
- optional S3 publication is explicit and bounded;
- no heavy generated content or secrets enter Git.

## Implementation Boundaries

Two implementations now coexist intentionally:

- `offline/**` — canonical implementation, currently owned by Issue #12 / PR #14 for its fast relocated-bundle proof;
- `docs/ops/**` — merged standalone colleague-facing Magic Script handoff, validated for the demo Level 1 proof.

Do not silently combine the two implementations. Share a proven improvement only through a focused issue/PR with explicit ownership and validation.

## No-Go and Deferred Work

Stop and report rather than silently changing architecture if:

- the selected pipeline requires a public runtime dependency;
- required plugins/images cannot be satisfied from the prepared bundle;
- relocatability depends on the original online-server absolute path;
- the fast proof requires Docker instead of the agreed Podman path;
- a focused validation task starts requiring CloudOS, CodeBuild/CodePipeline, IaC, ECR optimization, production data, or a generic multi-pipeline framework.

Existing `scrnaseq` scripts remain historical. Deferred Sarek scripts continue to use `offline/params_sarek_offline.json`; do not reuse the demo parameter file.

See `docs/validation-strategy.md` for the concise operator/engineer decision guide.
