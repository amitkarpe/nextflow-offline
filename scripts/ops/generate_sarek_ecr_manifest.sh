#!/usr/bin/bash
set -euo pipefail

# Generates the established four-column ECR manifest from the retained Sarek
# 3.4.4 source inventory. Tags are deterministic source hashes so every row is
# portable, collision-resistant, and within ECR's 128-character tag limit.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -f "$SCRIPT_DIR/ENV" ]; then
  set -a
  source "$SCRIPT_DIR/ENV"
  set +a
fi

: "${AWS_PROFILE:?set AWS_PROFILE or scripts/ops/ENV}"
: "${AWS_REGION:?set AWS_REGION or scripts/ops/ENV}"
source_list="${SOURCE_LIST:-$REPO_ROOT/offline/sarek_source_images_3.4.4.txt}"
output="${OUTPUT_MANIFEST:-$REPO_ROOT/offline/sarek_ecr_images.tsv}"
[ -f "$source_list" ] || { echo "source list missing: $source_list" >&2; exit 1; }

account_id="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)"
registry="${account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com"
tmp_output="${output}.new"
cleanup() {
  if [ -f "$tmp_output" ]; then
    find "$tmp_output" -maxdepth 0 -type f -delete
  fi
}
trap cleanup EXIT
printf 'source_image\trepository_name\ttag\tecr_image\n' > "$tmp_output"
while IFS= read -r source_image; do
  [ -n "$source_image" ] || continue
  tag="src-$(printf '%s' "$source_image" | sha256sum | cut -c1-24)"
  printf '%s\tnextflow/sarek\t%s\t%s/nextflow/sarek:%s\n' \
    "$source_image" "$tag" "$registry" "$tag" >> "$tmp_output"
done < "$source_list"
{
  head -n 1 "$tmp_output"
  tail -n +2 "$tmp_output" | sort -u -t $'\t' -k1,1
} > "$output"
rows="$(wc -l < "$output")"
printf 'MANIFEST=%s\nROWS=%s\n' "$output" "$((rows - 1))"
