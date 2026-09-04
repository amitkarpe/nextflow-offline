#!/usr/bin/bash
set -euo pipefail

# Adapt the established inspect.json -> image-manifest -> Nextflow override
# contract to one immutable ECR repository per pipeline.  Unlike the old EC2
# helper, this performs no Docker, Podman, AWS, or workflow action.

usage() {
  cat <<'EOF'
Usage: generate_pipeline_ecr_overrides.sh --inspect-json FILE --image-manifest FILE --out-dir DIR

Generate process-containers.tsv, unresolved-containers.tsv, and
nextflow-ecr-containers.config.  Fails closed when an inspected container has
no exact source_image entry in the ECR manifest.
EOF
}

inspect_json=""
image_manifest=""
out_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --inspect-json) inspect_json="${2:?missing inspect JSON}"; shift 2 ;;
    --image-manifest) image_manifest="${2:?missing image manifest}"; shift 2 ;;
    --out-dir) out_dir="${2:?missing output directory}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -f "$inspect_json" ] || { echo "inspect JSON missing: $inspect_json" >&2; exit 2; }
[ -f "$image_manifest" ] || { echo "image manifest missing: $image_manifest" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "missing command: jq" >&2; exit 1; }

mkdir -p "$out_dir"
jq -er '.processes | type == "array" and length > 0' "$inspect_json" >/dev/null
jq -r '.processes[] | select(.name | type == "string" and length > 0) | select(.container | type == "string" and length > 0) | [.name, .container] | @tsv' \
  "$inspect_json" | sort -u > "$out_dir/process-containers.tsv"
[ -s "$out_dir/process-containers.tsv" ] || { echo "no process/container pairs in inspect JSON" >&2; exit 1; }

awk_rc=0
awk -F '\t' -v unresolved="$out_dir/unresolved-containers.tsv" -v mapped="$out_dir/mapped-containers.tsv" '
  NR == FNR {
    if (FNR == 1) {
      if ($0 != "source_image\trepository_name\ttag\tecr_image") exit 2
      next
    }
    if (NF != 4 || $1 == "" || $4 == "") exit 2
    ecr[$1] = $4
    next
  }
  {
    if (NF != 2 || $1 == "" || $2 == "") exit 2
    if (!($2 in ecr)) {
      print $1 "\t" $2 "\tmissing-manifest-entry" > unresolved
      failed = 1
      next
    }
    name = $1
    gsub(/\\/, "\\\\", name)
    gsub(/\047/, "\\\\\047", name)
    print name "\t" $2 "\t" ecr[$2] > mapped
  }
  END { exit failed ? 1 : 0 }
' "$image_manifest" "$out_dir/process-containers.tsv" || awk_rc=$?

[ -f "$out_dir/unresolved-containers.tsv" ] || : > "$out_dir/unresolved-containers.tsv"
if [ -s "$out_dir/unresolved-containers.tsv" ]; then
  echo "inspected containers are absent from the ECR manifest" >&2
  exit 1
fi
[ "$awk_rc" -eq 0 ] || { echo "invalid image manifest or process mapping" >&2; exit 1; }
[ -s "$out_dir/mapped-containers.tsv" ] || { echo "no mapped containers" >&2; exit 1; }

config_tmp="$out_dir/nextflow-ecr-containers.config.tmp"
{
  printf '%s\n' '// Generated from inspect.json plus immutable ECR manifest.'
  printf '%s\n' 'process {'
  printf '%s\n' "  executor = 'local'"
  printf '%s\n' '  cpus = 2'
  printf '%s\n' "  memory = '4.GB'"
  while IFS=$'\t' read -r process_name _source_image ecr_image; do
    printf "  withName: '%s' { container = '%s' }\n" "$process_name" "$ecr_image"
  done < "$out_dir/mapped-containers.tsv"
  printf '%s\n' '}'
  printf '%s\n' 'podman.enabled = true'
  printf '%s\n' "podman.runOptions = '--network none'"
} > "$config_tmp"
mv "$config_tmp" "$out_dir/nextflow-ecr-containers.config"
printf 'PROCESSES=%s\n' "$(wc -l < "$out_dir/mapped-containers.tsv")"
printf 'UNRESOLVED=0\n'
printf 'RESULT=SUCCESS\n'
