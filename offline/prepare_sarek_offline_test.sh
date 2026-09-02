#!/usr/bin/bash
set -euo pipefail

SAREK_VERSION="${SAREK_VERSION:-3.10.0}"
BUNDLE_ROOT="${BUNDLE_ROOT:-$PWD/.sarek-bundle}"
ECR_REGISTRY="${ECR_REGISTRY:?set ECR_REGISTRY to the private ECR registry host}"
ECR_REPOSITORY="${ECR_REPOSITORY:-sarek-images}"
PUBLISH_ECR="${PUBLISH_ECR:-no}"
PUBLISH_S3="${PUBLISH_S3:-no}"
S3_ROOT="${S3_ROOT:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }
need nf-core
need nextflow
need jq
mkdir -p "$BUNDLE_ROOT"/{workflow,data/reads,data/refs,offline,manifests}

echo "Preparing nf-core/sarek ${SAREK_VERSION} under ${BUNDLE_ROOT}"
nf-core pipelines download sarek -r "$SAREK_VERSION" \
  --outdir "$BUNDLE_ROOT" --compress none --container-system none \
  --download-configuration --force
cp "$SCRIPT_DIR/offline_test.conf" "$BUNDLE_ROOT/offline/offline_test.conf"
cp "$SCRIPT_DIR/params_offline.json" "$BUNDLE_ROOT/offline/params_offline.json"

export NXF_HOME="${NXF_HOME:-$BUNDLE_ROOT/offline/nextflow-home}"
for plugin in nf-core-utils@0.4.0 nf-fgbio@1.0.0 nf-prov@1.7.0 nf-schema@2.7.2; do
  nextflow plugin install "$plugin"
done

WORKFLOW_DIR="$BUNDLE_ROOT/workflow"
[ -f "$WORKFLOW_DIR/main.nf" ] || { echo "workflow/main.nf not found" >&2; exit 1; }
nextflow inspect "$WORKFLOW_DIR" -profile test,podman -format json > "$BUNDLE_ROOT/manifests/inspect.json"
jq -r '.processes[]?.container | select(type == "string" and length > 0)' \
  "$BUNDLE_ROOT/manifests/inspect.json" | sort -u > "$BUNDLE_ROOT/manifests/images.txt"
[ -s "$BUNDLE_ROOT/manifests/images.txt" ] || { echo "empty image inventory" >&2; exit 1; }

sanitize() { printf '%s' "$1" | tr '/:@' '___' | tr -cd 'A-Za-z0-9_.-'; }
{
  printf 'source\ttarget\n'
  while IFS= read -r image; do
    target="${ECR_REGISTRY}/${ECR_REPOSITORY}:$(sanitize "$image")"
    printf '%s\t%s\n' "$image" "$target"
    if [ "$PUBLISH_ECR" = yes ]; then
      need aws
      need podman
      if [ "${ECR_LOGIN_DONE:-no}" != yes ]; then
        aws ecr get-login-password | podman login --username AWS --password-stdin "$ECR_REGISTRY"
        ECR_LOGIN_DONE=yes
      fi
      podman pull "$image"
      podman tag "$image" "$target"
      podman push "$target"
    fi
  done < "$BUNDLE_ROOT/manifests/images.txt"
} > "$BUNDLE_ROOT/manifests/image-map.tsv"

# Rewrite only workflow/config source references; the original inventory remains evidence.
while IFS=$'\t' read -r source target; do
  [ "$source" = source ] && continue
  needle=${source//&/\\&}; replacement=${target//&/\\&}
  while IFS= read -r -d '' file; do
    sed -i "s|$needle|$replacement|g" "$file"
  done < <(find "$WORKFLOW_DIR" -type f \( -name '*.nf' -o -name '*.config' \) -print0)
done < "$BUNDLE_ROOT/manifests/image-map.tsv"

sha256sum "$BUNDLE_ROOT/manifests/images.txt" "$BUNDLE_ROOT/manifests/image-map.tsv" \
  > "$BUNDLE_ROOT/manifests/SHA256SUMS"
printf 'sarek_version=%s\nnextflow_minimum=25.10.4\n' "$SAREK_VERSION" \
  > "$BUNDLE_ROOT/manifests/release.env"

if [ "$PUBLISH_S3" = yes ]; then
  need aws
  [ -n "$S3_ROOT" ] || { echo 'S3_ROOT is required when PUBLISH_S3=yes' >&2; exit 1; }
  aws s3 sync "$BUNDLE_ROOT/" "${S3_ROOT%/}/sarek/" --only-show-errors
fi
echo "Prepared bundle: $BUNDLE_ROOT"
