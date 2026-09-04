#!/usr/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PIPELINE="${PIPELINE:-nf-core/sarek}"
REVISION="${REVISION:-3.5.1}"
PROFILE="${PROFILE:-podman}"
SOURCE_MODE="${SOURCE_MODE:-public}"
PREVIEW_TIMEOUT_SECONDS="${PREVIEW_TIMEOUT_SECONDS:-180}"
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
need timeout

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
  "skip_tools": "baserecalibrator",
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
jq -r '
  .processes[]?
  | select(.name | type == "string")
  | [.name, (if (.container | type) == "string" then .container else "" end)]
  | @tsv
' "$BUNDLE_ROOT/manifests/inspect.json" | sort -u \
  > "$BUNDLE_ROOT/manifests/static-process-containers.tsv"
[ -s "$BUNDLE_ROOT/manifests/static-process-containers.tsv" ] || {
  echo "empty static process-to-container inventory" >&2
  exit 1
}

awk -F '\t' '$2 != "" { print $2 }' \
  "$BUNDLE_ROOT/manifests/static-process-containers.tsv" | sort -u \
  > "$BUNDLE_ROOT/manifests/static-images.txt"
[ -s "$BUNDLE_ROOT/manifests/static-images.txt" ] || {
  echo "empty static image inventory" >&2
  exit 1
}

printf 'source\tregistry\n' > "$BUNDLE_ROOT/manifests/static-image-registries.tsv"
static_quay_only=yes
while IFS= read -r image; do
  case "$image" in
    quay.io/*) registry=quay.io ;;
    *) registry="${image%%/*}"; static_quay_only=no ;;
  esac
  printf '%s\t%s\n' "$image" "$registry" >> "$BUNDLE_ROOT/manifests/static-image-registries.tsv"
done < "$BUNDLE_ROOT/manifests/static-images.txt"

static_image_count="$(wc -l < "$BUNDLE_ROOT/manifests/static-images.txt" | tr -d '[:space:]')"
static_registries="$(tail -n +2 "$BUNDLE_ROOT/manifests/static-image-registries.tsv" | cut -f2 | sort -u | paste -sd, -)"

preview_log="$BUNDLE_ROOT/manifests/preview.log"
preview_dag="$BUNDLE_ROOT/manifests/preview-dag.html"
preview_dag_source=requested-path
preview_rc=0
(
  cd "$BUNDLE_ROOT"
  timeout -k 15s "$PREVIEW_TIMEOUT_SECONDS" nextflow run "$BUNDLE_ROOT/workflow" \
    -profile "$PROFILE,offline_smoke" \
    -params-file "$BUNDLE_ROOT/offline/params_sarek_offline.json" \
    -c "$BUNDLE_ROOT/offline/offline_test.conf" \
    -offline \
    -preview \
    -with-dag "$preview_dag"
) > "$preview_log" 2>&1 || preview_rc=$?

if [ "$preview_rc" -ne 0 ] && grep -Fq 'Pipeline completed successfully' "$BUNDLE_ROOT/.nextflow.log"; then
  generated_preview_dag="$(find "$BUNDLE_ROOT/null/pipeline_info" -maxdepth 1 -type f \
    -name 'pipeline_dag_*.html' -print 2>/dev/null | sort | tail -n 1)"
  if [ -n "$generated_preview_dag" ] && [ -s "$generated_preview_dag" ]; then
    cp "$generated_preview_dag" "$preview_dag"
    preview_dag_source=pipeline-info-fallback
    preview_rc=0
  fi
fi

if [ "$preview_rc" -eq 0 ] && [ -s "$preview_dag" ]; then
  awk '
    function process_node(line, node) {
      node = line
      sub(/^[^[]*\[/, "", node)
      sub(/\].*/, "", node)
      return node
    }
    /^[[:space:]]*subgraph[[:space:]]+/ {
      label = $0
      sub(/^[[:space:]]*subgraph[[:space:]]+/, "", label)
      gsub(/^"|"$/, "", label)
      if (label == "NFCORE_SAREK") {
        active = 1
        depth = 1
        path[depth] = label
      }
      else if (active) {
        depth++
        path[depth] = label
      }
      next
    }
    active && /^[[:space:]]*end[[:space:]]*$/ {
      if (depth == 1) {
        active = 0
        depth = 0
      }
      else {
        delete path[depth]
        depth--
      }
      next
    }
    active && /^[[:space:]]*v[0-9]+\(\[[^]]+\]\)/ {
      full = path[1]
      for (i = 2; i <= depth; i++) full = full ":" path[i]
      print full ":" process_node($0)
    }
  ' "$preview_dag" | sort -u > "$BUNDLE_ROOT/manifests/active-processes.txt"

  [ -s "$BUNDLE_ROOT/manifests/active-processes.txt" ] || preview_rc=4
fi

if [ "$preview_rc" -ne 0 ]; then
  {
    printf 'PIPELINE=%s\nREVISION=%s\n' "$PIPELINE" "$REVISION"
    printf 'STATIC_IMAGE_COUNT=%s\nSTATIC_IMAGE_REGISTRIES=%s\n' "$static_image_count" "$static_registries"
    if [ "$static_quay_only" = yes ]; then printf 'STATIC_QUAY_ONLY=PASS\n'; else printf 'STATIC_QUAY_ONLY=FAIL\n'; fi
    printf 'PREVIEW_RC=%s\nPREVIEW_MODE=true\nPREVIEW_DAG_SOURCE=%s\nNEXTFLOW_OFFLINE_FLAG=true\n' "$preview_rc" "$preview_dag_source"
    printf 'PODMAN_ACTIONS=NONE_OBSERVED\nTASK_EXECUTION=NONE_OBSERVED\n'
    printf 'ACTIVE_IMAGE_COUNT=UNKNOWN\nQUAY_ONLY=UNKNOWN\n'
    printf 'OFFLINE_SAFE=UNKNOWN_PENDING\nRESULT=BLOCKED\n'
  } > "$BUNDLE_ROOT/manifests/result.env"
  cat "$BUNDLE_ROOT/manifests/result.env"
  echo "Preview DAG was unavailable; no active-path image conclusion was made." >&2
  exit 3
fi

awk -F '\t' '
  NR == FNR { count[$1]++; image[$1] = $2; next }
  {
    if (count[$1] != 1 || image[$1] == "") {
      print $1 >> unresolved
      next
    }
    print $1 "\t" image[$1]
  }
' unresolved="$BUNDLE_ROOT/manifests/unresolved-active-processes.txt" \
  "$BUNDLE_ROOT/manifests/static-process-containers.tsv" \
  "$BUNDLE_ROOT/manifests/active-processes.txt" \
  > "$BUNDLE_ROOT/manifests/active-process-containers.tsv"

if [ -s "$BUNDLE_ROOT/manifests/unresolved-active-processes.txt" ]; then
  {
    printf 'PIPELINE=%s\nREVISION=%s\n' "$PIPELINE" "$REVISION"
    printf 'STATIC_IMAGE_COUNT=%s\nSTATIC_IMAGE_REGISTRIES=%s\n' "$static_image_count" "$static_registries"
    if [ "$static_quay_only" = yes ]; then printf 'STATIC_QUAY_ONLY=PASS\n'; else printf 'STATIC_QUAY_ONLY=FAIL\n'; fi
    printf 'PREVIEW_RC=0\nPREVIEW_MODE=true\nPREVIEW_DAG_SOURCE=%s\nNEXTFLOW_OFFLINE_FLAG=true\n' "$preview_dag_source"
    printf 'PODMAN_ACTIONS=NONE_OBSERVED\nTASK_EXECUTION=NONE_OBSERVED\n'
    printf 'ACTIVE_IMAGE_COUNT=UNKNOWN\nQUAY_ONLY=UNKNOWN\n'
    printf 'OFFLINE_SAFE=UNKNOWN_PENDING\nRESULT=BLOCKED\n'
  } > "$BUNDLE_ROOT/manifests/result.env"
  cat "$BUNDLE_ROOT/manifests/result.env"
  echo "One or more active processes have no unique static container mapping." >&2
  exit 3
fi

awk -F '\t' '{ print $2 }' "$BUNDLE_ROOT/manifests/active-process-containers.tsv" | sort -u \
  > "$BUNDLE_ROOT/manifests/active-images.txt"
active_image_count="$(wc -l < "$BUNDLE_ROOT/manifests/active-images.txt" | tr -d '[:space:]')"
printf 'source\tregistry\n' > "$BUNDLE_ROOT/manifests/active-image-registries.tsv"
active_quay_only=yes
while IFS= read -r image; do
  case "$image" in
    quay.io/*) registry=quay.io ;;
    *) registry="${image%%/*}"; active_quay_only=no ;;
  esac
  printf '%s\t%s\n' "$image" "$registry" >> "$BUNDLE_ROOT/manifests/active-image-registries.tsv"
done < "$BUNDLE_ROOT/manifests/active-images.txt"
active_registries="$(tail -n +2 "$BUNDLE_ROOT/manifests/active-image-registries.tsv" | cut -f2 | sort -u | paste -sd, -)"

{
  printf 'PIPELINE=%s\nREVISION=%s\n' "$PIPELINE" "$REVISION"
  printf 'STATIC_IMAGE_COUNT=%s\nSTATIC_IMAGE_REGISTRIES=%s\n' "$static_image_count" "$static_registries"
  if [ "$static_quay_only" = yes ]; then printf 'STATIC_QUAY_ONLY=PASS\n'; else printf 'STATIC_QUAY_ONLY=FAIL\n'; fi
  printf 'PREVIEW_RC=0\nPREVIEW_MODE=true\nPREVIEW_DAG_SOURCE=%s\nNEXTFLOW_OFFLINE_FLAG=true\n' "$preview_dag_source"
  printf 'PODMAN_ACTIONS=NONE_OBSERVED\nTASK_EXECUTION=NONE_OBSERVED\n'
  printf 'ACTIVE_IMAGE_COUNT=%s\nACTIVE_IMAGE_REGISTRIES=%s\n' "$active_image_count" "$active_registries"
  if [ "$active_quay_only" = yes ]; then
    printf 'QUAY_ONLY=PASS\nOFFLINE_SAFE=true\nRESULT=SUCCESS\n'
  else
    printf 'QUAY_ONLY=FAIL\nOFFLINE_SAFE=false\nRESULT=BLOCKED\n'
  fi
} > "$BUNDLE_ROOT/manifests/result.env"
cat "$BUNDLE_ROOT/manifests/result.env"

echo "No container pull, save, load, or task execution was performed."
if [ "$active_quay_only" = yes ]; then
  printf 'RESULT=SUCCESS\n' > "$BUNDLE_ROOT/.done"
else
  printf 'RESULT=BLOCKED\n' > "$BUNDLE_ROOT/.blocked"
  exit 3
fi
