# ChatGPT implementation packet — Issue #15

Repository: `amitkarpe/nextflow-offline`
Base: `main`
Branch: `docs/issue-15-align-direction`
Issue: https://github.com/amitkarpe/nextflow-offline/issues/15

## Goal

Align repository guidance with the current project truth after the Phase 1 magic-bundle work.

This is documentation only. ChatGPT owns the implementation.

## Current direction

Use one validation progression:

```text
Level 0 — static checks
Level 1 — fast same-online-server offline emulation (default)
Level 2 — bounded S3 publish/readback transfer proof (occasional)
Level 3 — real offline-server acceptance gate
Level 4 — pipeline scale-up such as rnaseq/Sarek
```

Level 1 must use a relocated fresh bundle path, bundled container archives, bundle-local plugin/cache state, `NXF_OFFLINE=true`, `NXF_PLUGIN_AUTOINSTALL=false`, explicit Nextflow `-offline`, local executor, and Podman task network isolation.

`nextflow -offline` alone must not be described as an air-gap guarantee.

## Allowed files

- `AGENTS.md`
- `CONTEXT.md`
- `SPEC.md`
- `README.md`
- `docs/offline-bundle-lessons.md` only if needed
- new `docs/validation-strategy.md`
- this request packet

## Conflict boundary

Do not modify:

- `docs/ops/**` — owned by Issue #7 / PR #8;
- `offline/**` or `scripts/**` — runtime implementation;
- Issue #12 request packet — owned by PR #14.

## Required outcomes

1. Remove stale statements that Issue #5/Phase 1 is active or that Sarek is the immediate next task.
2. Make Issue #12 / PR #14 the current canonical implementation milestone.
3. Keep PR #8 / Issue #7 explicitly separate as the standalone colleague-facing Magic Script validation lane.
4. Make same-server offline emulation the default developer/PR test.
5. Make S3 publication optional for normal development and an occasional release/transfer proof.
6. Retain a real offline-server proof as a later acceptance gate.
7. Put Sarek after the bundle/validation contract is proven.
8. Keep terminology to **online server** and **offline server**.
9. Preserve KISS and avoid adding code, CI, IaC, CloudOS, ECR strategy, or production SOP.

## Acceptance

- root guidance files agree with each other;
- `docs/validation-strategy.md` clearly states what each validation level proves and does not prove;
- no code/runtime paths change;
- no `docs/ops/**` paths change;
- no secrets/private infrastructure identifiers are added.
