# Specification: Sarek Offline Happy Path

## Problem

Demonstrate that one selected nf-core Sarek execution can run from a declared
local or approved private cache without public Internet access.

## Scope

This foundation defines the future acceptance contract. It does not run Sarek,
download assets, pull images, or claim a successful pipeline execution.

## Required Before Execution

- Exact Sarek revision `3.10.0` and Nextflow `>=25.10.4`.
- One approved non-production input and expected result location.
- Explicit prepared bundle path (`BUNDLE_ROOT`) and private ECR registry.
- One repo-owned Bash command (`offline/run_sarek_offline.sh`) that runs with
  `-offline` and Podman.
- A local/private dependency source for every required asset, plugin, reference,
  and image. The prepared bundle must include the Nextflow plugin cache.

## Acceptance

One command completes with exit code `0`, produces the named non-sensitive
result, and its log shows an offline execution without a public download.

## Bundle Contract

The online preparation command writes `workflow/`, `data/reads/`,
`data/refs/`, `offline/`, and `manifests/` below `BUNDLE_ROOT`. It records the
source image inventory and deterministic private-ECR mapping in
`manifests/image-map.tsv`; source references are rewritten in the prepared
workflow. `PUBLISH_ECR` and `PUBLISH_S3` are opt-in and are not run by local
validation.

The offline command requires a pre-populated Nextflow plugin cache and uses
`NXF_OFFLINE=true`, `NXF_PLUGIN_AUTOINSTALL=false`, and Podman. It fails closed
when the workflow, samplesheet, image map, or reference directory is absent.
The online preparation pins and installs the Sarek `3.10.0` plugin set:
`nf-core-utils@0.4.0`, `nf-fgbio@1.0.0`, `nf-prov@1.7.0`, and
`nf-schema@2.7.2`.

## Later AWS Proof (UNKNOWN_PENDING)

The authorized runtime test must use an EC2 instance with no public IP, IGW
egress, or NAT path. It must prove S3 gateway access, ECR API and DKR
interface-endpoint access, SSM Session Manager endpoints, private DNS, and
endpoint security-group ingress. From that instance, GitHub, quay.io, and
Docker Hub must fail while the prepared Sarek command succeeds.

## Must Not

- Use production or clinical data.
- Store credentials or environment-specific secrets in Git.
- Silently fetch missing public assets or images.
- Turn this focused proof into multi-pipeline automation.

## Stop Gates

Stop before execution when the Sarek revision, cache inventory, input, command,
or expected result is unknown; when a dependency needs public access; or when a
credential or production data would be required.
