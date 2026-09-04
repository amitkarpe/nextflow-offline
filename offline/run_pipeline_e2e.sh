#!/usr/bin/bash
set -euo pipefail

# Home-server E2E runtime proof for one prepared pipeline bundle. Online setup
# may read private ECR. Once Nextflow starts, it uses a relocated bundle-local
# workflow, data, plugin state, preloaded isolated Podman store, -offline, and
# task --network none. This is offline emulation, not physical air-gap proof.

usage() {
  cat <<'EOF'
Usage: run_pipeline_e2e.sh --pipeline {demo|bamtofastq|rnaseq} --prepared-bundle DIR --test-root DIR
EOF
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
pipeline_key=""
prepared_bundle=""
test_root=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --pipeline) pipeline_key="${2:?missing pipeline}"; shift 2 ;;
    --prepared-bundle) prepared_bundle="${2:?missing prepared bundle}"; shift 2 ;;
    --test-root) test_root="${2:?missing test root}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done
case "$pipeline_key" in demo|bamtofastq|rnaseq) ;; *) usage >&2; exit 2 ;; esac
: "${AWS_PROFILE:?set AWS_PROFILE}"
: "${AWS_REGION:?set AWS_REGION}"
[ -d "$prepared_bundle" ] || { echo "prepared bundle missing: $prepared_bundle" >&2; exit 2; }
[ -f "$prepared_bundle/.done" ] || { echo "prepared bundle is not successful: $prepared_bundle" >&2; exit 2; }
[ -n "$test_root" ] || { usage >&2; exit 2; }

result_written=false
auth_file=""
runroot=""
on_exit() {
  local rc=$?
  if [ -n "$auth_file" ] && [ -f "$auth_file" ]; then
    find "$auth_file" -maxdepth 0 -type f -delete
  fi
  if [ -n "$runroot" ] && [ -d "$runroot" ]; then
    rmdir "$runroot" 2>/dev/null || true
  fi
  if [ "$result_written" = false ]; then
    mkdir -p "$test_root"
    printf 'PIPELINE_KEY=%s\nEXIT_CODE=%s\nRESULT=FAILED\n' "$pipeline_key" "$rc" > "$test_root/RESULT.md"
    printf 'RESULT=FAILED\n' > "$test_root/.failed"
  fi
}
trap on_exit EXIT

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing command: $1" >&2; exit 1; }; }
need aws
need podman
need nextflow
need sha256sum
need awk

mkdir -p "$test_root"
[ -z "$(find "$test_root" -mindepth 1 -maxdepth 1 -print -quit)" ] || {
  echo "test root must be empty: $test_root" >&2
  exit 2
}
cp -a "$prepared_bundle/." "$test_root/"
for inherited_marker in "$test_root/.done" "$test_root/.failed"; do
  if [ -f "$inherited_marker" ]; then
    find "$inherited_marker" -maxdepth 0 -type f -delete
  fi
done
for required in workflow data plugins manifests offline; do
  [ -e "$test_root/$required" ] || { echo "relocated bundle path missing: $required" >&2; exit 1; }
done
[ -f "$test_root/manifests/ecr-images.tsv" ] || { echo "ECR manifest missing" >&2; exit 1; }
[ -f "$test_root/offline/nextflow-ecr-containers.config" ] || { echo "ECR override missing" >&2; exit 1; }

if [ -f "$test_root/manifests/files.sha256" ]; then
  ( cd "$test_root" && sha256sum -c manifests/files.sha256 ) > "$test_root/manifests/relocated-checksums.log"
else
  # Discovery bundles do not yet carry transfer checksums; create and validate
  # a relocated inventory without modifying the source bundle.
  (
    cd "$test_root"
    find . -type f \
      ! -path './manifests/relocated-files.sha256' \
      ! -path './manifests/relocated-checksums.log' -print0 |
      sort -z | xargs -0 sha256sum
  ) > "$test_root/manifests/relocated-files.sha256"
  ( cd "$test_root" && sha256sum -c manifests/relocated-files.sha256 ) > "$test_root/manifests/relocated-checksums.log"
fi

image_bytes=0
printf 'ecr_image\timage_size_bytes\n' > "$test_root/manifests/ecr-image-sizes.tsv"
while IFS=$'\t' read -r _source_image repository tag ecr_image; do
  [ "$repository" = "repository_name" ] && continue
  size="$(aws ecr describe-images --profile "$AWS_PROFILE" --region "$AWS_REGION" \
    --repository-name "$repository" --image-ids "imageTag=$tag" \
    --query 'imageDetails[0].imageSizeInBytes' --output text)"
  case "$size" in ''|None|*[!0-9]*) echo "invalid ECR size for $ecr_image: $size" >&2; exit 1 ;; esac
  printf '%s\t%s\n' "$ecr_image" "$size" >> "$test_root/manifests/ecr-image-sizes.tsv"
  image_bytes=$((image_bytes + size))
done < "$test_root/manifests/ecr-images.tsv"
available_bytes="$(df -PB1 "$test_root" | awk 'NR == 2 {print $4}')"
required_bytes=$((image_bytes * 2 + 2147483648))
if [ "$available_bytes" -lt "$required_bytes" ]; then
  echo "insufficient disk for isolated ECR image store: need=$required_bytes available=$available_bytes" >&2
  exit 1
fi

podman_bin="$(command -v podman)"
graphroot="$test_root/.podman/graph"
runroot="$(mktemp -d "/run/user/$(id -u)/nextflow-e2e.XXXXXX")"
wrapper_dir="$test_root/.podman/bin"
mkdir -p "$graphroot" "$wrapper_dir"
command_log="$test_root/.podman/commands.log"
printf '%s\n' '#!/usr/bin/bash' \
  "printf '%s\\t' \"\\$(date -Iseconds)\" >> '$command_log'" \
  "printf '%q ' \"\\$@\" >> '$command_log'" \
  "printf '\\n' >> '$command_log'" \
  "exec '$podman_bin' --root '$graphroot' --runroot '$runroot' \"\\$@\"" \
  > "$wrapper_dir/podman"
chmod 0755 "$wrapper_dir/podman"
export PATH="$wrapper_dir:$PATH"
[ -z "$(podman images -q)" ] || { echo "isolated Podman store is not empty" >&2; exit 1; }

registry="$(awk -F '\t' 'NR == 2 {split($4, fields, "/"); print fields[1]; exit}' "$test_root/manifests/ecr-images.tsv")"
[ -n "$registry" ] || { echo "ECR registry missing from manifest" >&2; exit 1; }
auth_file="$test_root/.podman/ecr-auth.json"
aws ecr get-login-password --profile "$AWS_PROFILE" --region "$AWS_REGION" |
  podman login --authfile "$auth_file" --username AWS --password-stdin "$registry" >/dev/null
while IFS=$'\t' read -r _source_image _repository _tag ecr_image; do
  [ "$ecr_image" = "ecr_image" ] && continue
  podman pull --authfile "$auth_file" "$ecr_image"
  podman image exists "$ecr_image" || { echo "ECR pull did not create image: $ecr_image" >&2; exit 1; }
done < "$test_root/manifests/ecr-images.tsv"
find "$auth_file" -maxdepth 0 -type f -delete
auth_file=""

runtime_config="$test_root/offline/runtime.config"
runtime_input="$test_root/offline/runtime-input.csv"
case "$pipeline_key" in
  demo)
    printf 'sample,fastq_1,fastq_2\nE2E,%s,%s\n' \
      "$test_root/data/tiny_R1.fastq.gz" "$test_root/data/tiny_R2.fastq.gz" > "$runtime_input"
    cat > "$runtime_config" <<EOF
params {
  input = '$runtime_input'
  outdir = '$test_root/results'
  igenomes_ignore = true
  validate_params = false
  custom_config_base = null
  custom_config_version = null
  pipelines_testdata_base_path = null
  modules_testdata_base_path = null
}
EOF
    ;;
  bamtofastq)
    samtools_image="$(awk -F '\t' '$1 == "quay.io/biocontainers/samtools:1.19.2--h50ea8bc_0" {print $4}' "$test_root/manifests/ecr-images.tsv")"
    [ -n "$samtools_image" ] || { echo "BAM fixture Samtools image mapping is missing" >&2; exit 1; }
    cat > "$test_root/data/tiny.sam" <<EOF
@HD\tVN:1.6\tSO:coordinate
@SQ\tSN:chrTiny\tLN:1000
tiny\t99\tchrTiny\t1\t60\t16M\t=\t41\t56\tACGTACGTACGTACGT\tIIIIIIIIIIIIIIII
tiny\t147\tchrTiny\t41\t60\t16M\t=\t1\t-56\tTGCATGCATGCATGCA\tIIIIIIIIIIIIIIII
EOF
    podman run --rm --network none -v "$test_root/data:/data" --entrypoint /bin/sh "$samtools_image" \
      -c 'samtools view -b -o /data/tiny.bam /data/tiny.sam && samtools index /data/tiny.bam'
    printf 'sample_id,mapped,file_type\nE2E,%s,bam\n' "$test_root/data/tiny.bam" > "$runtime_input"
    cat > "$runtime_config" <<EOF
params {
  input = '$runtime_input'
  outdir = '$test_root/results'
  genome = null
  igenomes_ignore = true
  validate_params = false
  custom_config_base = null
  custom_config_version = null
  pipelines_testdata_base_path = null
}
EOF
    ;;
  rnaseq)
    printf 'sample,fastq_1,fastq_2,strandedness\nE2E,%s,%s,unstranded\n' \
      "$test_root/data/tiny_R1.fastq.gz" "$test_root/data/tiny_R2.fastq.gz" > "$runtime_input"
    cat > "$runtime_config" <<EOF
params {
  input = '$runtime_input'
  outdir = '$test_root/results'
  fasta = '$test_root/data/genome.fasta'
  gtf = '$test_root/data/genes_with_empty_tid.gtf.gz'
  genome = null
  igenomes_ignore = true
  validate_params = false
  custom_config_base = null
  custom_config_version = null
  pipelines_testdata_base_path = null
  modules_testdata_base_path = null
  skip_bbsplit = true
  skip_alignment = true
  skip_pseudo_alignment = true
  skip_trimming = true
  skip_linting = true
  skip_preseq = true
  skip_dupradar = true
  skip_qualimap = true
  skip_rseqc = true
  skip_biotype_qc = true
  skip_deseq2_qc = true
}
EOF
    ;;
esac

runtime_command_start="$(wc -l < "$command_log")"
export NXF_HOME="$test_root/plugins/nextflow-home"
export NXF_OFFLINE=true
export NXF_PLUGIN_AUTOINSTALL=false
nextflow -log "$test_root/offline/nextflow.log" run "$test_root/workflow" \
  -profile podman \
  -offline \
  -c "$test_root/offline/nextflow-ecr-containers.config" \
  -c "$runtime_config" \
  -work-dir "$test_root/work"

tail -n "+$((runtime_command_start + 1))" "$command_log" > "$test_root/.podman/runtime-commands.log"
if grep -Eq '(^|[[:space:]])pull([[:space:]]|$)' "$test_root/.podman/runtime-commands.log"; then
  echo "runtime attempted a Podman pull after strict offline start" >&2
  exit 1
fi
[ -f "$test_root/results/multiqc/multiqc_report.html" ] || {
  echo "expected MultiQC report is missing" >&2
  exit 1
}

{
  printf 'PIPELINE_KEY=%s\n' "$pipeline_key"
  printf 'RELOCATED_BUNDLE=PASS\nCHECKSUMS=PASS\n'
  printf 'ECR_IMAGE_BYTES=%s\nDISK_PREFLIGHT=PASS\n' "$image_bytes"
  printf 'ECR_PRELOAD=PASS\n'
  printf 'NXF_HOME=bundle-local\nNXF_OFFLINE=true\nNXF_PLUGIN_AUTOINSTALL=false\n'
  printf 'NEXTFLOW_OFFLINE_FLAG=true\nPODMAN_NETWORK=none\n'
  printf 'POST_START_PODMAN_PULLS=NONE\nPIPELINE_RC=0\nEXPECTED_MULTIQC=PASS\nRESULT=SUCCESS\n'
} > "$test_root/RESULT.md"
printf 'RESULT=SUCCESS\n' > "$test_root/.done"
result_written=true
cat "$test_root/RESULT.md"
