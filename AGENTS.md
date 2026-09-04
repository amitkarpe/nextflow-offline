# AGENTS.md

## Read First

1. `AGENTS.md`
2. `CONTEXT.md`
3. `SPEC.md`
4. `docs/validation-strategy.md`

## Scope

This repository proves a small, repeatable Nextflow offline-emulation contract:

```text
descriptor discovery -> ECR manifest -> Skopeo -> ECR override -> relocated Podman runtime
```

`offline/pipeline_e2e.tsv` is the pipeline registry. Discovery output is the
source of truth; `offline/reference/` is comparison evidence only. `docs/ops/**`
is a separate colleague-facing Magic Script and must not be silently merged
into the canonical path.

## Rules

- Use `/usr/bin/bash`; run `bash -n` on changed Bash scripts.
- Keep one problem, one command, one proof, and one result.
- Runtime must use staged workflow/data/plugins and preloaded private images;
  require bundle-local `NXF_HOME`, `NXF_OFFLINE=true`, disabled plugin
  autoinstall, explicit `-offline`, and Podman `--network none --pull=never`.
- Call same-server proof **offline emulation**, never physical air-gap proof.
- Keep heavy assets, AWS account values, and credentials outside Git.
- Keep S3 publication and ECR mirroring explicit. Do not add a framework, UI,
  CI system, IaC, CloudOS, or a duplicate pipeline architecture.
- Sarek uses its fail-closed preview active-path gate; do not start Sarek
  runtime/mirroring unless a task explicitly authorizes it.

## Shared Guidance

Global rules in `~/.codex/AGENTS.md` apply. Reusable guidance is in
`https://github.com/amitkarpe/agent-os`.
