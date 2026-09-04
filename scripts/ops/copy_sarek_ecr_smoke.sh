#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/ENV" ]; then
  set -a
  source "$SCRIPT_DIR/ENV"
  set +a
fi

: "${AWS_PROFILE:?set AWS_PROFILE or scripts/ops/ENV}"
: "${AWS_REGION:?set AWS_REGION or scripts/ops/ENV}"

source_image="quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0"
target_tag="quay-biocontainers-fastqc-0.12.1-hdfd78af-0-e194048df39c"
account_id="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)"
ecr_registry="${account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com"
target_image="${ecr_registry}/nextflow/sarek:${target_tag}"

auth_dir="${REGISTRY_AUTH_DIR:-$SCRIPT_DIR/.runtime}"
mkdir -p "$auth_dir"
auth_file="$auth_dir/ecr-auth.json"
cleanup() {
  if [ -f "$auth_file" ]; then
    find "$auth_file" -maxdepth 0 -type f -delete
  fi
}
trap cleanup EXIT

source_digest="$(skopeo inspect --no-tags "docker://${source_image}" --format '{{.Digest}}')"
[ "$source_digest" = 'sha256:e194048df39c3145d9b4e0a14f4da20b59d59250465b6f2a9cb698445fd45900' ] || {
  echo "source digest changed: $source_digest" >&2
  exit 1
}

aws ecr get-login-password --profile "$AWS_PROFILE" --region "$AWS_REGION" |
  skopeo login --authfile "$auth_file" --username AWS --password-stdin "$ecr_registry" >/dev/null

skopeo copy --authfile "$auth_file" \
  --src-tls-verify=true \
  --dest-tls-verify=true \
  "docker://${source_image}" \
  "docker://${target_image}"

target_digest="$(skopeo inspect --authfile "$auth_file" --no-tags "docker://${target_image}" --format '{{.Digest}}')"
printf 'SOURCE_IMAGE=%s\nSOURCE_DIGEST=%s\nTARGET_IMAGE=%s\nTARGET_DIGEST=%s\n' \
  "$source_image" "$source_digest" "$target_image" "$target_digest"
