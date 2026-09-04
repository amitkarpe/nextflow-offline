#!/usr/bin/bash
set -euo pipefail

# Generic operator entrypoint. It creates a deterministic ECR manifest, then
# delegates copy/verification to the Skopeo mirror. It never creates ECR
# repositories: create_ecr.sh must be run separately and explicitly.

usage() {
  cat <<'EOF'
Usage: run_ecr_distribution.sh --pipeline {demo|bamtofastq|rnaseq|sarek} --source-list FILE [--execute]

Default mode creates and validates a plan only. --execute starts the Skopeo
registry-to-registry loop. The ECR repository nextflow/PIPELINE must already
exist. Results are written to --out-dir (or ~/.AGENTS-temp/nextflow/...).
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
pipeline=""
source_list=""
out_dir=""
execute=false
continue_on_error=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pipeline) pipeline="${2:?missing pipeline}"; shift 2 ;;
    --source-list) source_list="${2:?missing source list}"; shift 2 ;;
    --out-dir) out_dir="${2:?missing output directory}"; shift 2 ;;
    --execute) execute=true; shift ;;
    --continue-on-error) continue_on_error=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$pipeline" in demo|bamtofastq|rnaseq|sarek) ;; *) usage >&2; exit 2 ;; esac
[ -f "$source_list" ] || { echo "source list missing: $source_list" >&2; exit 2; }
: "${AWS_PROFILE:?set AWS_PROFILE}"
: "${AWS_REGION:?set AWS_REGION}"

out_dir="${out_dir:-${HOME}/.AGENTS-temp/nextflow/${pipeline}-ecr-distribution-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$out_dir"
manifest="$out_dir/image-manifest.tsv"
ECR_REPOSITORY="nextflow/$pipeline" SOURCE_LIST="$source_list" OUTPUT_MANIFEST="$manifest" \
  "$SCRIPT_DIR/generate_sarek_ecr_manifest.sh" > "$out_dir/generate.log" 2>&1

mirror_args=(--image-manifest "$manifest" --repository "nextflow/$pipeline" --out-dir "$out_dir/mirror")
if [ "$execute" = true ]; then
  [ "$continue_on_error" = true ] && mirror_args+=(--continue-on-error)
else
  mirror_args+=(--dry-run)
fi
"$SCRIPT_DIR/mirror_sarek_ecr_images.sh" "${mirror_args[@]}" > "$out_dir/mirror.log" 2>&1
cp "$out_dir/mirror/RESULT.md" "$out_dir/RESULT.md"
printf 'PIPELINE=%s\nECR_REPOSITORY=nextflow/%s\nEXECUTE=%s\n' "$pipeline" "$pipeline" "$execute" >> "$out_dir/RESULT.md"
if [ "$execute" = true ]; then
  printf 'RESULT=SUCCESS\n' >> "$out_dir/RESULT.md"
  printf 'RESULT=SUCCESS\n' > "$out_dir/.done"
else
  printf 'IMAGE_COPY=NOT_RUN\nRESULT=SUCCESS\n' >> "$out_dir/RESULT.md"
fi
cat "$out_dir/RESULT.md"
