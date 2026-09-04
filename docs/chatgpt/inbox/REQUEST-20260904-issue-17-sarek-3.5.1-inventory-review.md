# REQUEST — Review the Sarek 3.5.1 candidate inventory gate

Protocol: https://gist.github.com/amitkarpe/c8d29ad89cafe3ba178fcae29de3c238

Repository: `amitkarpe/nextflow-offline`  
Issue: #17  
PR: #18  
Implementation commit: `4acc1327a923a53d6b25014d6441de1f823975a2`

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

The first two attempts corrected real helper defects: selecting a nested
`main.nf`, then using `subject` instead of the Sarek-required `patient`
samplesheet column. The final bounded invocation reached `nextflow inspect` but
did not complete within 180 seconds; therefore no image inventory is claimed.

```text
PIPELINE=nf-core/sarek
REVISION=3.5.1
INSPECT=TIMEOUT_AFTER_180_SECONDS
RESULT=BLOCKED
```

No S3, ECR, Docker, Skopeo, image pull/save/load, task execution, clinical
data, or infrastructure action occurred.

## Review question

Review the actual implementation diff at the immutable implementation commit:

https://github.com/amitkarpe/nextflow-offline/commit/4acc1327a923a53d6b25014d6441de1f823975a2

Is the helper safely scoped and is the bounded `BLOCKED` result truthful?
Choose exactly one smallest next milestone. Do not recommend a registry,
revision, container, cloud, or architecture substitution.

## Required response

Record the completed review in one new standalone GitHub Issue. State:

```text
RESULT=SUCCESS|BLOCKED|CHANGES_REQUESTED
ONE_NEXT_MILESTONE=<one sentence>
```
