#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"

AWS_PROFILE="${AWS_PROFILE:-dev}"
S3_ROOT="${S3_ROOT:-s3://trust-team/nextflow-offline}"
PIPELINE="${PIPELINE:-demo}"
REVISION="${REVISION:-1.0.2}"
WORK_ROOT="${WORK_ROOT:-/tmp/nextflow-offline}"
IMAGE_MODE="${IMAGE_MODE:-archive}"
IMAGE_DEST_REGISTRY="${IMAGE_DEST_REGISTRY:-}"
IMAGE_DEST_PREFIX="${IMAGE_DEST_PREFIX:-nextflow-offline}"
BUNDLE_CHANNEL="${BUNDLE_CHANNEL:-magic-v1}"
PUBLISH_S3="${PUBLISH_S3:-yes}"
PIPELINES_TSV="${PIPELINES_TSV:-$SCRIPT_DIR/pipelines.tsv}"
TESTDATA_TSV="${TESTDATA_TSV:-$SCRIPT_DIR/testdata.tsv}"

BUNDLE_NAME="${PIPELINE}-${REVISION}"
BUNDLE_ROOT="${BUNDLE_ROOT:-$WORK_ROOT/$BUNDLE_NAME}"
S3_BUNDLE_URI="${S3_BUNDLE_URI:-${S3_ROOT%/}/bundles/${BUNDLE_NAME}/${BUNDLE_CHANNEL}}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }
for tool in nf-core nextflow jq curl sha256sum skopeo; do need "$tool"; done
[[ "$PUBLISH_S3" == yes ]] && need aws

case "$BUNDLE_ROOT" in "$WORK_ROOT"/*) ;; *) echo "BUNDLE_ROOT must stay below WORK_ROOT" >&2; exit 1 ;; esac

row="$(awk -F '\t' -v p="$PIPELINE" -v r="$REVISION" 'NR>1 && $1==p && $2==r {print; exit}' "$PIPELINES_TSV")"
[[ -n "$row" ]] || { echo "missing pipeline row: $PIPELINE $REVISION" >&2; exit 1; }
IFS=$'\t' read -r _ _ INSPECT_PROFILE RUN_PROFILE RUN_ARGS_FILE <<< "$row"
PIPELINE_REF="$PIPELINE"; [[ "$PIPELINE_REF" == */* ]] || PIPELINE_REF="nf-core/$PIPELINE_REF"

echo "==> build $PIPELINE_REF@$REVISION"
rm -rf "$BUNDLE_ROOT"
mkdir -p "$BUNDLE_ROOT"/{containers,plugins,data/reads,data/refs,offline,manifests}

nf-core pipelines download "$PIPELINE_REF" -r "$REVISION" \
  --outdir "$BUNDLE_ROOT" --compress none --container-system none \
  --download-configuration --force

WORKFLOW_DIR="$BUNDLE_ROOT/workflow"
[[ -f "$WORKFLOW_DIR/main.nf" ]] || { echo "workflow/main.nf not found" >&2; exit 1; }
cp "$SCRIPT_DIR/params_offline.json" "$BUNDLE_ROOT/offline/params_offline.json"
cp "$SCRIPT_DIR/offline_test.conf" "$BUNDLE_ROOT/offline/offline_test.conf"
cp "$SCRIPT_DIR/$RUN_ARGS_FILE" "$BUNDLE_ROOT/offline/run.args"
printf '%s\n' "$RUN_PROFILE" > "$BUNDLE_ROOT/offline/run.profile"

while IFS=$'\t' read -r p r kind source destination; do
  [[ "$p" == pipeline || "$p" != "$PIPELINE" || "$r" != "$REVISION" ]] && continue
  target="$BUNDLE_ROOT/$destination"; mkdir -p "$(dirname "$target")"
  echo "==> data [$kind] $source"
  case "$source" in
    repo://*) cp "$SCRIPT_DIR/${source#repo://}" "$target" ;;
    s3://*) need aws; aws --profile "$AWS_PROFILE" s3 cp "$source" "$target" --only-show-errors ;;
    http://*|https://*) curl -fL --retry 3 --output "$target" "$source" ;;
    *) cp "$source" "$target" ;;
  esac
done < "$TESTDATA_TSV"
[[ -f "$BUNDLE_ROOT/data/samplesheet.csv" ]] || { echo "samplesheet missing" >&2; exit 1; }

# Keep the plugin cache inside the bundle. Online inspect may populate it; offline auto-install is disabled later.
export NXF_HOME="$BUNDLE_ROOT/plugins/nextflow-home"
export NXF_PLUGIN_AUTOINSTALL=true
mkdir -p "$NXF_HOME"
nextflow inspect "$WORKFLOW_DIR" -profile "$INSPECT_PROFILE" -format json > "$BUNDLE_ROOT/manifests/inspect.json"
jq -r '.processes[]?.container | select(type == "string" and length > 0)' "$BUNDLE_ROOT/manifests/inspect.json" \
  | sort -u > "$BUNDLE_ROOT/manifests/images.txt"
[[ -s "$BUNDLE_ROOT/manifests/images.txt" ]] || { echo "empty image inventory" >&2; exit 1; }

printf 'source\tmode\tartifact_or_destination\n' > "$BUNDLE_ROOT/manifests/images.tsv"
archive_name() { printf '%s-%s.tar' "$(printf '%s' "$1" | sed 's|.*/||; s|[^A-Za-z0-9_.-]|_|g')" "$(printf '%s' "$1" | sha256sum | cut -c1-12)"; }
registry_target() { printf '%s/%s/%s' "${IMAGE_DEST_REGISTRY%/}" "${IMAGE_DEST_PREFIX#/}" "$(printf '%s' "$1" | sed 's|^docker://||; s|@sha256:|_sha256_|; s|[^A-Za-z0-9._:/-]|_|g')"; }

while IFS= read -r image; do
  [[ -n "$image" ]] || continue
  image="${image#docker://}"
  case "$IMAGE_MODE" in
    archive)
      [[ "$image" != *@sha256:* ]] || { echo "digest-only image needs registry mode or explicit mapping: $image" >&2; exit 1; }
      rel="containers/$(archive_name "$image")"
      echo "==> image $image -> $rel"
      skopeo copy --retry-times 3 "docker://$image" "docker-archive:$BUNDLE_ROOT/$rel:$image"
      printf '%s\tarchive\t%s\n' "$image" "$rel" >> "$BUNDLE_ROOT/manifests/images.tsv"
      ;;
    registry)
      [[ -n "$IMAGE_DEST_REGISTRY" ]] || { echo "IMAGE_DEST_REGISTRY required" >&2; exit 1; }
      target="$(registry_target "$image")"
      skopeo copy --retry-times 3 "docker://$image" "docker://$target"
      printf '%s\tregistry\t%s\n' "$image" "$target" >> "$BUNDLE_ROOT/manifests/images.tsv"
      ;;
    *) echo "unsupported IMAGE_MODE=$IMAGE_MODE" >&2; exit 1 ;;
  esac
done < "$BUNDLE_ROOT/manifests/images.txt"

cat > "$BUNDLE_ROOT/manifests/release.env" <<EOF
pipeline=$PIPELINE_REF
revision=$REVISION
inspect_profile=$INSPECT_PROFILE
run_profile=$RUN_PROFILE
image_mode=$IMAGE_MODE
s3_bundle_uri=$S3_BUNDLE_URI
EOF

cat > "$BUNDLE_ROOT/README.txt" <<EOF
Offline bundle: $PIPELINE_REF@$REVISION
S3: $S3_BUNDLE_URI
Use docs/ops/magic-offline.sh to sync, validate, load images, and optionally run.
EOF

(cd "$BUNDLE_ROOT" && find . -type f ! -path './manifests/files.sha256' -print0 | sort -z | xargs -0 sha256sum > manifests/files.sha256)
"$SCRIPT_DIR/validate-bundle.sh" "$BUNDLE_ROOT"

if [[ "$PUBLISH_S3" == yes ]]; then
  echo "==> aws s3 sync -> $S3_BUNDLE_URI"
  aws --profile "$AWS_PROFILE" s3 sync "$BUNDLE_ROOT/" "$S3_BUNDLE_URI/" --only-show-errors
fi

echo "SUCCESS: $BUNDLE_ROOT"
echo "S3: $S3_BUNDLE_URI"
