#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PIPELINE="${PIPELINE:-nf-core/sarek}"
REVISION="${REVISION:-3.5.1}"
PROFILE="${PROFILE:-podman}"
SOURCE_MODE="${SOURCE_MODE:-public}"
: "${BUNDLE_ROOT:?BUNDLE_ROOT must name a fresh candidate directory}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

[ "$PIPELINE" = nf-core/sarek ] || {
  echo "PIPELINE must be nf-core/sarek" >&2
  exit 1
}
[ "$REVISION" = 3.5.1 ] || {
  echo "REVISION must be 3.5.1 for the approved candidate gate" >&2
  exit 1
}
[ "$PROFILE" = podman ] || {
  echo "PROFILE must be podman" >&2
  exit 1
}
[ "$SOURCE_MODE" = public ] || {
  echo "SOURCE_MODE must be public for the candidate gate" >&2
  exit 1
}

need nf-core
need nextflow
need jq
need gzip
need sha256sum

BUNDLE_ROOT="$(mkdir -p "$BUNDLE_ROOT" && cd "$BUNDLE_ROOT" && pwd)"
[ -z "$(find "$BUNDLE_ROOT" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
  echo "BUNDLE_ROOT must be empty: $BUNDLE_ROOT" >&2
  exit 1
}

mkdir -p "$BUNDLE_ROOT"/{workflow,plugins/nextflow-home,data/reads,data/refs,offline,manifests}

nf-core pipelines download "$PIPELINE" -r "$REVISION" \
  --outdir "$BUNDLE_ROOT/download" \
  --compress none \
  --container-system none \
  --download-configuration yes \
  --force

main_nf="$(find "$BUNDLE_ROOT/download" -mindepth 2 -maxdepth 2 -type f -name main.nf -print -quit)"
[ -n "$main_nf" ] || {
  echo "downloaded workflow has no main.nf" >&2
  exit 1
}
workflow_source="$(dirname "$main_nf")"
cp -a "$workflow_source/." "$BUNDLE_ROOT/workflow/"

cat > "$BUNDLE_ROOT/data/reads/synthetic_R1.fastq" <<'EOF'
@synthetic.1/1
ACGTACGTACGTACGTACGTACGTACGTACGT
+
IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
EOF
cat > "$BUNDLE_ROOT/data/reads/synthetic_R2.fastq" <<'EOF'
@synthetic.1/2
TGCATGCATGCATGCATGCATGCATGCATGCA
+
IIIIIIIIIIIIIIIIIIIIIIIIIIIIIIIII
EOF
gzip -n "$BUNDLE_ROOT/data/reads/synthetic_R1.fastq"
gzip -n "$BUNDLE_ROOT/data/reads/synthetic_R2.fastq"
cat > "$BUNDLE_ROOT/data/reads/samplesheet.csv" <<'EOF'
patient,sample,lane,fastq_1,fastq_2
synthetic,synthetic,1,data/reads/synthetic_R1.fastq.gz,data/reads/synthetic_R2.fastq.gz
EOF
cat > "$BUNDLE_ROOT/data/refs/synthetic.fa" <<'EOF'
>synthetic_chr1
ACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGTACGT
EOF
printf 'synthetic_chr1\t80\t16\t80\t81\n' > "$BUNDLE_ROOT/data/refs/synthetic.fa.fai"
cat > "$BUNDLE_ROOT/data/refs/synthetic.dict" <<'EOF'
@HD	VN:1.6	SO:unsorted
@SQ	SN:synthetic_chr1	LN:80
EOF

cat > "$BUNDLE_ROOT/offline/params_sarek_offline.json" <<'EOF'
{
  "input": "data/reads/samplesheet.csv",
  "outdir": null,
  "genome": null,
  "igenomes_ignore": true,
  "fasta": "data/refs/synthetic.fa",
  "fasta_fai": "data/refs/synthetic.fa.fai",
  "dict": "data/refs/synthetic.dict",
  "custom_config_base": null,
  "custom_config_version": null,
  "pipelines_testdata_base_path": null,
  "modules_testdata_base_path": null,
  "test_data_base": null,
  "validate_params": false,
  "step": "mapping",
  "tools": "strelka",
  "split_fastq": 0
}
EOF
cp "$SCRIPT_DIR/offline_test.conf" "$BUNDLE_ROOT/offline/offline_test.conf"

mapfile -t plugins < <(
  grep -RhoE "id '[^']+'" "$BUNDLE_ROOT/workflow" 2>/dev/null |
    sed -E "s/^id '([^']+)'$/\1/" | sort -u
)
[ "${#plugins[@]}" -gt 0 ] || {
  echo "no workflow plugins found" >&2
  exit 1
}
printf '%s\n' "${plugins[@]}" > "$BUNDLE_ROOT/manifests/plugins.txt"
for plugin in "${plugins[@]}"; do
  NXF_HOME="$BUNDLE_ROOT/plugins/nextflow-home" nextflow plugin install "$plugin"
done

export NXF_HOME="$BUNDLE_ROOT/plugins/nextflow-home"
export NXF_OFFLINE=true
export NXF_PLUGIN_AUTOINSTALL=false
(
  cd "$BUNDLE_ROOT"
  nextflow inspect "$BUNDLE_ROOT/workflow" \
    -profile "$PROFILE,offline_smoke" \
    -params-file "$BUNDLE_ROOT/offline/params_sarek_offline.json" \
    -c "$BUNDLE_ROOT/offline/offline_test.conf" \
    -format json
) > "$BUNDLE_ROOT/manifests/inspect.json"

jq -e '.processes | type == "array" and length > 0' \
  "$BUNDLE_ROOT/manifests/inspect.json" >/dev/null
jq -r '.processes[]? | .container? | select(type == "string" and length > 0)' \
  "$BUNDLE_ROOT/manifests/inspect.json" | sort -u > "$BUNDLE_ROOT/manifests/images.txt"
[ -s "$BUNDLE_ROOT/manifests/images.txt" ] || {
  echo "empty image inventory" >&2
  exit 1
}

printf 'source\tregistry\n' > "$BUNDLE_ROOT/manifests/image-registries.tsv"
quay_only=yes
while IFS= read -r image; do
  case "$image" in
    quay.io/*) registry=quay.io ;;
    *) registry="${image%%/*}"; quay_only=no ;;
  esac
  printf '%s\t%s\n' "$image" "$registry" >> "$BUNDLE_ROOT/manifests/image-registries.tsv"
done < "$BUNDLE_ROOT/manifests/images.txt"

image_count="$(wc -l < "$BUNDLE_ROOT/manifests/images.txt" | tr -d '[:space:]')"
registries="$(tail -n +2 "$BUNDLE_ROOT/manifests/image-registries.tsv" | cut -f2 | sort -u | paste -sd, -)"
printf 'PIPELINE=%s\n' "$PIPELINE" > "$BUNDLE_ROOT/manifests/result.env"
printf 'REVISION=%s\n' "$REVISION" >> "$BUNDLE_ROOT/manifests/result.env"
printf 'IMAGE_COUNT=%s\n' "$image_count" >> "$BUNDLE_ROOT/manifests/result.env"
printf 'IMAGE_REGISTRIES=%s\n' "$registries" >> "$BUNDLE_ROOT/manifests/result.env"
if [ "$quay_only" = yes ]; then
  printf 'QUAY_ONLY=PASS\nOFFLINE_SAFE=true\nRESULT=SUCCESS\n' >> "$BUNDLE_ROOT/manifests/result.env"
else
  printf 'QUAY_ONLY=FAIL\nOFFLINE_SAFE=false\nRESULT=BLOCKED\n' >> "$BUNDLE_ROOT/manifests/result.env"
fi
cat "$BUNDLE_ROOT/manifests/result.env"

[ "$quay_only" = yes ] || {
  echo "non-Quay image references are not offline-safe for this project" >&2
  exit 3
}

echo "No container pull, save, load, or task execution was performed."
