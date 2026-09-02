# Specification: Sarek Offline Happy Path

## Problem

Demonstrate that one selected nf-core Sarek execution can run from a declared
local or approved private cache without public Internet access.

## Scope

This foundation defines the future acceptance contract. It does not run Sarek,
download assets, pull images, or claim a successful pipeline execution.

## Required Before Execution

- Exact Sarek revision and Nextflow version.
- One approved non-production input and expected result location.
- Explicit pipeline asset cache path and container image cache path.
- One repo-owned Bash command that runs with `-offline`.
- A local/private dependency source for every required asset, plugin, and image.

## Acceptance

One command completes with exit code `0`, produces the named non-sensitive
result, and its log shows an offline execution without a public download.

## Must Not

- Use production or clinical data.
- Store credentials or environment-specific secrets in Git.
- Silently fetch missing public assets or images.
- Turn this focused proof into multi-pipeline automation.

## Stop Gates

Stop before execution when the Sarek revision, cache inventory, input, command,
or expected result is unknown; when a dependency needs public access; or when a
credential or production data would be required.
