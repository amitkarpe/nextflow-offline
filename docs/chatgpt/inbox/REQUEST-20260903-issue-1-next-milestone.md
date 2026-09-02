# ChatGPT review request: select the next repository milestone

## Protocol

Follow the public [ChatGPT/Codex collaboration protocol](https://github.com/amitkarpe/agent-os/blob/main/kb/playbooks/integrations/chatgpt-codex-collaboration-protocol.md).

## Repository and immutable evidence

- Repository: [amitkarpe/nextflow-offline](https://github.com/amitkarpe/nextflow-offline)
- Accepted milestone commit: `d01e394c26382e8d6960199fbbbd1f39cfa7b763` on `main`
- Accepted implementation: [PR #3](https://github.com/amitkarpe/nextflow-offline/pull/3)
- Current specification: [SPEC.md at accepted commit](https://github.com/amitkarpe/nextflow-offline/blob/d01e394c26382e8d6960199fbbbd1f39cfa7b763/SPEC.md)
- Current issue: [Issue #1](https://github.com/amitkarpe/nextflow-offline/issues/1)

## Verified current truth

The repository contains a legacy `scrnaseq` demonstration plus a bounded Sarek
offline scaffold. The accepted milestone pins nf-core/sarek `3.10.0` and
Nextflow `>=25.10.4`, adds repo-owned preparation and offline Podman commands,
records deterministic private-ECR image mapping, and disables remote
config/test-data/plugin auto-install behavior. Bash syntax, JSON parsing, and
Git diff checks pass. No AWS calls, ECR/S3 publishing, EC2 launch, endpoint
changes, image pulls, or Sarek runtime execution have been performed.

Issue #1 remains open because the endpoint-isolated two-EC2 runtime proof is
`UNKNOWN_PENDING`. There are no other open Issues or PRs. The repository is
public; keep all response content public-safe.

## Exact question

Review the immutable repository evidence and existing open Issue. Choose exactly
one small, bounded next objective. Return:

1. one recommended Issue scope (continue Issue #1 only if it still owns the
   work; otherwise explain why a new Issue is justified);
2. one cohesive implementation Draft PR plan targeting `main`;
3. rejected alternatives;
4. acceptance criteria and validation/evidence;
5. explicit no-go gates and deferred work.

Do not implement anything, create GitHub records, or assume live AWS state.
Keep the recommendation within the existing Sarek/offline architecture and
state any prerequisite approval for AWS or external-service mutation.

## Publication safety

Use only the public links and sanitized facts above. Do not include credentials,
account IDs, ARNs, private endpoints, hostnames, IPs, customer data, raw cloud
payloads, or unverified runtime claims.
