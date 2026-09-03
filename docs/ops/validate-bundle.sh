#!/usr/bin/bash
set -euo pipefail
BUNDLE_ROOT="${1:?usage: validate-bundle.sh <bundle-root>}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }
need sha256sum
for rel in workflow/main.nf data/samplesheet.csv offline/params_offline.json offline/offline_test.conf offline/run.args offline/run.profile manifests/images.tsv manifests/files.sha256 manifests/release.env; do
  [[ -e "$BUNDLE_ROOT/$rel" ]] || { echo "missing: $rel" >&2; exit 1; }
done
(cd "$BUNDLE_ROOT" && sha256sum -c manifests/files.sha256)

while IFS=$'\t' read -r source mode artifact; do
  [[ "$source" == source || -z "$source" ]] && continue
  [[ "$mode" != archive || -f "$BUNDLE_ROOT/$artifact" ]] || { echo "missing archive: $artifact" >&2; exit 1; }
done < "$BUNDLE_ROOT/manifests/images.tsv"

if command -v nextflow >/dev/null 2>&1; then
  export NXF_HOME="$BUNDLE_ROOT/plugins/nextflow-home"
  export NXF_OFFLINE=true
  export NXF_PLUGIN_AUTOINSTALL=false
  (
    cd "$BUNDLE_ROOT"
    NXF_CONFIG_FILE="$BUNDLE_ROOT/offline/offline_test.conf" \
      nextflow config "$BUNDLE_ROOT/workflow" -flat
  ) > /tmp/nextflow-offline-config-flat.txt
  grep -E 'custom_config_base|pipelines_testdata_base_path|validate_params' /tmp/nextflow-offline-config-flat.txt || true
fi

echo "SUCCESS: bundle validation passed"
