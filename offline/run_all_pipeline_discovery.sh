#!/usr/bin/bash
set -euo pipefail

# Launch isolated online discovery for the three approved pipelines in parallel.
# All shared state is avoided: each pipeline receives its own bundle root,
# plugin cache, inspect output, manifest, config, console log, and marker.

usage() {
  cat <<'EOF'
Usage: run_all_pipeline_discovery.sh [--pipelines CSV] --out-dir DIR
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pipelines="demo,bamtofastq,rnaseq"
out_dir=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pipelines) pipelines="${2:?missing CSV}"; shift 2 ;;
    --out-dir) out_dir="${2:?missing output directory}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
: "${AWS_PROFILE:?set AWS_PROFILE}"
: "${AWS_REGION:?set AWS_REGION}"
[ -n "$out_dir" ] || { usage >&2; exit 2; }
mkdir -p "$out_dir"
status="$out_dir/status.tsv"
printf 'pipeline\trun_rc\tresult\n' > "$status"

declare -A pids=()
IFS=',' read -r -a selected <<< "$pipelines"
for pipeline in "${selected[@]}"; do
  case "$pipeline" in demo|bamtofastq|rnaseq) ;; *) echo "invalid pipeline: $pipeline" >&2; exit 2 ;; esac
  pipeline_dir="$out_dir/$pipeline"
  mkdir -p "$pipeline_dir"
  printf 'START pipeline=%s\n' "$pipeline"
  /usr/bin/bash "$SCRIPT_DIR/discover_pipeline_e2e.sh" \
    --pipeline "$pipeline" \
    --bundle-root "$pipeline_dir/bundle" \
    > "$pipeline_dir/console.log" 2>&1 &
  pids["$pipeline"]=$!
done

overall_rc=0
for pipeline in "${selected[@]}"; do
  set +e
  wait "${pids[$pipeline]}"
  run_rc=$?
  set -e
  result="FAILED"
  if [ -f "$out_dir/$pipeline/bundle/RESULT.md" ]; then
    result="$(awk -F= '/^RESULT=/{value=$2} END{print value}' "$out_dir/$pipeline/bundle/RESULT.md")"
  fi
  printf '%s\t%s\t%s\n' "$pipeline" "$run_rc" "$result" >> "$status"
  printf 'DONE pipeline=%s rc=%s result=%s\n' "$pipeline" "$run_rc" "$result"
  if [ "$run_rc" -ne 0 ] || [ "$result" != SUCCESS ]; then
    overall_rc=1
  fi
done

{
  printf 'MODE=online-discovery\n'
  printf 'PODMAN_ACTIONS=NONE_BY_SCRIPT\n'
  printf 'TASK_EXECUTION=NONE_BY_SCRIPT\n'
  printf 'STATUS=%s\n' "$status"
  if [ "$overall_rc" -eq 0 ]; then
    printf 'RESULT=SUCCESS\n'
  else
    printf 'RESULT=BLOCKED\n'
  fi
} > "$out_dir/RESULT.md"
if [ "$overall_rc" -eq 0 ]; then
  printf 'RESULT=SUCCESS\n' > "$out_dir/.done"
else
  printf 'RESULT=BLOCKED\n' > "$out_dir/.failed"
fi
cat "$out_dir/RESULT.md"
exit "$overall_rc"
