#!/usr/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <s3://bucket/prefix/>" >&2
  exit 2
fi

PUBLISH_URI="${1%/}/"
AWS_BIN="${AWS_BIN:-aws}"
case "$PUBLISH_URI" in
  s3://*) ;;
  *) echo "publish URI must start with s3://: $PUBLISH_URI" >&2; exit 2 ;;
esac

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

need "$AWS_BIN"
need jq

uri_path="${PUBLISH_URI#s3://}"
bucket="${uri_path%%/*}"
prefix="${uri_path#*/}"
[ "$uri_path" != "$prefix" ] && [ -n "${prefix%/}" ] || {
  echo "publish URI must include a bucket and non-empty key prefix: $PUBLISH_URI" >&2
  exit 2
}
inventory_file="$(mktemp "${TMPDIR:-/tmp}/nextflow-s3-inventory.XXXXXX")"
metadata_file="$(mktemp "${TMPDIR:-/tmp}/nextflow-s3-readme.XXXXXX")"
trap 'rm -f "$inventory_file" "$metadata_file"' EXIT

"$AWS_BIN" s3 ls "$PUBLISH_URI" --recursive > "$inventory_file"
[ -s "$inventory_file" ] || { echo "published prefix is empty: $PUBLISH_URI" >&2; exit 1; }

for required in workflow/ containers/ plugins/ data/ offline/ manifests/ README.txt; do
  grep -Fq "${prefix}${required}" "$inventory_file" || {
    echo "missing required published path: ${required}" >&2
    exit 1
  }
done

"$AWS_BIN" s3api head-object --bucket "$bucket" --key "${prefix}README.txt" > "$metadata_file"
object_count="$(wc -l < "$inventory_file" | tr -d ' ')"
total_bytes="$(awk '{sum += $3} END {print sum + 0}' "$inventory_file")"
readme_size="$(jq -r '.ContentLength' "$metadata_file")"
readme_modified="$(jq -r '.LastModified' "$metadata_file")"

printf 'PUBLISH_URI=%s\n' "$PUBLISH_URI"
printf 'OBJECT_COUNT=%s\n' "$object_count"
printf 'TOTAL_BYTES=%s\n' "$total_bytes"
printf 'README_CONTENT_LENGTH=%s\n' "$readme_size"
printf 'README_LAST_MODIFIED=%s\n' "$readme_modified"
printf 'REQUIRED_BUNDLE_PATHS=PASS\n'
