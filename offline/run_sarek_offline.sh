#!/usr/bin/bash
set -euo pipefail

BUNDLE_ROOT="${BUNDLE_ROOT:?set BUNDLE_ROOT to the prepared local/S3 bundle}"
OUTPUT_DIR="${OUTPUT_DIR:-$PWD/results-sarek}"
WORK_DIR="${WORK_DIR:-$PWD/work-sarek}"
INPUT_SHEET="${INPUT_SHEET:-$BUNDLE_ROOT/data/reads/samplesheet.csv}"
ECR_REGISTRY="${ECR_REGISTRY:?set ECR_REGISTRY matching the prepared image map}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }
need nextflow
need podman
need jq
WORKFLOW_DIR="$BUNDLE_ROOT/workflow"
PARAMS_FILE="$BUNDLE_ROOT/offline/params_offline.json"
CONFIG_FILE="$BUNDLE_ROOT/offline/offline_test.conf"
[ -f "$WORKFLOW_DIR/main.nf" ] || { echo 'prepared workflow missing' >&2; exit 1; }
[ -f "$INPUT_SHEET" ] || { echo "input sheet missing: $INPUT_SHEET" >&2; exit 1; }
[ -f "$PARAMS_FILE" ] && [ -f "$CONFIG_FILE" ] || { echo 'offline config bundle missing' >&2; exit 1; }
[ -s "$BUNDLE_ROOT/manifests/image-map.tsv" ] || { echo 'image map missing' >&2; exit 1; }
grep -Fq "${ECR_REGISTRY}/" "$BUNDLE_ROOT/manifests/image-map.tsv" || {
  echo 'image map does not target the declared private ECR registry' >&2; exit 1;
}

export NXF_OFFLINE=true
export NXF_PLUGIN_AUTOINSTALL=false
export NXF_HOME="${NXF_HOME:-$BUNDLE_ROOT/offline/nextflow-home}"
mkdir -p "$OUTPUT_DIR" "$WORK_DIR"
echo "Running pinned Sarek bundle offline with Podman"
nextflow run "$WORKFLOW_DIR" \
  -profile podman \
  -params-file "$PARAMS_FILE" \
  -c "$CONFIG_FILE" \
  --input "$INPUT_SHEET" \
  --igenomes_base "$BUNDLE_ROOT/data/refs" \
  --outdir "$OUTPUT_DIR" \
  -work-dir "$WORK_DIR" \
  -offline \
  -resume \
  -with-report "$OUTPUT_DIR/execution-report.html"
