# REQUEST — Issue #20 KISS generic pipeline onboarding + repository cleanup

## Work only here

- Issue: #20
- Branch: `feature/issue-20-kiss-generic-cleanup`
- PR: the Draft PR created from this branch
- Parent dependency: PR #18

Do not create a replacement Issue, branch, or PR.

Until PR #18 merges, this is a stacked PR. After #18 merges, retarget this PR to `main` before implementation continues.

## Goal

Make the repository smaller and make the **PR #18 generic flow** the single canonical way to onboard future Nextflow pipelines for offline execution.

KISS target:

```text
one pipeline registry
one prepare/discovery path
one ECR distribution path
one offline runtime path
one short README
```

Do not build a framework.

## Canonical architecture to preserve

```text
Nextflow inspect/preview
-> discovered image inventory
-> image-manifest.tsv
-> skopeo copy -> private ECR
-> generated Nextflow ECR overrides
-> S3 workflow/data/plugins + ECR containers
-> Podman offline runtime
```

Runtime invariants:

```text
NXF_OFFLINE=true
NXF_PLUGIN_AUTOINSTALL=false
validate_params=false
custom_config_base=null
custom_config_version=null
pipelines_testdata_base_path=null
podman --network none --pull=never
```

Object-store staging may lose POSIX executable mode, so the canonical runtime must restore executable mode for bundle-local `workflow/bin/*` before Nextflow starts.

## First action — inventory before deletion

Before editing/deleting, post a compact table in the PR:

```text
CURRENT FILE | PURPOSE | KEEP / MERGE / DELETE | CANONICAL REPLACEMENT
```

Inspect at least:

- root docs;
- `offline/**`;
- `scripts/ops/**`;
- `docs/ops/**`.

Do not preserve a duplicate implementation merely because it is old. Git history is the archive.

## Implementation order

### 1. Finish one generic descriptor contract

Prefer the existing `offline/pipeline_e2e.tsv` unless a rename materially simplifies the interface.

A future pipeline should mainly require one descriptor/config change, not a copied shell program.

Keep only fields the generic flow actually needs, e.g.:

```text
key
pipeline
revision
workflow_s3_key
data/fixture key
optional params/adapter id
```

No AWS account IDs, private ECR URLs, private S3 roots, credentials, or generated manifests in Git.

### 2. Reduce durable commands

Prefer improving existing generic scripts rather than adding wrappers.

Desired operator shape:

```text
prepare/discover <pipeline>
distribute-images <pipeline>
run-offline <pipeline>
```

Exact filenames are secondary. Fewer scripts is better.

### 3. Remove superseded paths only after replacement proof

Candidates to evaluate include:

```text
offline/build_offline_bundle.sh
offline/test_bundle_offline_local.sh
offline/prepare_sarek_offline_test.sh
offline/run_sarek_offline.sh
historical image lists that no longer drive logic
redundant run-all/watch wrappers
duplicated docs/ops implementation scripts
```

Delete rather than create `archive/` folders.

If a candidate still owns a unique useful capability, first move that capability into the canonical generic path or keep it and state the blocker.

### 4. Shorten and correct documentation

Update current truth in:

- `README.md`
- `AGENTS.md`
- `CONTEXT.md`
- `SPEC.md`
- `docs/validation-strategy.md` only if needed

Remove stale Issue #12 / PR #14 as-current wording.

README must stay short and answer only:

1. what this repo does;
2. how a pipeline is registered/onboarded;
3. online preparation;
4. offline runtime;
5. status semantics.

### 5. Preserve truthful status semantics

Use only:

```text
SUCCESS
BLOCKED
FAILED
```

A blocked compatibility gate must never create a success marker.

Sarek remains a compatibility task. Do not mirror/substitute Wave images or run Sarek as part of this cleanup.

## Validation

Keep it bounded:

```text
bash -n changed-shell-files
TSV/JSON/config validation
public-repo hygiene scan
existing demo/bamtofastq/rnaseq descriptor mapping PASS
one smallest demo relocated E2E regression PASS
one fake/new descriptor reaches generic plan/discovery validation without a new shell script
```

Do not re-run every expensive lane unless a changed shared path requires it.

## Required final evidence

```text
ONE_CANONICAL_FLOW=true
PIPELINE_SPECIFIC_SHELL_COPIES=0
GENERIC_DESCRIPTOR_ONBOARDING=PASS
DEMO_REGRESSION=PASS
PUBLIC_REPO_HYGIENE=PASS
STALE_DOCS_REMOVED=PASS
DUPLICATE_IMPLEMENTATION_REDUCED=PASS
```

Also include the final deletion/replacement map.

## Non-goals

Do not add:

- plugin/framework architecture;
- CloudOS integration;
- CodeBuild/CodePipeline;
- Terraform/CDK/CloudFormation;
- GUI;
- broad CI/test framework;
- production/clinical data;
- automatic inference for arbitrary pipeline inputs/references;
- Sarek registry substitution/runtime work.

## Stop rule

If cleanup starts increasing script count or abstraction count, stop and simplify.

**Core principle: delete duplication, improve the proven generic path, and stop.**
