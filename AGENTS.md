# AGENTS.md

## Read First

1. `AGENTS.md`
2. `CONTEXT.md`
3. `SPEC.md`
4. `docs/validation-strategy.md`

Read those before changing scripts, caches, cloud access, pipeline behavior, or validation claims.

## Scope

This repository demonstrates how to prepare and validate portable Nextflow offline bundles.

Current canonical implementation milestone:

- Issue #12 / PR #14 — fast same-**online server** offline-emulation proof using the merged `offline/` bundle path.

Separate experimental lane:

- Issue #7 / PR #8 — standalone colleague-facing `docs/ops/**` Magic Script validation. Do not mix its implementation into the canonical `offline/` path unless a later reviewed decision explicitly promotes it.

Sarek is a later scale-up milestone. It is not the default next task for agents.

## Validation Model

Use the smallest proof that answers the current question:

1. static checks;
2. same-online-server offline emulation — default developer/PR proof;
3. bounded S3 publish/readback — occasional transfer/release proof;
4. real **offline server** execution — acceptance gate;
5. later pipeline scale-up such as rnaseq/Sarek.

Do not require S3 publication or a second server for every engineering iteration.

The fast offline-emulation proof is not the same as proving the host has no internet route. `nextflow -offline` alone is also not an air-gap guarantee. Preserve the full control set: bundle-local assets and plugin/cache state, `NXF_OFFLINE=true`, `NXF_PLUGIN_AUTOINSTALL=false`, explicit `-offline`, local executor, and Podman task network isolation where defined by the offline smoke profile.

## Rules

- Keep one problem, one command, one proof, and one result.
- Use `/usr/bin/bash` for shell work and run `bash -n` on changed scripts.
- Runtime proof must not depend on public pipeline assets, public test data, plugin downloads, or public container pulls.
- Keep generated bundles and heavy assets outside Git.
- S3 publication must remain explicit; use `PUBLISH_S3=no` for the normal fast validation loop unless the task specifically owns a transfer/release proof.
- Do not add credentials, real clinical data, or environment-specific secrets to Git.
- Preserve existing work. Do not create a framework, UI, CI system, IaC layer, CloudOS integration, or broad test suite for a focused proof.
- Respect active PR ownership. In particular, avoid `docs/ops/**` while PR #8 is active and avoid the Issue #12 request packet while PR #14 is active.
- Create temporary folders or worktrees only when needed. Keep durable work in Git; remove the exact lane-owned temporary path after a terminal task.

## Terminology

Use these terms in repository guidance:

- **online server** — prepares assets and may use approved public/private sources;
- **offline server** — consumes pre-staged assets without public internet dependency.

Same-server testing is called **offline emulation**; do not call it proof of a physically air-gapped server.

## Shared Guidance

Global rules in `~/.codex/AGENTS.md` apply. Reusable operating guidance is in `https://github.com/amitkarpe/agent-os`.
