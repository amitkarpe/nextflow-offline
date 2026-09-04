#!/usr/bin/bash
set -euo pipefail

# Reuses the existing offline/common/aws-validation image-manifest contract:
# source_image, repository_name, tag, ecr_image.  Unlike its Docker/Crane
# engines, this loop uses Skopeo registry-to-registry copy and never calls
# Podman or Docker.

usage() {
  cat <<'EOF'
Usage: mirror_sarek_ecr_images.sh [--image-manifest FILE] [--repository NAME] [--dry-run] [--continue-on-error]

Mirror the exact source-to-ECR rows in a four-column TSV. All rows must target
one existing ECR repository. This command never creates an ECR
repository, pulls images into Podman/Docker, or runs a workflow.
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ -f "$SCRIPT_DIR/ENV" ]; then
  set -a
  source "$SCRIPT_DIR/ENV"
  set +a
fi

manifest="$REPO_ROOT/offline/sarek_ecr_images.tsv"
out_dir="${OUT_DIR:-$REPO_ROOT/.sarek-ecr-mirror}"
repository_name=""
dry_run=false
continue_on_error=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --image-manifest) manifest="${2:?missing manifest path}"; shift 2 ;;
    --repository) repository_name="${2:?missing repository name}"; shift 2 ;;
    --out-dir) out_dir="${2:?missing output path}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --continue-on-error) continue_on_error=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

: "${AWS_PROFILE:?set AWS_PROFILE or scripts/ops/ENV}"
: "${AWS_REGION:?set AWS_REGION or scripts/ops/ENV}"
[ -f "$manifest" ] || die "manifest not found: $manifest"
need aws
need awk
need jq
need skopeo

mkdir -p "$out_dir"
manifest_repository="$(awk -F '\t' 'NR == 2 { print $2; exit }' "$manifest")"
[ -n "$manifest_repository" ] || die "manifest has no image rows"
repository_name="${repository_name:-$manifest_repository}"
awk -F '\t' -v repository="$repository_name" '
  NR == 1 { if ($0 != "source_image\trepository_name\ttag\tecr_image") exit 2; next }
  NF != 4 || $1 == "" || $2 != repository || $3 == "" || $4 == "" { exit 2 }
' "$manifest" || die "invalid manifest; expected four columns targeting $repository_name"
cp "$manifest" "$out_dir/image-manifest.tsv"

{
  printf 'source_image\trepository_name\ttag\tecr_image\taction\n'
  tail -n +2 "$manifest" | awk -F '\t' 'NF == 4 { print $0 "\tplanned" }'
} > "$out_dir/plan.tsv"

if [ "$dry_run" = true ]; then
  printf 'COPY_ENGINE=skopeo\nSTATUS=dry_run\nMANIFEST=%s\n' "$manifest" > "$out_dir/RESULT.md"
  cat "$out_dir/RESULT.md"
  exit 0
fi

account_id="$(aws sts get-caller-identity --profile "$AWS_PROFILE" --query Account --output text)"
ecr_registry="${account_id}.dkr.ecr.${AWS_REGION}.amazonaws.com"
aws ecr describe-repositories --profile "$AWS_PROFILE" --region "$AWS_REGION" \
  --repository-names "$repository_name" >/dev/null

auth_file="$out_dir/ecr-auth.json"
cleanup() {
  if [ -f "$auth_file" ]; then
    find "$auth_file" -maxdepth 0 -type f -delete
  fi
}
trap cleanup EXIT
aws ecr get-login-password --profile "$AWS_PROFILE" --region "$AWS_REGION" |
  skopeo login --authfile "$auth_file" --username AWS --password-stdin "$ecr_registry" >/dev/null

printf 'source_image\trepository_name\ttag\tecr_image\tsource_manifest\ttarget_manifest\tconfig_digest\taction\n' \
  > "$out_dir/successful-images.tsv"
printf 'source_image\trepository_name\ttag\tecr_image\tstage\n' > "$out_dir/failed-images.tsv"
copied=0
skipped=0
failed=0

while IFS=$'\t' read -r source_image repository_name tag ecr_image; do
  [ -n "$source_image" ] || continue
  case "$ecr_image" in "$ecr_registry/$repository_name:$tag") ;; *) die "manifest destination mismatch: $ecr_image" ;; esac
  source_manifest="$(skopeo inspect --no-tags "docker://$source_image" --format '{{.Digest}}')" || {
    printf '%s\t%s\t%s\t%s\tsource-inspect\n' "$source_image" "$repository_name" "$tag" "$ecr_image" >> "$out_dir/failed-images.tsv"
    failed=$((failed + 1)); [ "$continue_on_error" = true ] && continue || exit 1
  }
  source_config="$(skopeo inspect --raw "docker://$source_image" | jq -r '.config.digest // empty')"
  [ -n "$source_config" ] || die "source manifest has no config digest: $source_image"
  if target_manifest="$(skopeo inspect --authfile "$auth_file" --no-tags "docker://$ecr_image" --format '{{.Digest}}' 2>/dev/null)"; then
    target_config="$(skopeo inspect --authfile "$auth_file" --raw "docker://$ecr_image" | jq -r '.config.digest // empty')"
    if [ "$target_config" = "$source_config" ]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\tskipped-existing\n' "$source_image" "$repository_name" "$tag" "$ecr_image" "$source_manifest" "$target_manifest" "$source_config" >> "$out_dir/successful-images.tsv"
      skipped=$((skipped + 1))
      continue
    fi
    die "immutable destination tag has a different digest: $ecr_image"
  fi
  if skopeo copy --authfile "$auth_file" --src-tls-verify=true --dest-tls-verify=true \
    "docker://$source_image" "docker://$ecr_image" > "$out_dir/skopeo-copy-${copied}.log" 2>&1; then
    target_manifest="$(skopeo inspect --authfile "$auth_file" --no-tags "docker://$ecr_image" --format '{{.Digest}}')"
    target_config="$(skopeo inspect --authfile "$auth_file" --raw "docker://$ecr_image" | jq -r '.config.digest // empty')"
    [ "$target_config" = "$source_config" ] || die "config digest mismatch after copy: $ecr_image"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\tcopied\n' "$source_image" "$repository_name" "$tag" "$ecr_image" "$source_manifest" "$target_manifest" "$source_config" >> "$out_dir/successful-images.tsv"
    copied=$((copied + 1))
  else
    printf '%s\t%s\t%s\t%s\tcopy\n' "$source_image" "$repository_name" "$tag" "$ecr_image" >> "$out_dir/failed-images.tsv"
    failed=$((failed + 1)); [ "$continue_on_error" = true ] || exit 1
  fi
done < <(tail -n +2 "$manifest")

printf 'COPY_ENGINE=skopeo\nCOPIED=%s\nSKIPPED=%s\nFAILED=%s\n' "$copied" "$skipped" "$failed" > "$out_dir/RESULT.md"
cat "$out_dir/RESULT.md"
[ "$failed" -eq 0 ]
