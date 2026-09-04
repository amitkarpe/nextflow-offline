#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
AWS_PROFILE="${AWS_PROFILE:-dev}"
S3_ROOT="${S3_ROOT:-}"
PIPELINE="${PIPELINE:-demo}"
REVISION="${REVISION:-1.0.2}"
BUNDLE_CHANNEL="${BUNDLE_CHANNEL:-magic-v1}"
OFFLINE_ROOT="${OFFLINE_ROOT:-/tmp/nextflow-offline-offline}"
RUN_PIPELINE="${RUN_PIPELINE:-no}"
SKIP_S3_PULL="${SKIP_S3_PULL:-no}"
BUNDLE_NAME="${PIPELINE}-${REVISION}"
BUNDLE_ROOT="${BUNDLE_ROOT:-$OFFLINE_ROOT/$BUNDLE_NAME}"
S3_BUNDLE_URI="${S3_BUNDLE_URI:-}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }
for tool in podman nextflow sha256sum; do need "$tool"; done

NEXTFLOW_BIN="$(command -v nextflow)"
if grep -q '^export NXF_HOME=' "$NEXTFLOW_BIN" 2>/dev/null; then
  tools_root="$(sed -n 's/^export NEXTFLOW_TOOLS_ROOT=//p' "$NEXTFLOW_BIN")"
  if [[ -n "$tools_root" && -x "$tools_root/nextflow/nextflow" ]]; then
    export JAVA_HOME="$tools_root/java"
    export PATH="$JAVA_HOME/bin:$PATH"
    NEXTFLOW_BIN="$tools_root/nextflow/nextflow"
  fi
fi
nf() { "$NEXTFLOW_BIN" "$@"; }
mkdir -p "$BUNDLE_ROOT"
if [[ "$SKIP_S3_PULL" != yes ]]; then
  need aws
  [[ -n "$S3_BUNDLE_URI" || -n "$S3_ROOT" ]] || {
    echo "set S3_BUNDLE_URI or S3_ROOT when SKIP_S3_PULL is not yes" >&2
    exit 2
  }
  S3_BUNDLE_URI="${S3_BUNDLE_URI:-${S3_ROOT%/}/bundles/${BUNDLE_NAME}/${BUNDLE_CHANNEL}}"
  aws --profile "$AWS_PROFILE" s3 sync "$S3_BUNDLE_URI/" "$BUNDLE_ROOT/" --only-show-errors
fi
"$SCRIPT_DIR/validate-bundle.sh" "$BUNDLE_ROOT"

PODMAN_ARCHIVES_LOADED=0
while IFS=$'\t' read -r source mode artifact; do
  [[ "$source" == source || -z "$source" ]] && continue
  [[ "$mode" == archive ]] || continue
  podman load -i "$BUNDLE_ROOT/$artifact"
  podman image exists "$source" || {
    echo "loaded archive did not preserve image reference: $source" >&2
    exit 1
  }
  PODMAN_ARCHIVES_LOADED=$((PODMAN_ARCHIVES_LOADED + 1))
done < "$BUNDLE_ROOT/manifests/images.tsv"
printf 'PODMAN_ARCHIVES_LOADED=%s\n' "$PODMAN_ARCHIVES_LOADED"

if [[ -d "$BUNDLE_ROOT/workflow/bin" ]]; then chmod +x -c "$BUNDLE_ROOT/workflow/bin/"* 2>/dev/null || true; fi
export NXF_HOME="$BUNDLE_ROOT/plugins/nextflow-home"
export NXF_OFFLINE=true
export NXF_PLUGIN_AUTOINSTALL=false

if [[ "$RUN_PIPELINE" != yes ]]; then
  echo "SUCCESS: staged, verified, and images loaded. Set RUN_PIPELINE=yes to execute."
  exit 0
fi

mapfile -t RUN_ARGS < "$BUNDLE_ROOT/offline/run.args"
RUN_PROFILE="$(cat "$BUNDLE_ROOT/offline/run.profile")"
cd "$BUNDLE_ROOT"
nf run workflow -profile "$RUN_PROFILE" -params-file offline/params_offline.json -c offline/offline_test.conf \
  -work-dir work -offline "${RUN_ARGS[@]}"
echo "SUCCESS: offline pipeline completed"
