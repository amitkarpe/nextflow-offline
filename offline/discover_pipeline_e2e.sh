#!/usr/bin/bash
set -euo pipefail

# Online preparation/discovery only. Stages a pinned workflow and approved tiny
# data from private S3, installs bundle-local plugins, inspects containers, and
# proves every static container has an immutable ECR mapping. It never invokes
# Podman/Docker or schedules a Nextflow task.

usage() {
  cat <<'EOF'
Usage: discover_pipeline_e2e.sh --pipeline {demo|bamtofastq|rnaseq} --bundle-root DIR
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
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
IFS=$'\t' read -r _key pipeline revision workflow_s3_uri data_s3_uri source_list fixture <<< "$row"
source_list="$REPO_ROOT/$source_list"
[ -f "$source_list" ] || { echo "source list missing: $source_list" >&2; exit 2; }

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

mapfile -t plugins < <(grep -RhoE "id '[^']+'" "$bundle_root/workflow" 2>/dev/null | sed -E "s/^id '([^']+)'$/\1/" | sort -u || true)
printf '%s\n' "${plugins[@]}" > "$bundle_root/manifests/plugins.txt"
for plugin in "${plugins[@]}"; do
  [ -n "$plugin" ] || continue
  NXF_HOME="$bundle_root/plugins/nextflow-home" NXF_PLUGIN_AUTOINSTALL=false \
    nextflow plugin install "$plugin"
done

NXF_HOME="$bundle_root/plugins/nextflow-home" \
NXF_OFFLINE=true \
NXF_PLUGIN_AUTOINSTALL=false \
  timeout 180 nextflow inspect "$bundle_root/workflow" -profile podman -format json \
  > "$bundle_root/manifests/inspect.json"
jq -er '.processes | type == "array" and length > 0' "$bundle_root/manifests/inspect.json" >/dev/null

ECR_REPOSITORY="nextflow/$pipeline_key" \
SOURCE_LIST="$source_list" \
OUTPUT_MANIFEST="$bundle_root/manifests/ecr-images.tsv" \
  "$REPO_ROOT/scripts/ops/generate_sarek_ecr_manifest.sh" \
  > "$bundle_root/manifests/generate-ecr-manifest.log"
"$REPO_ROOT/scripts/ops/generate_pipeline_ecr_overrides.sh" \
  --inspect-json "$bundle_root/manifests/inspect.json" \
  --image-manifest "$bundle_root/manifests/ecr-images.tsv" \
  --out-dir "$bundle_root/offline" \
  > "$bundle_root/manifests/generate-ecr-overrides.log"

static_images="$(jq -r '.processes[] | .container? | select(type == "string" and length > 0)' "$bundle_root/manifests/inspect.json" | sort -u | wc -l)"
registries="$(jq -r '.processes[] | .container? | select(type == "string" and length > 0)' "$bundle_root/manifests/inspect.json" | awk -F/ '{print $1}' | sort -u | paste -sd, -)"
{
  printf 'PIPELINE_KEY=%s\nPIPELINE=%s\nREVISION=%s\n' "$pipeline_key" "$pipeline" "$revision"
  printf 'WORKFLOW_SOURCE=%s\nDATA_SOURCE=%s\nFIXTURE=%s\n' "$workflow_s3_uri" "$data_s3_uri" "$fixture"
  printf 'STATIC_IMAGE_COUNT=%s\nSTATIC_IMAGE_REGISTRIES=%s\n' "$static_images" "$registries"
  printf 'ECR_OVERRIDE_MAPPING=PASS\n'
  printf 'PODMAN_ACTIONS=NONE_BY_SCRIPT\nTASK_EXECUTION=NONE_BY_SCRIPT\nRESULT=SUCCESS\n'
} > "$bundle_root/RESULT.md"
printf 'RESULT=SUCCESS\n' > "$bundle_root/.done"
result_written=true
cat "$bundle_root/RESULT.md"
