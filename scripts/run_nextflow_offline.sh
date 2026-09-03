#!/usr/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error when substituting.
set -o pipefail # Return value of a pipeline is the value of the last command to exit with a non-zero status

# --- Asset Configuration (Should align with setup_online_cache.sh) ---
PIPELINE_NAME="scrnaseq" # Just the pipeline name (e.g., scrnaseq), used to find assets
S3_MOUNT_POINT="/mnt/s3" # Mount point for the S3 bucket
# Base directory where pipeline *assets* were downloaded (nf-core download)
ASSET_CACHE_BASE_DIR="${S3_MOUNT_POINT}/nextflow-offline-cache"
ASSET_DIR="${ASSET_CACHE_BASE_DIR}/assets"

# --- Image Configuration (Should align with fetch_and_save_images.sh) ---
# Base directory where legacy .tgz and current .tar image archives are saved
IMAGE_CACHE_DIR="${S3_MOUNT_POINT}/pipe/images"

# Derived directories/paths for assets
PIPELINE_WORKFLOW_DIR=$(find "${ASSET_DIR}" -maxdepth 2 -type d -name "${PIPELINE_NAME}" -print -quit)
if [ -z "${PIPELINE_WORKFLOW_DIR}" ]; then
    echo "Error: Could not find downloaded pipeline directory for '${PIPELINE_NAME}' within ${ASSET_DIR}" >&2
    exit 1
fi
PIPELINE_MAIN_NF="${PIPELINE_WORKFLOW_DIR}/main.nf" # Path to the main workflow script

# --- Configuration for the Run ---
OUTPUT_DIR="./results"     # Output directory for the pipeline run
WORK_DIR="./work"         # Work directory for Nextflow
CONFIG_FILE="./config/cache_override.config" # Relative path to the override config

# Find the test profile input sheet (adjust pattern if needed)
# Common patterns: test.csv, test_full.csv, samplesheet.csv within testdata
INPUT_SHEET=$(find "${PIPELINE_WORKFLOW_DIR}/tests/test_data/" -name '*samplesheet*.csv' -print -quit)
if [ -z "${INPUT_SHEET}" ]; then
    # Fallback: Check for common names directly in the workflow dir or testdata root
    INPUT_SHEET=$(find "${PIPELINE_WORKFLOW_DIR}/" -maxdepth 2 \( -name 'samplesheet.csv' -o -name 'test.csv' -o -name 'test_full.csv' \) -print -quit)
fi

if [ -z "${INPUT_SHEET}" ]; then
    echo "Error: Could not automatically find a test input samplesheet CSV within ${PIPELINE_WORKFLOW_DIR}. Please specify manually." >&2
    # You might want to add a command-line argument to specify this instead of exiting
    exit 1
fi
echo "Using input sheet: ${INPUT_SHEET}"


# --- Dependency Checks (Basic) ---
# Assume nextflow and docker are pre-installed on the offline machine
command -v nextflow >/dev/null 2>&1 || { echo >&2 "Nextflow is required but not installed. Aborting."; exit 1; }
command -v docker >/dev/null 2>&1 || { echo >&2 "Docker is required but not installed. Aborting."; exit 1; }

# --- Load Docker Images from Cache ---
echo ">>> Loading Docker images from ${IMAGE_CACHE_DIR}..."
IMAGES_LOADED=0
IMAGES_FAILED=0
shopt -s nullglob # Prevent loop from running if no files match
IMAGE_ARCHIVES=("${IMAGE_CACHE_DIR}"/*.tar "${IMAGE_CACHE_DIR}"/*.tgz)
for IMAGE_ARCHIVE in "${IMAGE_ARCHIVES[@]}"; do
    # nullglob ensures the loop body does not run when neither format exists.
    echo "--- Loading image from: ${IMAGE_ARCHIVE} ---"
    if docker load < "${IMAGE_ARCHIVE}"; then
        echo "--- Successfully loaded ${IMAGE_ARCHIVE} ---"
        IMAGES_LOADED=$((IMAGES_LOADED + 1))
    else
        echo "--- ERROR loading ${IMAGE_ARCHIVE} ---"
        IMAGES_FAILED=$((IMAGES_FAILED + 1))
    fi
done
shopt -u nullglob # Turn off nullglob

echo ">>> Finished loading images. Loaded: ${IMAGES_LOADED}, Failed: ${IMAGES_FAILED}."
if [ "${IMAGES_FAILED}" -gt 0 ]; then
    echo "Error: Failed to load one or more Docker images. Aborting." >&2
    exit 1
fi
if [ "${IMAGES_LOADED}" -eq 0 ]; then
    # No supported archives may be valid for a container-free pipeline.
    # If files existed but all failed to load, that's definitely an error (covered above).
    if [ "${#IMAGE_ARCHIVES[@]}" -eq 0 ]; then
        echo "Warning: No Docker image .tar or .tgz files found in ${IMAGE_CACHE_DIR}. Assuming pipeline does not require containers or they are already loaded."
    else
        # This case shouldn't be reached if IMAGES_FAILED check works, but added for robustness
        echo "Warning: Found supported image archives but failed to load any. Pipeline might fail." >&2
    fi
    # Consider exiting based on requirements
    # exit 1
fi

# --- Run Nextflow Pipeline Offline ---
echo ">>> Starting Nextflow pipeline run in offline mode..."
echo "Pipeline: ${PIPELINE_MAIN_NF}"
echo "Input: ${INPUT_SHEET}"
echo "Output Dir: ${OUTPUT_DIR}"
echo "Work Dir: ${WORK_DIR}"
echo "Config: ${CONFIG_FILE}"

NXF_OPTS="-Xms1g -Xmx4g" # Optional: Adjust JVM options if needed
export NXF_OPTS

nextflow run "${PIPELINE_MAIN_NF}" \
    -profile docker \
    --input "${INPUT_SHEET}" \
    --outdir "${OUTPUT_DIR}" \
    -work-dir "${WORK_DIR}" \
    -c "${CONFIG_FILE}" \
    -offline \
    -resume

RUN_EXIT_CODE=$?

# --- Basic Test/Verification ---
if [ ${RUN_EXIT_CODE} -eq 0 ]; then
    echo "✅ Nextflow pipeline completed successfully (Exit Code 0)."
    # Add more specific checks if needed, e.g., check for expected output files
    # if [ -f "${OUTPUT_DIR}/some_expected_output.txt" ]; then
    #    echo "✅ Found expected output file."
    # else
    #    echo "❌ ERROR: Expected output file not found!"
    #    exit 1
    # fi
    exit 0
else
    echo "❌ ERROR: Nextflow pipeline failed with Exit Code ${RUN_EXIT_CODE}."
    exit ${RUN_EXIT_CODE}
fi
