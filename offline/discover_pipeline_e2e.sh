#!/usr/bin/bash
set -euo pipefail

# Online preparation/discovery only. Stages a pinned workflow and approved tiny
# data from private S3, installs bundle-local plugins, and derives the source
# container inventory from static inspect. Historical lists are comparison-only
# references. It never invokes Podman/Docker or schedules a Nextflow task.

usage() {
  cat <<'EOF'
Usage: discover_pipeline_e2e.sh --pipeline {demo|bamtofastq|rnaseq} --bundle-root DIR
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OPS_ENV="$REPO_ROOT/scripts/ops/ENV"
if [ -f "$OPS_ENV" ]; then
  set -a
  source "$OPS_ENV"
  set +a
fi
pipeline_key=""
bundle_root=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pipeline) pipeline_key="${2:?missing pipeline}"; shift 2 ;;
    --bundle-root) bundle_root="${2:?missing bundle root}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$pipeline_key" in demo|bamtofastq|rnaseq) ;; *) usage >&2; exit 2 ;; esac
: "${AWS_PROFILE:?set AWS_PROFILE}"
: "${AWS_REGION:?set AWS_REGION}"
: "${S3_ROOT:?set S3_ROOT or scripts/ops/ENV}"
case "$S3_ROOT" in s3://*) ;; *) echo "S3_ROOT must be an s3:// URI" >&2; exit 2 ;; esac
[ -n "$bundle_root" ] || { usage >&2; exit 2; }

result_written=false
on_exit() {
  local rc=$?
  if [ "$result_written" = false ]; then
    mkdir -p "$bundle_root"
    printf 'PIPELINE_KEY=%s\nEXIT_CODE=%s\nRESULT=FAILED\n' "$pipeline_key" "$rc" > "$bundle_root/RESULT.md"
    printf 'RESULT=FAILED\n' > "$bundle_root/.failed"
  fi
}
trap on_exit EXIT

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }
need aws
need nextflow
need jq

descriptor="$REPO_ROOT/offline/pipeline_e2e.tsv"
row="$(awk -F '\t' -v key="$pipeline_key" 'NR > 1 && $1 == key {print; found=1} END {if (!found) exit 1}' "$descriptor")" || {
  echo "pipeline descriptor missing: $pipeline_key" >&2
  exit 2
}
IFS=$'\t' read -r _key pipeline revision workflow_s3_key data_s3_key reference_source_list fixture <<< "$row"
reference_source_list="$REPO_ROOT/$reference_source_list"
[ -f "$reference_source_list" ] || { echo "reference source list missing: $reference_source_list" >&2; exit 2; }
workflow_s3_uri="${S3_ROOT%/}/${workflow_s3_key}"
if [ "$data_s3_key" != - ]; then
  data_s3_uri="${S3_ROOT%/}/${data_s3_key}"
else
  data_s3_uri=-
fi

mkdir -p "$bundle_root"
if [ -n "$(find "$bundle_root" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  echo "bundle root must be empty: $bundle_root" >&2
  exit 2
fi
mkdir -p "$bundle_root"/{workflow,data,plugins/nextflow-home,manifests,offline}
aws s3 sync "${workflow_s3_uri%/}/" "$bundle_root/workflow/" --only-show-errors
[ -f "$bundle_root/workflow/main.nf" ] || { echo "staged workflow has no main.nf" >&2; exit 1; }
if [ "$data_s3_uri" != - ]; then
  aws s3 sync "${data_s3_uri%/}/" "$bundle_root/data/" --only-show-errors
fi

# inspect evaluates required schema parameters even though it does not launch a
# task. Build only local placeholder inputs here; the runtime phase replaces
# them with the validated tiny fixture and never uses these discovery files.
discovery_input="$bundle_root/offline/discovery-input.csv"
case "$fixture" in
  paired-fastq)
    [ -f "$bundle_root/data/tiny_R1.fastq.gz" ] && [ -f "$bundle_root/data/tiny_R2.fastq.gz" ] || {
      echo "paired discovery FASTQ files are missing" >&2
      exit 1
    }
    printf 'sample,fastq_1,fastq_2\nDISCOVERY,%s,%s\n' \
      "$bundle_root/data/tiny_R1.fastq.gz" "$bundle_root/data/tiny_R2.fastq.gz" > "$discovery_input"
    ;;
  paired-fastq-reference)
    [ -f "$bundle_root/data/tiny_R1.fastq.gz" ] && [ -f "$bundle_root/data/tiny_R2.fastq.gz" ] || {
      echo "RNA-seq discovery FASTQ files are missing" >&2
      exit 1
    }
    printf 'sample,fastq_1,fastq_2,strandedness\nDISCOVERY,%s,%s,unstranded\n' \
      "$bundle_root/data/tiny_R1.fastq.gz" "$bundle_root/data/tiny_R2.fastq.gz" > "$discovery_input"
    ;;
  generated-bam)
    : > "$bundle_root/data/discovery-placeholder.bam"
    printf 'sample_id,mapped,file_type\nDISCOVERY,%s,bam\n' \
      "$bundle_root/data/discovery-placeholder.bam" > "$discovery_input"
    ;;
  *) echo "unsupported discovery fixture: $fixture" >&2; exit 2 ;;
esac
discovery_config="$bundle_root/offline/discovery.config"
{
  printf '%s\n' 'params {'
  printf "  input = '%s'\n" "$discovery_input"
  printf "  outdir = '%s'\n" "$bundle_root/offline/discovery-output"
  printf '%s\n' '  genome = null'
  printf '%s\n' '  igenomes_ignore = true'
  printf '%s\n' '  validate_params = false'
  printf '%s\n' '  custom_config_base = null'
  printf '%s\n' '  custom_config_version = null'
  printf '%s\n' '  pipelines_testdata_base_path = null'
  printf '%s\n' '  modules_testdata_base_path = null'
  if [ "$fixture" = paired-fastq-reference ]; then
    printf "  fasta = '%s'\n" "$bundle_root/data/genome.fasta"
    printf "  gtf = '%s'\n" "$bundle_root/data/genes_with_empty_tid.gtf.gz"
  fi
  printf '%s\n' '}'
  printf '%s\n' 'trace.enabled = false'
  printf '%s\n' 'report.enabled = false'
  printf '%s\n' 'timeline.enabled = false'
  printf '%s\n' 'dag.enabled = false'
} > "$discovery_config"

mapfile -t plugins < <(grep -RhoE "id '[^']+'" "$bundle_root/workflow" 2>/dev/null | sed -E "s/^id '([^']+)'$/\1/" | sort -u || true)
printf '%s\n' "${plugins[@]}" > "$bundle_root/manifests/plugins.txt"
for plugin in "${plugins[@]}"; do
  [ -n "$plugin" ] || continue
  NXF_HOME="$bundle_root/plugins/nextflow-home" NXF_PLUGIN_AUTOINSTALL=false \
    nextflow plugin install "$plugin"
done

inspect_args=(nextflow inspect "$bundle_root/workflow" -profile podman -c "$discovery_config" -format json \
  --input "$discovery_input" --outdir "$bundle_root/offline/discovery-output")
if [ "$fixture" = paired-fastq-reference ]; then
  inspect_args+=(--fasta "$bundle_root/data/genome.fasta" --gtf "$bundle_root/data/genes_with_empty_tid.gtf.gz")
fi
NXF_HOME="$bundle_root/plugins/nextflow-home" \
NXF_OFFLINE=true \
NXF_PLUGIN_AUTOINSTALL=false \
  timeout 180 "${inspect_args[@]}" > "$bundle_root/manifests/inspect.json"
jq -er '.processes | type == "array" and length > 0' "$bundle_root/manifests/inspect.json" >/dev/null

# The inspected containers are the source of truth for this pipeline path.
# Reference inventories are retained solely to show whether cached knowledge is
# incomplete or stale; a reference mismatch never changes the generated manifest.
discovered_source_list="$bundle_root/manifests/discovered-source-images.txt"
jq -r '.processes[] | .container? | select(type == "string" and length > 0)' \
  "$bundle_root/manifests/inspect.json" | sort -u > "$discovered_source_list"
[ -s "$discovered_source_list" ] || { echo "inspect returned no source containers" >&2; exit 1; }
reference_source_list_clean="$bundle_root/manifests/reference-source-images.txt"
awk 'NF && $1 !~ /^#/ {print}' "$reference_source_list" | sort -u > "$reference_source_list_clean"
reference_comparison="$bundle_root/manifests/reference-image-comparison.tsv"
{
  printf 'source_image\tcomparison\n'
  comm -23 "$discovered_source_list" "$reference_source_list_clean" | \
    awk '{print $0 "\tdiscovered-not-in-reference"}'
  comm -13 "$discovered_source_list" "$reference_source_list_clean" | \
    awk '{print $0 "\treference-not-in-discovery"}'
} > "$reference_comparison"

ECR_REPOSITORY="nextflow/$pipeline_key" \
SOURCE_LIST="$discovered_source_list" \
OUTPUT_MANIFEST="$bundle_root/manifests/ecr-images.tsv" \
  "$REPO_ROOT/scripts/ops/generate_ecr_manifest.sh" \
  > "$bundle_root/manifests/generate-ecr-manifest.log"
"$REPO_ROOT/scripts/ops/generate_pipeline_ecr_overrides.sh" \
  --inspect-json "$bundle_root/manifests/inspect.json" \
  --image-manifest "$bundle_root/manifests/ecr-images.tsv" \
  --out-dir "$bundle_root/offline" \
  > "$bundle_root/manifests/generate-ecr-overrides.log"

static_images="$(jq -r '.processes[] | .container? | select(type == "string" and length > 0)' "$bundle_root/manifests/inspect.json" | sort -u | wc -l)"
registries="$(jq -r '.processes[] | .container? | select(type == "string" and length > 0)' "$bundle_root/manifests/inspect.json" | awk -F/ '{print $1}' | sort -u | paste -sd, -)"
reference_missing="$(awk -F '\t' 'NR > 1 && $2 == "discovered-not-in-reference" {count++} END {print count + 0}' "$reference_comparison")"
reference_stale="$(awk -F '\t' 'NR > 1 && $2 == "reference-not-in-discovery" {count++} END {print count + 0}' "$reference_comparison")"
{
  printf 'PIPELINE_KEY=%s\nPIPELINE=%s\nREVISION=%s\n' "$pipeline_key" "$pipeline" "$revision"
  printf 'WORKFLOW_SOURCE=%s\nDATA_SOURCE=%s\nFIXTURE=%s\n' "$workflow_s3_uri" "$data_s3_uri" "$fixture"
  printf 'STATIC_IMAGE_COUNT=%s\nSTATIC_IMAGE_REGISTRIES=%s\n' "$static_images" "$registries"
  printf 'REFERENCE_DISCOVERED_MISSING=%s\nREFERENCE_STALE=%s\n' "$reference_missing" "$reference_stale"
  printf 'ECR_OVERRIDE_MAPPING=PASS\n'
  printf 'PODMAN_ACTIONS=NONE_BY_SCRIPT\nTASK_EXECUTION=NONE_BY_SCRIPT\nRESULT=SUCCESS\n'
} > "$bundle_root/RESULT.md"

# Hash the completed source bundle before relocation. The copied runtime bundle
# validates this inventory without relying on a hash it generated after copy.
(
  cd "$bundle_root"
  find . -type f \
    ! -path './manifests/files.sha256' \
    ! -path './manifests/source-checksums.log' \
    ! -path './.done' \
    ! -path './.failed' -print0 |
    sort -z | xargs -0 sha256sum
) > "$bundle_root/manifests/files.sha256"
( cd "$bundle_root" && sha256sum -c manifests/files.sha256 ) \
  > "$bundle_root/manifests/source-checksums.log"
printf 'RESULT=SUCCESS\n' > "$bundle_root/.done"
result_written=true
cat "$bundle_root/RESULT.md"
