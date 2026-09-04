# Validation strategy

Use the cheapest proof that answers the change.

| Level | Proof | Use |
| --- | --- | --- |
| 0 | Bash, TSV, JSON, and diff checks | every relevant change |
| 1 | descriptor `--plan` | onboarding and descriptor edits |
| 2 | online discovery plus optional ECR distribution | asset/image changes |
| 3 | relocated Podman offline emulation | runtime-contract changes |
| 4 | bounded S3 readback or real offline-server run | explicit transfer/acceptance milestone |

Level 3 requires a prepared bundle at a different absolute path, a fresh
Podman store, private ECR preload before Nextflow starts, bundle-local
`NXF_HOME`, `NXF_OFFLINE=true`, disabled plugin autoinstall, explicit
`nextflow -offline`, and task `--network none --pull=never`.

It proves offline emulation, not physical host isolation. Do not repeat ECR
mirroring, S3 transfer, or real-server tests unless the change needs that
stronger evidence.
