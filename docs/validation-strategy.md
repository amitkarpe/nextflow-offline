# Validation strategy

Use the cheapest proof that answers the current engineering question. Escalate only when the milestone needs stronger evidence.

## Decision table

| Level | Where | Typical frequency | Required proof | What it proves | What it does not prove |
| --- | --- | --- | --- | --- | --- |
| 0 — Static | repository / online server | every relevant change | shell/config/JSON/TSV checks | files are syntactically/coherently valid | bundle/runtime behavior |
| 1 — Offline emulation | same **online server** | default PR/developer loop | build, relocate, load bundle archives, strict offline run | bundle is relocatable and runtime can use staged local assets | host has no internet route |
| 2 — S3 transfer | online server + bounded S3 prefix | occasional release/transfer change | explicit publish + readback/inventory | bundle survives the S3 handoff contract | offline server can run it |
| 3 — Offline-server acceptance | real **offline server** | milestone/release gate | transferred bundle completes pipeline without public runtime dependency | environment + bundle work together offline | every larger pipeline is already supported |
| 4 — Pipeline scale-up | proven validation path | after core contract is stable | repeat contract for rnaseq/Sarek/etc. | shared design handles larger pipeline requirements | production readiness by itself |

## Level 0 — static checks

Run focused checks appropriate to the changed files. Examples:

```bash
/usr/bin/bash -n path/to/changed-script.sh
jq empty path/to/changed.json
```

Use TSV/config parsers or focused repository checks when relevant. Do not turn a small proof into a broad CI framework.

## Level 1 — default fast offline-emulation proof

This is the normal engineering validation loop.

```text
ONLINE SERVER
  -> build fresh bundle
  -> PUBLISH_S3=no
  -> relocate/copy bundle to a different fresh absolute path
  -> load only relocated containers/*.tar
  -> use relocated workflow/data/refs/plugins
  -> NXF_OFFLINE=true
  -> NXF_PLUGIN_AUTOINSTALL=false
  -> explicit nextflow -offline
  -> local executor
  -> Podman task network none
  -> PASS
```

### Required controls

```text
NXF_OFFLINE=true
NXF_PLUGIN_AUTOINSTALL=false
validate_params=false
custom_config_base=null
custom_config_version=null
pipelines_testdata_base_path=null
```

Also require:

- bundle-local `NXF_HOME`;
- no public input URL at runtime;
- no plugin download at runtime;
- no public container pull at runtime;
- container archives loaded from the relocated bundle;
- repo-owned offline smoke profile with local executor and Podman task network isolation.

### Why relocate on the same server?

A second absolute path catches portability bugs such as embedded online-build paths while keeping the test fast and repeatable.

### Important claim boundary

Call this **offline emulation**.

Do not say the server is air-gapped merely because:

```text
nextflow -offline
```

was used. That flag is only one part of the runtime contract. Level 1 proves self-contained bundle behavior under enforced offline controls, not physical network isolation of the host.

## Level 2 — bounded S3 transfer/release proof

S3 publication is opt-in and should not be repeated for ordinary code/doc iterations.

Use it when validating publication, transfer layout, or a release candidate:

```text
PUBLISH_S3=yes
PUBLISH_PREFIX=s3://<approved-bucket>/<bounded-prefix>/
```

Expected evidence:

- destination was explicitly selected;
- existing objects are not overwritten unintentionally;
- upload exits zero;
- required bundle paths can be read back;
- release metadata records the exact destination;
- no credentials/private payloads are committed.

The repository already completed one Phase 1 demo S3 publish/readback proof. Future repetition should have a specific reason.

## Level 3 — real offline-server acceptance gate

Use when the milestone needs actual environmental proof.

```text
prepared bundle
  -> approved transfer path
  -> OFFLINE SERVER
  -> local bundle assets
  -> Podman
  -> strict offline controls
  -> pipeline PASS
```

A real offline-server proof may use approved private infrastructure to receive the bundle before execution. The pipeline runtime itself must not require public GitHub, nf-core test-data URLs, plugin downloads, or public registries.

A failed `curl` is not sufficient acceptance evidence. The pipeline itself must complete from the prepared bundle.

## Level 4 — pipeline scale-up

Once Levels 1–3 establish the contract, use the same architecture for additional pipelines.

For rnaseq/Sarek, add only pipeline-specific requirements proven necessary, for example:

- FASTA/GTF or other required references;
- more container archives;
- disk-space checks;
- resumable preparation;
- stronger completeness checks;
- longer build/test times.

Do not replace the shared bundle contract merely because the pipeline is larger.

## Current lanes

### Canonical implementation

Issue #12 / PR #14 owns the current Level 1 fast same-online-server relocated-bundle proof for the merged `offline/` implementation.

### Standalone colleague-facing experiment

Issue #7 / PR #8 owns `docs/ops/**` and validates a separate standalone Magic Script handoff. Keep that work isolated until its runtime evidence is reviewed.

### Documentation direction

Issue #15 / PR #16 owns root documentation and this validation model. It must not modify runtime code or `docs/ops/**`.

## Recommended progression

```text
change
  -> Level 0
  -> Level 1
  -> merge normal engineering work

only when transfer/release evidence is needed
  -> Level 2

only when real environment acceptance is needed
  -> Level 3

then scale to rnaseq/Sarek
  -> Level 4
```

This keeps feedback fast without weakening the final offline acceptance standard.
