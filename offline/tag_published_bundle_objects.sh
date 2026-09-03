#!/usr/bin/bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <s3://bucket/prefix/> <TTL:DD-MM-YY>" >&2
  exit 2
fi

PUBLISH_URI="${1%/}/"
PUBLISH_TTL="$2"
AWS_BIN="${AWS_BIN:-aws}"
TAG_WORKERS="${TAG_WORKERS:-8}"
PUBLISH_NAME="${PUBLISH_NAME:-issue-10-demo-bundle}"
PUBLISH_VERSION="${PUBLISH_VERSION:-1.0.2}"
PUBLISH_PHASE="${PUBLISH_PHASE:-issue-10}"
PUBLISH_CREATED="${PUBLISH_CREATED:-$(date +%F)}"

case "$PUBLISH_URI" in
  s3://*) ;;
  *) echo "publish URI must start with s3://: $PUBLISH_URI" >&2; exit 2 ;;
esac
case "$PUBLISH_TTL" in
  [0-3][0-9]-[0-1][0-9]-[0-9][0-9]) ;;
  *) echo "TTL must use DD-MM-YY: $PUBLISH_TTL" >&2; exit 2 ;;
esac
case "$TAG_WORKERS" in
  ''|*[!0-9]*|0) echo "TAG_WORKERS must be a positive integer" >&2; exit 2 ;;
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

tagging_json="$(jq -nc \
  --arg created "$PUBLISH_CREATED" \
  --arg name "$PUBLISH_NAME" \
  --arg version "$PUBLISH_VERSION" \
  --arg ttl "$PUBLISH_TTL" \
  --arg phase "$PUBLISH_PHASE" \
  '{TagSet: [
    {Key: "dev", Value: "amit"},
    {Key: "project", Value: "nextflow-offline"},
    {Key: "created", Value: $created},
    {Key: "tools", Value: "cdx"},
    {Key: "environment", Value: "dev"},
    {Key: "owner", Value: "amit"},
    {Key: "Name", Value: $name},
    {Key: "version", Value: $version},
    {Key: "TTL", Value: $ttl},
    {Key: "purpose", Value: "s3-publish-proof"},
    {Key: "phase", Value: $phase}
  ]}')"

inventory_file="$(mktemp "${TMPDIR:-/tmp}/nextflow-s3-tag-inventory.XXXXXX")"
trap 'rm -f "$inventory_file"' EXIT
"$AWS_BIN" s3api list-objects-v2 --bucket "$bucket" --prefix "$prefix" --output json > "$inventory_file"
object_count="$(jq -r '.KeyCount' "$inventory_file")"
[ "$object_count" -gt 0 ] || { echo "published prefix is empty: $PUBLISH_URI" >&2; exit 1; }

active=0
while IFS= read -r object_key; do
  "$AWS_BIN" s3api put-object-tagging \
    --bucket "$bucket" \
    --key "$object_key" \
    --tagging "$tagging_json" \
    --output text &
  active=$((active + 1))
  if [ "$active" -ge "$TAG_WORKERS" ]; then
    wait -n
    active=$((active - 1))
  fi
done < <(jq -r '.Contents[]?.Key' "$inventory_file")
while [ "$active" -gt 0 ]; do
  wait -n
  active=$((active - 1))
done

printf 'PUBLISH_URI=%s\n' "$PUBLISH_URI"
printf 'TAGGED_OBJECT_COUNT=%s\n' "$object_count"
printf 'TTL=%s\n' "$PUBLISH_TTL"
printf 'OBJECT_TAGGING=PASS\n'
