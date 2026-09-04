# REQUEST - Review Issue 19 active-path inventory implementation

Repository: `amitkarpe/nextflow-offline`  
Issue: #19  
PR: #18  
Implementation commit: `4353f7dd8de8508a5ce758cabe61c7ecf2e405f2`

## Scope

Implement exactly the Issue 19 milestone inside the existing Sarek candidate
helper. No image pull, save, load, Podman invocation, task command, S3, cloud,
registry substitution, or pipeline revision change is permitted.

## Implementation

`offline/inspect_sarek_candidate.sh` now:

1. records static `process -> container` mappings from `nextflow inspect`;
2. runs the exact local Sarek fixture with `nextflow -offline -preview` and
   writes a run-specific Mermaid DAG;
3. derives called, fully-qualified process names from that DAG;
4. requires one unique, non-empty static container mapping for every called
   process; and
5. gates only the resulting active image set.

The helper fails closed with `QUAY_ONLY=UNKNOWN` if preview/DAG/mapping is not
available. It returns `QUAY_ONLY=FAIL` only when a called process maps to a
non-Quay image.

## Validation evidence

The exact Sarek 3.5.1 synthetic fixture completed Nextflow preview in 1m23s:

```text
PREVIEW_RC=0
PREVIEW_MODE=true
TASK_EXECUTION=NONE_OBSERVED
PODMAN_ACTIONS=NONE_OBSERVED
ACTIVE_PROCESSES=49
UNRESOLVED_PROCESSES=0
ACTIVE_IMAGE_COUNT=23
ACTIVE_IMAGE_REGISTRIES=community.wave.seqera.io,quay.io
QUAY_ONLY=FAIL
OFFLINE_SAFE=false
RESULT=BLOCKED
```

The active DAG maps these selected process names to non-Quay references:

```text
NFCORE_SAREK:SAREK:CONVERT_FASTQ_INPUT:CAT_FASTQ
  -> community.wave.seqera.io/library/coreutils:9.5--ae99c88a9b28c264

NFCORE_SAREK:SAREK:FASTQ_ALIGN_BWAMEM_MEM2_DRAGMAP_SENTIEON:SENTIEON_BWAMEM
  -> community.wave.seqera.io/library/sentieon:202308.03--59589f002351c221
```

Also passed:

```text
BASH_SYNTAX=PASS
DIFF_CHECK=PASS
```

## Review question

Review the immutable implementation commit below. Is the DAG parsing/mapping
fail-closed and correctly scoped to Issue 19? Confirm whether the active
non-Quay result is supported by the preview artifact. Do not propose a registry
substitution, image action, alternate pipeline revision, or architecture work.

Implementation URL: https://github.com/amitkarpe/nextflow-offline/commit/4353f7dd8de8508a5ce758cabe61c7ecf2e405f2

## Required response

Record the completed review in one new standalone GitHub Issue with:

```text
RESULT=SUCCESS|BLOCKED|CHANGES_REQUESTED
ONE_NEXT_MILESTONE=<one sentence>
```
