# Historical Sarek 3.4.4 candidate

This is the selected historical starting point for Issue 17. It is not yet a
complete execution proof.

| Component | Value | Evidence | Status |
|---|---|---|---|
| Pipeline | `nf-core/sarek` | `offline/sarek/ENV` | historical |
| Revision | `3.4.4` | `offline/sarek/ENV` | historical |
| Nextflow | `24.04.4` | `offline/sarek/README.md` optional pin | historical |
| Java | unknown | not retained in historical material | pending |
| nf-core tools | unknown | not retained in historical material | pending |
| Plugins | disabled auto-install | `offline/sarek/ENV` | historical |
| Registry source | Nexus Quay proxy | `offline/sarek/test.config` | historical |
| Runtime destination | `nextflow/sarek` private ECR | Issue 17 | selected |
| Input/reference | historical S3 test path | `offline/sarek/test.config` | not reused |

The retained configuration disables remote institutional/test-data lookups,
sets `igenomes_ignore=true`, uses the Sarek offline profile, and skips
baserecalibration. Its historical container inventory records 22 Quay images,
including the FastQC smoke image below. Do not treat the inventory alone as a
full runnable tuple; Java, tools, plugins, params and image digests must be
captured before an execution proof.
