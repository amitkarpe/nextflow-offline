#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error when substituting.
set -o pipefail # Return value of a pipeline is the value of the last command to exit with a non-zero status

# --- Configuration ---
PIPELINE="nf-core/scrnaseq" # Specify the pipeline name (e.g., nf-core/rnaseq)
# PIPELINE_VERSION="3.14.0" # Optional: Specify a pipeline version
PROFILE="docker"           # Profile to use for inspection (docker/singularity)
S3_MOUNT_POINT="/mnt/s3"   # Mount point for the S3 bucket
CACHE_BASE_DIR="${S3_MOUNT_POINT}/nextflow-offline-cache" # Base directory in S3 for *assets*
ASSET_DIR="${CACHE_BASE_DIR}/assets" # Directory within cache for pipeline assets

# --- Output Configuration for Image List ---
# Directory to store the generated image list file (relative to current dir)
LIST_DIR="./pipeline_lists"
PIPELINE_SHORT_NAME=$(basename ${PIPELINE})
JSON_LIST_FILE="${LIST_DIR}/${PIPELINE_SHORT_NAME}.list.json"

# --- Ensure target directories exist ---
echo ">>> Ensuring asset directory exists: ${ASSET_DIR}..."
mkdir -p "${ASSET_DIR}"
echo ">>> Ensuring list directory exists: ${LIST_DIR}..."
mkdir -p "${LIST_DIR}"
echo ">>> Directories ensured."

# --- Dependency Checks (Basic) ---
command -v nextflow >/dev/null 2>&1 || { echo >&2 "Nextflow is required but not installed. Aborting."; exit 1; }
command -v nf-core >/dev/null 2>&1 || { echo >&2 "nf-core tools are required but not installed. Aborting."; exit 1; }
# aws cli check removed, assuming sync is handled elsewhere or S3 mount is sufficient

# --- Download Pipeline Assets and Test Data ---
echo ">>> Downloading pipeline assets and test data for ${PIPELINE} to ${ASSET_DIR}..."
# Using ASSET_DIR as outdir for nf-core download to place pipeline code there
nf-core download "${PIPELINE}" \
    --revision "${PIPELINE_VERSION:-}" \
    --outdir "${ASSET_DIR}" \
    --compress none \
    --container-system none \
    --force # Overwrite if exists
    # Add --download-configuration if needed for institutional profiles

echo ">>> Pipeline assets and test data downloaded to ${ASSET_DIR}."

# --- Generate Pipeline Image List (JSON) ---
echo ">>> Inspecting pipeline ${PIPELINE} to generate image list: ${JSON_LIST_FILE}..."
# Construct the inspect command, optionally adding version
INSPECT_CMD="nextflow inspect ${PIPELINE}"
# [ -n "${PIPELINE_VERSION:-}" ] && INSPECT_CMD="${INSPECT_CMD} -r ${PIPELINE_VERSION}"
INSPECT_CMD="${INSPECT_CMD} -profile ${PROFILE}"
# Add other necessary profiles if needed, e.g., -profile test,docker

# Generate the JSON list
${INSPECT_CMD} -format json > "${JSON_LIST_FILE}"

if [ $? -ne 0 ] || [ ! -s "${JSON_LIST_FILE}" ]; then
    echo "Error: Failed to generate image list file ${JSON_LIST_FILE} using 'nextflow inspect'." >&2
    # Clean up empty file potentially created on error
    [ -f "${JSON_LIST_FILE}" ] && rm -f "${JSON_LIST_FILE}"
    exit 1
fi

echo ">>> Image list generated: ${JSON_LIST_FILE}"

# --- Final Instructions ---
echo ">>> Asset download and image list generation complete."
echo ">>> Pipeline assets are in: ${ASSET_DIR}"
echo ">>> Image list for ${PIPELINE} is at: ${JSON_LIST_FILE}"
echo ""
echo "Next Step: Run the image fetching script, providing the generated list file:"
echo "  ./scripts/fetch_and_save_images.sh \"${JSON_LIST_FILE}\" \"/mnt/s3/pipe/images\""

exit 0 