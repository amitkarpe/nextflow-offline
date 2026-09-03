#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${BUNDLE_ENV:-$SCRIPT_DIR/bundle.env}"

if [ -f "$ENV_FILE" ]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

PIPELINE="${PIPELINE:-nf-core/demo}"
REVISION="${REVISION:-1.0.2}"
PROFILE="${PROFILE:-podman}"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
SOURCE_MODE="${SOURCE_MODE:-s3-cache}"
S3_BUNDLE_PREFIX="${S3_BUNDLE_PREFIX:-s3://trust-team/nextflow-offline/bundles/demo-1.0.2}"
DATA_S3_PREFIX="${DATA_S3_PREFIX:-s3://trust-team/nextflow-offline/data/rnaseq-tiny-20260624}"
BUNDLE_ROOT="${BUNDLE_ROOT:-$HOME/.cache/nextflow-offline/${PIPELINE##*/}-${REVISION}}"
PUBLISH_S3="${PUBLISH_S3:-no}"
S3_ROOT="${S3_ROOT:-}"
PUBLISH_PREFIX="${PUBLISH_PREFIX:-}"
PUBLISH_REQUIRE_EMPTY="${PUBLISH_REQUIRE_EMPTY:-yes}"
LOAD_BUNDLE_IMAGES="${LOAD_BUNDLE_IMAGES:-yes}"
NXF_VER="${NXF_VER:-25.10.4}"
export NXF_VER

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

case "$CONTAINER_ENGINE" in
  podman|docker) ;;
  *) echo "CONTAINER_ENGINE must be podman or docker" >&2; exit 1 ;;
esac
case "$SOURCE_MODE" in
  s3-cache) need aws ;;
  public) need nf-core ;;
  *) echo "SOURCE_MODE must be s3-cache or public" >&2; exit 1 ;;
esac
need jq
need "$CONTAINER_ENGINE"
need nextflow
[ "$PUBLISH_S3" = yes ] || [ "$PUBLISH_S3" = no ] || {
  echo "PUBLISH_S3 must be yes or no" >&2
  exit 1
}
if [ "$PUBLISH_S3" = yes ]; then
  need aws
  [ -n "$PUBLISH_PREFIX" ] || [ -n "$S3_ROOT" ] || {
    echo "PUBLISH_PREFIX or S3_ROOT is required when PUBLISH_S3=yes" >&2
    exit 1
  }
fi
case "$PUBLISH_REQUIRE_EMPTY" in
  yes|no) ;;
  *) echo "PUBLISH_REQUIRE_EMPTY must be yes or no" >&2; exit 1 ;;
esac
case "$LOAD_BUNDLE_IMAGES" in
  yes|no) ;;
  *) echo "LOAD_BUNDLE_IMAGES must be yes or no" >&2; exit 1 ;;
esac

# The host launcher pins Java/NXF_HOME. Invoke its underlying launcher so the
# bundle owns the framework and plugin cache.
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

BUNDLE_ROOT="$(mkdir -p "$BUNDLE_ROOT" && cd "$BUNDLE_ROOT" && pwd)"
if [ -n "$(find "$BUNDLE_ROOT" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  echo "BUNDLE_ROOT must be empty: $BUNDLE_ROOT" >&2
  exit 1
fi
STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/nextflow-offline.XXXXXX")"
trap 'rm -rf "$STAGE_ROOT"' EXIT

PIPELINE_NAME="${PIPELINE##*/}"
PUBLISH_URI=""
PUBLISH_BUCKET=""
PUBLISH_KEY_PREFIX=""
if [ "$PUBLISH_S3" = yes ]; then
  PUBLISH_URI="${PUBLISH_PREFIX:-${S3_ROOT%/}/${PIPELINE_NAME}/${REVISION}/}"
  PUBLISH_URI="${PUBLISH_URI%/}/"
  publish_path="${PUBLISH_URI#s3://}"
  PUBLISH_BUCKET="${publish_path%%/*}"
  PUBLISH_KEY_PREFIX="${publish_path#*/}"
  if [ "$publish_path" = "$PUBLISH_KEY_PREFIX" ] || [ -z "${PUBLISH_KEY_PREFIX%/}" ]; then
    echo "PUBLISH_PREFIX must include a bucket and non-empty key prefix: $PUBLISH_URI" >&2
    exit 1
  fi
fi
WORKFLOW_SOURCE="$STAGE_ROOT/workflow"
DATA_SOURCE="$STAGE_ROOT/data"
IMAGE_SOURCE="$STAGE_ROOT/images"
PLUGIN_HOME="$BUNDLE_ROOT/plugins/nextflow-home"
CONTAINER_PROFILE="$PROFILE"
[ "$CONTAINER_ENGINE" = docker ] && CONTAINER_PROFILE=docker
mkdir -p "$BUNDLE_ROOT"/{workflow,containers,plugins/nextflow-home,data/reads,data/refs,offline,manifests}
mkdir -p "$WORKFLOW_SOURCE" "$DATA_SOURCE" "$IMAGE_SOURCE"

echo "Building $PIPELINE revision $REVISION from $SOURCE_MODE"
if [ "$SOURCE_MODE" = s3-cache ]; then
  case "$PIPELINE:$REVISION" in
    nf-core/demo:1.0.2) ;;
    *) echo "s3-cache currently requires PIPELINE=nf-core/demo and REVISION=1.0.2" >&2; exit 1 ;;
  esac
  aws s3 cp "${S3_BUNDLE_PREFIX%/}/1_0_2/" "$WORKFLOW_SOURCE/" --recursive --only-show-errors
  aws s3 cp "${S3_BUNDLE_PREFIX%/}/docker-images/" "$IMAGE_SOURCE/" --recursive --only-show-errors
  aws s3 cp "${DATA_S3_PREFIX%/}/" "$DATA_SOURCE/" --recursive --only-show-errors
else
  need curl
  nf-core pipelines download "$PIPELINE" -r "$REVISION" \
    --outdir "$STAGE_ROOT/download" \
    --compress none \
    --container-system none \
    --download-configuration yes \
    --force
  MAIN_NF="$(find "$STAGE_ROOT/download" -type f -name main.nf -print -quit)"
  [ -n "$MAIN_NF" ] || { echo "downloaded workflow has no main.nf" >&2; exit 1; }
  SOURCE_ROOT="$(dirname "$MAIN_NF")"
  cp -a "$SOURCE_ROOT/." "$WORKFLOW_SOURCE/"
  if [ -d "$STAGE_ROOT/download/configs" ]; then
    cp -a "$STAGE_ROOT/download/configs" "$BUNDLE_ROOT/configs"
  fi
  TEST_CONFIG="$WORKFLOW_SOURCE/conf/test.config"
  [ -f "$TEST_CONFIG" ] || {
    echo "public mode requires pipeline conf/test.config: $TEST_CONFIG" >&2
    exit 1
  }
  TEST_INPUT_URL="$(grep -E '^[[:space:]]*input[[:space:]]*=' "$TEST_CONFIG" |
    sed -n "s/.*['\"]\(https\?:[^'\"]*\)['\"].*/\1/p" | head -1)"
  [ -n "$TEST_INPUT_URL" ] || {
    echo "public mode could not find an HTTP test input in $TEST_CONFIG" >&2
    exit 1
  }
  curl -fsSL "$TEST_INPUT_URL" -o "$DATA_SOURCE/upstream_samplesheet.csv"
  while IFS=, read -r sample r1 r2; do
    [ "$sample" = sample ] && continue
    for url in "$r1" "$r2"; do
      [ -n "$url" ] || continue
      case "$url" in
        http://*|https://*) ;;
        *) echo "unsupported public test input URL: $url" >&2; exit 1 ;;
      esac
      filename="${url##*/}"
      curl -fsSL "$url" -o "$DATA_SOURCE/$filename"
    done
  done < "$DATA_SOURCE/upstream_samplesheet.csv"
  DATA_SOURCE_LABEL="$TEST_INPUT_URL"
fi

[ -n "${DATA_SOURCE_LABEL:-}" ] || DATA_SOURCE_LABEL="$DATA_S3_PREFIX"

[ -f "$WORKFLOW_SOURCE/main.nf" ] || { echo "workflow/main.nf not found" >&2; exit 1; }
cp -a "$WORKFLOW_SOURCE/." "$BUNDLE_ROOT/workflow/"

R1_SOURCE="$(find "$DATA_SOURCE" -type f -name '*R1*.fastq.gz' -print -quit)"
R2_SOURCE="$(find "$DATA_SOURCE" -type f -name '*R2*.fastq.gz' -print -quit)"
[ -n "$R1_SOURCE" ] && [ -n "$R2_SOURCE" ] || {
  echo "paired FASTQ files were not found under $DATA_SOURCE_LABEL" >&2
  exit 1
}
cp "$R1_SOURCE" "$BUNDLE_ROOT/data/reads/tiny_R1.fastq.gz"
cp "$R2_SOURCE" "$BUNDLE_ROOT/data/reads/tiny_R2.fastq.gz"
cat > "$BUNDLE_ROOT/data/reads/samplesheet.csv" <<EOF
sample,fastq_1,fastq_2
OFFLINE_TINY,data/reads/tiny_R1.fastq.gz,data/reads/tiny_R2.fastq.gz
EOF
find "$DATA_SOURCE" -maxdepth 1 -type f \( -name '*.fasta' -o -name '*.fa' -o -name '*.gtf' -o -name '*.gtf.gz' \) \
  -exec cp {} "$BUNDLE_ROOT/data/refs/" \;
cat > "$BUNDLE_ROOT/data/refs/README.txt" <<EOF
Input source: $DATA_SOURCE_LABEL
The FASTQ and reference files are pre-staged local assets; no runtime download is allowed.
EOF

DEMO_PARAMS_FILE="$REPO_ROOT/offline/params_demo_offline.json"
[ -f "$DEMO_PARAMS_FILE" ] || { echo "demo params file not found: $DEMO_PARAMS_FILE" >&2; exit 1; }
cp "$DEMO_PARAMS_FILE" "$BUNDLE_ROOT/offline/params_offline.json"
cp "$REPO_ROOT/offline/offline_test.conf" "$BUNDLE_ROOT/offline/offline_test.conf"

mapfile -t plugins < <(
  grep -RhoE "id '[^']+'" "$BUNDLE_ROOT/workflow" 2>/dev/null |
    sed -E "s/^id '([^']+)'$/\1/" | sort -u
)
printf '%s\n' "${plugins[@]}" > "$BUNDLE_ROOT/manifests/plugins.txt"
for plugin in "${plugins[@]}"; do
  NXF_HOME="$PLUGIN_HOME" NXF_PLUGIN_AUTOINSTALL=false nf plugin install "$plugin"
done

export NXF_HOME="$PLUGIN_HOME"
export NXF_OFFLINE=true
export NXF_PLUGIN_AUTOINSTALL=false
nf -version > "$BUNDLE_ROOT/manifests/nextflow.version.txt"
if command -v nf-core >/dev/null 2>&1; then
  nf-core --version > "$BUNDLE_ROOT/manifests/nf-core.version.txt"
else
  printf '%s\n' 'not used (SOURCE_MODE=s3-cache)' > "$BUNDLE_ROOT/manifests/nf-core.version.txt"
fi
nf inspect "$BUNDLE_ROOT/workflow" -profile "$CONTAINER_PROFILE,offline_smoke" \
  -c "$BUNDLE_ROOT/offline/offline_test.conf" -format json \
  > "$BUNDLE_ROOT/manifests/inspect.json"
jq -e '.processes | type == "array" and length > 0' \
  "$BUNDLE_ROOT/manifests/inspect.json" >/dev/null

IMAGE_ARCHIVE_SOURCE_DIR=""
[ "$SOURCE_MODE" = s3-cache ] && IMAGE_ARCHIVE_SOURCE_DIR="$IMAGE_SOURCE"
IMAGE_MANIFEST_FILE="$BUNDLE_ROOT/manifests/images.tsv" \
IMAGE_ARCHIVE_SOURCE_DIR="$IMAGE_ARCHIVE_SOURCE_DIR" \
CONTAINER_ENGINE="$CONTAINER_ENGINE" \
  "$REPO_ROOT/scripts/fetch_and_save_images.sh" \
  "$BUNDLE_ROOT/manifests/inspect.json" "$BUNDLE_ROOT/containers"

if [ "$LOAD_BUNDLE_IMAGES" = yes ]; then
  for archive in "$BUNDLE_ROOT"/containers/*.tar; do
    [ -f "$archive" ] || continue
    "$CONTAINER_ENGINE" load -i "$archive"
  done
else
  echo "Skipping bundle image loads (LOAD_BUNDLE_IMAGES=no)"
fi

cat > "$BUNDLE_ROOT/manifests/pipeline.env" <<EOF
PIPELINE=$PIPELINE
REVISION=$REVISION
PROFILE=$CONTAINER_PROFILE
CONTAINER_ENGINE=$CONTAINER_ENGINE
SOURCE_MODE=$SOURCE_MODE
DATA_S3_PREFIX=$DATA_S3_PREFIX
INPUT_SOURCE=$DATA_SOURCE_LABEL
NXF_VER=$NXF_VER
NEXTFLOW_OFFLINE=true
NXF_PLUGIN_AUTOINSTALL=false
EOF
cat > "$BUNDLE_ROOT/manifests/release.env" <<EOF
pipeline=$PIPELINE
revision=$REVISION
nextflow_version=$NXF_VER
source_mode=$SOURCE_MODE
EOF
[ -z "$PUBLISH_URI" ] || printf 'publish_uri=%s\n' "$PUBLISH_URI" >> "$BUNDLE_ROOT/manifests/release.env"

SMOKE_OUT="$BUNDLE_ROOT/offline/smoke-output"
SMOKE_WORK="$STAGE_ROOT/smoke-work"
mkdir -p "$SMOKE_OUT"
(
  cd "$BUNDLE_ROOT"
  nf run "$BUNDLE_ROOT/workflow" \
    -profile "$CONTAINER_PROFILE,offline_smoke" \
    -params-file "$BUNDLE_ROOT/offline/params_offline.json" \
    -c "$BUNDLE_ROOT/offline/offline_test.conf" \
    --input data/reads/samplesheet.csv \
    --outdir "$SMOKE_OUT" \
    -work-dir "$SMOKE_WORK" \
    -offline \
    -with-report "$SMOKE_OUT/execution-report.html"
)

cat > "$BUNDLE_ROOT/README.txt" <<EOF
Portable Nextflow offline bundle
Pipeline: $PIPELINE
Revision: $REVISION
Container engine: $CONTAINER_ENGINE
Input source: $DATA_SOURCE_LABEL

This bundle was assembled on an online server and validated locally with
NXF_OFFLINE=true. An offline server must use only this bundle.

Load containers:
  for image in <bundle>/containers/*.tar; do
    [ -f "\$image" ] || continue
    $CONTAINER_ENGINE load -i "\$image"
  done

Run from the bundle root:
  cd <bundle>
  NXF_VER=$NXF_VER NXF_OFFLINE=true NXF_PLUGIN_AUTOINSTALL=false \\
    NXF_HOME=\$PWD/plugins/nextflow-home \\
    nextflow run \$PWD/workflow -profile $CONTAINER_PROFILE,offline_smoke \\
    -params-file \$PWD/offline/params_offline.json \\
    -c \$PWD/offline/offline_test.conf \\
    --input data/reads/samplesheet.csv \\
    --outdir ./results -work-dir ./work -offline -resume
EOF
( cd "$BUNDLE_ROOT" &&
  find . -type f ! -path './manifests/files.sha256' -print0 |
    sort -z | xargs -0 sha256sum
) > "$BUNDLE_ROOT/manifests/files.sha256"
if [ "$PUBLISH_S3" = yes ]; then
  if [ "$PUBLISH_REQUIRE_EMPTY" = yes ]; then
    existing_key_count="$(aws s3api list-objects-v2 \
      --bucket "$PUBLISH_BUCKET" \
      --prefix "$PUBLISH_KEY_PREFIX" \
      --max-keys 1 \
      --query 'KeyCount' \
      --output text)"
    if [ "$existing_key_count" != 0 ]; then
      echo "refusing to publish to non-empty prefix: $PUBLISH_URI" >&2
      exit 1
    fi
  fi
  aws s3 sync "$BUNDLE_ROOT/" "$PUBLISH_URI" --only-show-errors
fi

echo "Bundle ready: $BUNDLE_ROOT"
