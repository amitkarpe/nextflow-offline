#!/usr/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <inspect-json> <output-image-directory>" >&2
  exit 2
fi

INSPECT_JSON="$1"
OUTPUT_IMAGE_DIR="$2"
CONTAINER_ENGINE="${CONTAINER_ENGINE:-podman}"
IMAGE_MANIFEST_FILE="${IMAGE_MANIFEST_FILE:-$OUTPUT_IMAGE_DIR/images.tsv}"
IMAGE_ARCHIVE_SOURCE_DIR="${IMAGE_ARCHIVE_SOURCE_DIR:-}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

[ -f "$INSPECT_JSON" ] || { echo "inspect JSON not found: $INSPECT_JSON" >&2; exit 1; }
case "$CONTAINER_ENGINE" in
  podman|docker) ;;
  *) echo "CONTAINER_ENGINE must be podman or docker" >&2; exit 1 ;;
esac
need jq
need "$CONTAINER_ENGINE"
jq -e '.processes | type == "array"' "$INSPECT_JSON" >/dev/null || {
  echo "inspect JSON has no processes array: $INSPECT_JSON" >&2
  exit 1
}

mapfile -t images < <(
  jq -r '.processes[]? | .container? | select(type == "string" and length > 0)' \
    "$INSPECT_JSON" | sort -u
)
[ "${#images[@]}" -gt 0 ] || {
  echo "no container images found in $INSPECT_JSON" >&2
  exit 1
}

mkdir -p "$OUTPUT_IMAGE_DIR"
manifest_dir="$(dirname "$IMAGE_MANIFEST_FILE")"
mkdir -p "$manifest_dir"
manifest_tmp="${IMAGE_MANIFEST_FILE}.tmp"
trap 'rm -f "$manifest_tmp"' EXIT
printf 'source\timage_id\tarchive\tarchive_sha256\n' > "$manifest_tmp"

sanitize() {
  printf '%s' "$1" | tr '/:@' '___' | tr -cd 'A-Za-z0-9_.-'
}

if [ -n "$IMAGE_ARCHIVE_SOURCE_DIR" ]; then
  [ -d "$IMAGE_ARCHIVE_SOURCE_DIR" ] || {
    echo "image archive source directory not found: $IMAGE_ARCHIVE_SOURCE_DIR" >&2
    exit 1
  }
  declare -A archive_for_image=()
  declare -A image_id_for_image=()
  mapfile -t source_archives < <(find "$IMAGE_ARCHIVE_SOURCE_DIR" -maxdepth 1 -type f -name '*.tar' -print | sort)
  [ "${#source_archives[@]}" -gt 0 ] || {
    echo "no image archives found in $IMAGE_ARCHIVE_SOURCE_DIR" >&2
    exit 1
  }
  for source_archive in "${source_archives[@]}"; do
    tar -tf "$source_archive" >/dev/null
    archive_manifest="$(tar -O -xf "$source_archive" manifest.json)"
    config_name="$(jq -r '.[0].Config // empty' <<<"$archive_manifest")"
    [ -n "$config_name" ] || { echo "archive has no config: $source_archive" >&2; exit 1; }
    mapfile -t archive_tags < <(jq -r '.[].RepoTags[]?' <<<"$archive_manifest")
    for tag in "${archive_tags[@]}"; do
      archive_for_image["$tag"]="$source_archive"
      image_id_for_image["$tag"]="archive-config:$config_name"
    done
  done
  for image in "${images[@]}"; do
    source_archive="${archive_for_image[$image]:-}"
    [ -n "$source_archive" ] || {
      echo "no staged archive matches inspected image: $image" >&2
      exit 1
    }
    name="$(sanitize "$image")"
    archive="$OUTPUT_IMAGE_DIR/${name}.tar"
    cp "$source_archive" "$archive"
    archive_sha256="$(sha256sum "$archive" | awk '{print $1}')"
    printf '%s\t%s\t%s\t%s\n' "$image" "${image_id_for_image[$image]}" "${archive##*/}" "$archive_sha256" >> "$manifest_tmp"
  done
else
  for image in "${images[@]}"; do
    name="$(sanitize "$image")"
    archive="$OUTPUT_IMAGE_DIR/${name}.tar"
    temp_archive="${archive}.tmp"

    echo "Pulling $image with $CONTAINER_ENGINE"
    "$CONTAINER_ENGINE" pull "$image"
    image_id="$("$CONTAINER_ENGINE" image inspect --format '{{.Id}}' "$image")"
    [ -n "$image_id" ] || { echo "no image id returned for $image" >&2; exit 1; }
    rm -f "$temp_archive"
    "$CONTAINER_ENGINE" save -o "$temp_archive" "$image"
    tar -tf "$temp_archive" >/dev/null
    mv "$temp_archive" "$archive"
    archive_sha256="$(sha256sum "$archive" | awk '{print $1}')"
    printf '%s\t%s\t%s\t%s\n' "$image" "$image_id" "${archive##*/}" "$archive_sha256" >> "$manifest_tmp"
  done
fi

mv "$manifest_tmp" "$IMAGE_MANIFEST_FILE"
echo "Saved ${#images[@]} portable image archives in $OUTPUT_IMAGE_DIR"
