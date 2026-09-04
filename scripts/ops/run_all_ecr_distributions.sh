#!/usr/bin/bash
set -euo pipefail

# Online preparation only. This sequential driver creates missing approved ECR
# repositories, then delegates source-to-ECR transfer and config-digest
# verification to the generic Skopeo runner. It never invokes Podman, Docker,
# or Nextflow. A queue callback is opt-in: the operator must provide a verified
# CODEX_QUEUE_THREAD instead of the script guessing a Codex session.

usage() {
  cat <<'EOF'
Usage: run_all_ecr_distributions.sh [--pipelines CSV] [--execute] [--out-dir DIR]

Defaults to demo,bamtofastq,rnaseq and plan-only mode. --execute creates only
missing nextflow/<pipeline> ECR repositories, then mirrors the retained
historical inventories using Skopeo.
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
pipelines="demo,bamtofastq,rnaseq"
execute=false
out_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pipelines) pipelines="${2:?missing CSV}"; shift 2 ;;
    --execute) execute=true; shift ;;
    --out-dir) out_dir="${2:?missing output directory}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

: "${AWS_PROFILE:?set AWS_PROFILE}"
: "${AWS_REGION:?set AWS_REGION}"
if [ "$execute" = true ]; then
  : "${ECR_TTL:?set ECR_TTL as DD-MM-YY before --execute}"
fi
out_dir="${out_dir:-${HOME}/.AGENTS-temp/nextflow/ecr-distribution-all-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$out_dir"
status="$out_dir/status.tsv"
printf 'pipeline\tsource_list\trepository\trun_rc\tresult\n' > "$status"

notify_completion() {
  local result="$1"
  local message="Nextflow ECR distribution ${result}; evidence: ${out_dir}"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send 'Nextflow ECR distribution' "$message" >/dev/null 2>&1 || true
  fi
  printf '\a' >&2
  if [ -n "${CODEX_QUEUE_THREAD:-}" ]; then
    codex queue --thread "$CODEX_QUEUE_THREAD" --message "$message" > "$out_dir/codex-queue.log" 2>&1 || true
  fi
}

overall_rc=0
IFS=',' read -r -a selected <<< "$pipelines"
for pipeline in "${selected[@]}"; do
  case "$pipeline" in demo|bamtofastq|rnaseq) ;; *) echo "invalid pipeline: $pipeline" >&2; exit 2 ;; esac
  source_list="$REPO_ROOT/offline/${pipeline}_source_images_historical.txt"
  [ -f "$source_list" ] || { echo "source list missing: $source_list" >&2; exit 2; }
  awk 'NF && $1 !~ /^quay\.io\// { exit 1 }' "$source_list" || {
    echo "non-Quay source not approved by this historical-input runner: $source_list" >&2
    exit 2
  }
  pipeline_dir="$out_dir/$pipeline"
  mkdir -p "$pipeline_dir"
  if [ "$execute" = true ]; then
    if ! "$SCRIPT_DIR/create_ecr.sh" "$pipeline" > "$pipeline_dir/ecr-repository-uri.txt" 2> "$pipeline_dir/ecr-repository.err"; then
      printf '%s\t%s\tnextflow/%s\t1\tFAILED_CREATE_REPOSITORY\n' "$pipeline" "$source_list" "$pipeline" >> "$status"
      overall_rc=1
      continue
    fi
  fi
  run_args=(--pipeline "$pipeline" --source-list "$source_list" --out-dir "$pipeline_dir" --continue-on-error)
  if [ "$execute" = true ]; then
    run_args+=(--execute)
  fi
  set +e
  "$SCRIPT_DIR/run_ecr_distribution.sh" "${run_args[@]}" > "$pipeline_dir/console.log" 2>&1
  run_rc=$?
  set -e
  result="FAILED"
  if [ -f "$pipeline_dir/RESULT.md" ]; then
    result="$(awk -F= '/^RESULT=/{value=$2} END{print value}' "$pipeline_dir/RESULT.md")"
  fi
  printf '%s\t%s\tnextflow/%s\t%s\t%s\n' "$pipeline" "$source_list" "$pipeline" "$run_rc" "$result" >> "$status"
  if [ "$run_rc" -ne 0 ] || [ "$result" != SUCCESS ]; then
    overall_rc=1
  fi
done

{
  if [ "$execute" = true ]; then
    printf 'MODE=execute\n'
  else
    printf 'MODE=dry_run\n'
  fi
  printf 'COPY_ENGINE=skopeo\n'
  printf 'PODMAN_ACTIONS=NONE_BY_SCRIPT\n'
  printf 'WORKFLOW_EXECUTION=NONE_BY_SCRIPT\n'
  printf 'STATUS=%s\n' "$status"
  if [ "$overall_rc" -eq 0 ]; then
    printf 'RESULT=SUCCESS\n'
  else
    printf 'RESULT=FAILED\n'
  fi
} > "$out_dir/RESULT.md"
if [ "$overall_rc" -eq 0 ]; then
  printf 'RESULT=SUCCESS\n' > "$out_dir/.done"
else
  printf 'RESULT=FAILED\n' > "$out_dir/.failed"
fi
notify_completion "$(awk -F= '/^RESULT=/{print $2}' "$out_dir/RESULT.md")"
cat "$out_dir/RESULT.md"
exit "$overall_rc"
