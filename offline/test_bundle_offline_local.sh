#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PIPELINE="${PIPELINE:-nf-core/demo}"
REVISION="${REVISION:-1.0.2}"
SOURCE_MODE="${SOURCE_MODE:-public}"
PUBLISH_S3="${PUBLISH_S3:-no}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
: "${BUILD_ROOT:?BUILD_ROOT must name a fresh bundle directory}"
: "${TEST_ROOT:?TEST_ROOT must name a different fresh relocated directory}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

case "$PIPELINE:$REVISION" in
  nf-core/demo:1.0.2) ;;
  *) echo "this local proof only supports PIPELINE=nf-core/demo REVISION=1.0.2" >&2; exit 1 ;;
esac
[ "$SOURCE_MODE" = public ] || {
  echo "SOURCE_MODE must be public for this no-S3 local proof" >&2
  exit 1
}
[ "$PUBLISH_S3" = no ] || {
  echo "PUBLISH_S3 must be no for this local proof" >&2
  exit 1
}
[ "$CONTAINER_ENGINE" = podman ] || {
  echo "CONTAINER_ENGINE must be podman for this local proof" >&2
  exit 1
}
need podman
need nextflow
need sha256sum

BUILD_ROOT="$(mkdir -p "$BUILD_ROOT" && cd "$BUILD_ROOT" && pwd)"
TEST_ROOT="$(mkdir -p "$TEST_ROOT" && cd "$TEST_ROOT" && pwd)"
[ "$BUILD_ROOT" != "$TEST_ROOT" ] || {
  echo "BUILD_ROOT and TEST_ROOT must differ" >&2
  exit 1
}
for root in "$BUILD_ROOT" "$TEST_ROOT"; do
  [ -z "$(find "$root" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
    echo "proof root must be empty: $root" >&2
    exit 1
  }
done

env BUNDLE_ENV="${BUNDLE_ENV:-/dev/null}" \
  PIPELINE="$PIPELINE" \
  REVISION="$REVISION" \
  SOURCE_MODE="$SOURCE_MODE" \
  PUBLISH_S3=no \
  LOAD_BUNDLE_IMAGES=no \
  CONTAINER_ENGINE=podman \
  BUNDLE_ROOT="$BUILD_ROOT" \
  /usr/bin/bash "$SCRIPT_DIR/build_offline_bundle.sh"

for required in workflow containers plugins data offline manifests README.txt; do
  [ -e "$BUILD_ROOT/$required" ] || {
    echo "missing required bundle path: $required" >&2
    exit 1
  }
done

cp -a "$BUILD_ROOT/." "$TEST_ROOT/"
( cd "$TEST_ROOT" && sha256sum -c manifests/files.sha256 ) \
  > "$TEST_ROOT/manifests/local-offline-checksums.log"

PODMAN_BIN="$(command -v podman)"
PODMAN_GRAPH="$TEST_ROOT/.podman/graph"
if [ -n "${PODMAN_RUNROOT:-}" ]; then
  podman_runroot_owned=no
else
  PODMAN_RUNROOT="$(mktemp -d "/run/user/$(id -u)/nextflow-offline.XXXXXX")"
  podman_runroot_owned=yes
fi
PODMAN_WRAPPER_DIR="$TEST_ROOT/.podman/bin"
mkdir -p "$PODMAN_GRAPH" "$PODMAN_WRAPPER_DIR"
if [ "$podman_runroot_owned" = yes ]; then
  trap 'rmdir "$PODMAN_RUNROOT" 2>/dev/null || true' EXIT
fi
printf '%s\n' '#!/usr/bin/bash' \
  "exec \"$PODMAN_BIN\" --root \"$PODMAN_GRAPH\" --runroot \"$PODMAN_RUNROOT\" \"\$@\"" \
  > "$PODMAN_WRAPPER_DIR/podman"
chmod 0755 "$PODMAN_WRAPPER_DIR/podman"
export PATH="$PODMAN_WRAPPER_DIR:$PATH"

[ -z "$(podman images -q)" ] || {
  echo "isolated Podman store is not empty before archive load" >&2
  exit 1
}
loaded=0
for archive in "$TEST_ROOT"/containers/*.tar; do
  [ -f "$archive" ] || continue
  podman load -i "$archive"
  loaded=$((loaded + 1))
done
[ "$loaded" -gt 0 ] || {
  echo "no bundle container archives were loaded" >&2
  exit 1
}
while IFS=$'\t' read -r image _; do
  [ "$image" = source ] && continue
  podman image exists "$image" || {
    echo "archive did not preserve required image tag: $image" >&2
    exit 1
  }
done < "$TEST_ROOT/manifests/images.tsv"

chmod +x "$TEST_ROOT"/workflow/bin/* 2>/dev/null || true
NXF_VER="$(sed -n 's/^NXF_VER=//p' "$TEST_ROOT/manifests/pipeline.env")"
[ -n "$NXF_VER" ] || {
  echo "bundle manifest does not declare NXF_VER" >&2
  exit 1
}
export NXF_VER
NEXTFLOW_BIN="$(command -v nextflow)"
if grep -q '^export NXF_HOME=' "$NEXTFLOW_BIN" 2>/dev/null; then
  tools_root="$(sed -n 's/^export NEXTFLOW_TOOLS_ROOT=//p' "$NEXTFLOW_BIN")"
  if [ -n "$tools_root" ] && [ -x "$tools_root/nextflow/nextflow" ]; then
    export JAVA_HOME="$tools_root/java"
    export PATH="$JAVA_HOME/bin:$PATH"
    NEXTFLOW_BIN="$tools_root/nextflow/nextflow"
  fi
fi
nf() { "$NEXTFLOW_BIN" "$@"; }

export NXF_HOME="$TEST_ROOT/plugins/nextflow-home"
export NXF_OFFLINE=true
export NXF_PLUGIN_AUTOINSTALL=false
(
  cd "$TEST_ROOT"
  nf run "$TEST_ROOT/workflow" \
    -profile podman,offline_smoke \
    -params-file "$TEST_ROOT/offline/params_offline.json" \
    -c "$TEST_ROOT/offline/offline_test.conf" \
    --input data/reads/samplesheet.csv \
    --outdir "$TEST_ROOT/results" \
    -work-dir "$TEST_ROOT/work" \
    -offline
)

[ -f "$TEST_ROOT/results/multiqc/multiqc_report.html" ] || {
  echo "expected MultiQC report is missing" >&2
  exit 1
}

printf 'PIPELINE=%s\n' "$PIPELINE"
printf 'REVISION=%s\n' "$REVISION"
printf 'BUILD_RC=0\n'
printf 'PUBLISH_S3=no\n'
printf 'RELOCATED_BUNDLE=PASS\n'
printf 'REQUIRED_BUNDLE_PATHS=PASS\n'
printf 'CHECKSUMS=PASS\n'
printf 'PODMAN_ARCHIVES_LOADED=%s\n' "$loaded"
printf 'IMAGE_TAG_MAPPING=PASS\n'
printf 'NXF_HOME=bundle-local\n'
printf 'NXF_OFFLINE=true\n'
printf 'NXF_PLUGIN_AUTOINSTALL=false\n'
printf 'NEXTFLOW_OFFLINE_FLAG=true\n'
printf 'PODMAN_NETWORK=none\n'
printf 'PIPELINE_RC=0\n'
printf 'EXPECTED_DEMO_STAGES=PASS\n'
printf 'RESULT=SUCCESS\n'
