#!/usr/bin/bash
set -euo pipefail

# Read-only terminal view for the parallel discovery runner.  It is intended
# for an operator tmux pane and exits when the aggregate marker is written.

usage() {
  cat <<'EOF'
Usage: watch_pipeline_e2e_discovery.sh --root DIR [--interval SECONDS]
EOF
}

root=""
interval=10
while [ "$#" -gt 0 ]; do
  case "$1" in
    --root) root="${2:?missing root}"; shift 2 ;;
    --interval) interval="${2:?missing interval}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -d "$root" ] || { echo "root not found: $root" >&2; exit 2; }
case "$interval" in *[!0-9]*|'') echo "interval must be a positive integer" >&2; exit 2 ;; esac
[ "$interval" -gt 0 ] || { echo "interval must be positive" >&2; exit 2; }

while :; do
  clear
  printf 'Nextflow pipeline discovery progress\n'
  date
  printf 'Evidence: %s\n\n' "$root"
  printf '%-12s %-10s %-10s %-10s %-10s\n' pipeline workflow plugins inspect override
  for pipeline in demo bamtofastq rnaseq; do
    bundle="$root/$pipeline/bundle"
    workflow=0
    plugins=0
    [ -d "$bundle/workflow" ] && workflow="$(find "$bundle/workflow" -type f | wc -l)"
    [ -d "$bundle/plugins" ] && plugins="$(find "$bundle/plugins" -type f | wc -l)"
    inspect=no
    override=no
    [ -f "$bundle/manifests/inspect.json" ] && inspect=yes
    [ -f "$bundle/offline/nextflow-ecr-containers.config" ] && override=yes
    printf '%-12s %-10s %-10s %-10s %-10s\n' "$pipeline" "$workflow" "$plugins" "$inspect" "$override"
    if [ -f "$bundle/RESULT.md" ]; then
      awk -F= '/^(RESULT|STATIC_IMAGE_COUNT|ECR_OVERRIDE_MAPPING)=/{print "  " $0}' "$bundle/RESULT.md"
    fi
  done
  if [ -f "$root/.done" ] || [ -f "$root/.failed" ]; then
    printf '\n--- aggregate result ---\n'
    cat "$root/RESULT.md"
    exit 0
  fi
  sleep "$interval"
done
