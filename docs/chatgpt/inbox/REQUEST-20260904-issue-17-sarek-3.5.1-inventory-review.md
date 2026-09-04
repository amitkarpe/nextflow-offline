# REQUEST — Review the Sarek 3.5.1 candidate inventory gate

Protocol: https://gist.github.com/amitkarpe/c8d29ad89cafe3ba178fcae29de3c238

Repository: `amitkarpe/nextflow-offline`  
Issue: #17  
PR: #18  
Implementation commit: `0f789c0e3977e5fc0642bc8427f155018a027650`

## Approved scope

Amit approved `nf-core/sarek` `3.5.1` as the replacement candidate after the
previous `3.10.0` inventory gate was blocked by its unavailable
`nf-core-utils@0.4.0` plugin.

The implementation adds one no-image helper:

```text
offline/inspect_sarek_candidate.sh
```

It downloads only the pinned workflow source/configuration, creates a tiny
synthetic non-clinical Sarek samplesheet/reference fixture, stages the declared
plugins, runs `nextflow inspect`, and records an image-registry gate. It must
not pull, save, load, or run containers.

## Validation performed

```text
BASH_SYNTAX=PASS
JSON_VALIDATION=PASS
DIFF_CHECK=PASS
PODMAN_ACTIONS=NONE_OBSERVED
TASK_EXECUTION=NONE_OBSERVED
```

The helper initially selected a nested `main.nf`, used `subject` instead of the
Sarek-required `patient` samplesheet column, and omitted the documented
`skip_tools=baserecalibrator` setting needed when no BQSR resource is supplied.
Those defects are fixed. The bounded run then completed without image or task
actions and emitted a static process inventory:

```text
PIPELINE=nf-core/sarek
REVISION=3.5.1
STATIC_IMAGE_COUNT=23
STATIC_IMAGE_REGISTRIES=community.wave.seqera.io,quay.io
STATIC_QUAY_ONLY=FAIL
QUAY_ONLY=UNKNOWN
OFFLINE_SAFE=UNKNOWN_PENDING
RESULT=BLOCKED
```

This correction is intentional: Nextflow documents `inspect` as analysis of
process settings without execution. Sarek has conditional processes, so this
static list cannot truthfully establish the images required by the selected
`tools=strelka`, `step=mapping` route. The helper now reports that limitation
instead of declaring the candidate unsafe from optional-process references.

No S3, ECR, Docker, Skopeo, image pull/save/load, task execution, clinical
data, or infrastructure action occurred.

## Review question

Review the actual implementation diff at the immutable implementation commit:

https://github.com/amitkarpe/nextflow-offline/commit/0f789c0e3977e5fc0642bc8427f155018a027650

Is the helper safely scoped and is its `UNKNOWN_PENDING` conclusion truthful?
Choose exactly one smallest next milestone to prove the selected active path's
image set without pulling images or executing container tasks. Do not recommend
a registry, revision, container, cloud, or architecture substitution.

## Required response

Record the completed review in one new standalone GitHub Issue. State:

```text
RESULT=SUCCESS|BLOCKED|CHANGES_REQUESTED
ONE_NEXT_MILESTONE=<one sentence>
```
