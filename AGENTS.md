# AGENTS.md

## Read First

1. `AGENTS.md`
2. `CONTEXT.md`
3. `SPEC.md` before changing scripts, caches, cloud access, or pipeline behavior.

## Scope

This repository demonstrates offline Nextflow execution. Preserve the existing
`scrnaseq` scripts unless a task explicitly targets them. The next planned
scope is one Sarek offline happy path; it is not yet proven.

## Rules

- Keep one problem, one command, one proof, and one result.
- Use `/usr/bin/bash` for shell work and run `bash -n` on changed scripts.
- Do not download public pipeline assets or container images from an offline
  run. Cache source, pipeline revision, images, input, and output location must
  be named before execution.
- Do not add credentials, real clinical data, or environment-specific secrets
  to Git.
- Preserve existing work. Do not create a framework, UI, CI system, or broad
  test suite for a focused pipeline proof.
- Create temporary folders or worktrees only when needed. Keep durable work in
  Git; remove the exact lane-owned temporary path after a terminal task.

## Shared Guidance

Global rules in `~/.codex/AGENTS.md` apply. Reusable operating guidance is in
`https://github.com/amitkarpe/agent-os`.
