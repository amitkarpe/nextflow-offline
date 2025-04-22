#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
set -u # Treat unset variables as an error when substituting.
set -o pipefail # Return value of a pipeline is the value of the last command to exit with a non-zero status

# --- Configuration ---
PIPELINE="nf-core/scrnaseq" # Specify the pipeline name (e.g., nf-core/rnaseq)
# PIPELINE_VERSION="3.14.0" # Optional: Specify a pipeline version
PROFILE="docker"           # Profile to use for inspection (docker/singularity)
S3_MOUNT_POINT="/mnt/s3"   # Mount point for the S3 bucket
CACHE_BASE_DIR="${S3_MOUNT_POINT}/nextflow-offline-cache" # Base directory in S3 for offline assets

# Derived directories
IMAGE_DIR="${CACHE_BASE_DIR}/images"
ASSET_DIR="${CACHE_BASE_DIR}/assets"
DATA_DIR="${CACHE_BASE_DIR}/data"
TEMP_DIR=$(mktemp -d) # Temporary directory for saving images before sync

# --- Ensure target directories exist ---
echo ">>> Creating cache directories in ${CACHE_BASE_DIR}..."
mkdir -p "${IMAGE_DIR}"
mkdir -p "${ASSET_DIR}"
mkdir -p "${DATA_DIR}"
echo ">>> Cache directories created."

# --- Helper Functions ---
cleanup() {
    echo ">>> Cleaning up temporary directory: ${TEMP_DIR}"
    rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT # Register cleanup function to run on script exit

# Function to sanitize image names for filenames
sanitize_filename() {
    echo "$1" | tr '/:' '__'
}

# --- Dependency Checks (Basic) ---
# Add checks for nextflow, nf-core, docker, aws cli if needed
# command -v nextflow >/dev/null 2>&1 || { echo >&2 "Nextflow is required but not installed. Aborting."; exit 1; }
# command -v nf-core >/dev/null 2>&1 || { echo >&2 "nf-core tools are required but not installed. Aborting."; exit 1; }
# command -v docker >/dev/null 2>&1 || { echo >&2 "Docker is required but not installed. Aborting."; exit 1; }
# command -v aws >/dev/null 2>&1 || { echo >&2 "AWS CLI is required but not installed. Aborting."; exit 1; }


# --- Download Pipeline Assets and Test Data ---
echo ">>> Downloading pipeline assets and test data for ${PIPELINE}..."
# Using ASSET_DIR as outdir for nf-core download to place pipeline code there
nf-core download "${PIPELINE}" \
    --revision "${PIPELINE_VERSION:-}" \
    --outdir "${ASSET_DIR}" \
    --compress none \
    --container-system none \
    --force # Overwrite if exists
    # Add --download-configuration if needed for institutional profiles

# Note: nf-core download places test data *within* the downloaded pipeline directory structure
# We might want to move or symlink the test data to DATA_DIR if a cleaner separation is desired.
# For now, we'll assume the offline script knows where to find it within ASSET_DIR/<pipeline_name>
echo ">>> Pipeline assets and test data downloaded to ${ASSET_DIR}."


# --- Inspect Pipeline and Save Docker Images ---
echo ">>> Inspecting pipeline ${PIPELINE} to find Docker images..."
# Construct the inspect command, optionally adding version
INSPECT_CMD="nextflow inspect ${PIPELINE}"
# [ -n "${PIPELINE_VERSION:-}" ] && INSPECT_CMD="${INSPECT_CMD} -r ${PIPELINE_VERSION}"
INSPECT_CMD="${INSPECT_CMD} -profile ${PROFILE}"

# Get unique container image URIs
IMAGES=$(${INSPECT_CMD} | grep 'Container' | awk '{print $3}' | sort -u)

if [ -z "$IMAGES" ]; then
    echo >&2 "Error: Could not find any container images using 'nextflow inspect'. Check pipeline name and profile."
    exit 1
fi

echo ">>> Found the following images:"
echo "$IMAGES"

echo ">>> Pulling and saving Docker images to ${TEMP_DIR}..."
cd "${TEMP_DIR}" # Save images in temp dir first
SAVED_IMAGE_FILES=()
for IMAGE in ${IMAGES}; do
    echo "--- Processing image: ${IMAGE} ---"
    echo "Pulling..."
    docker pull "${IMAGE}"

    FILENAME=$(sanitize_filename "${IMAGE}").tar
    echo "Saving to ${FILENAME}..."
    docker save -o "${FILENAME}" "${IMAGE}"
    SAVED_IMAGE_FILES+=("${FILENAME}")
    echo "--- Done processing ${IMAGE} ---"
done
cd - > /dev/null # Return to previous directory

echo ">>> Docker images saved locally to ${TEMP_DIR}."

# --- Sync to S3 Cache ---
# Sync saved images
echo ">>> Syncing saved Docker images (.tar) to ${IMAGE_DIR}..."
# Using aws s3 sync - could also use rsync if S3 bucket is mounted locally and preferred
aws s3 sync "${TEMP_DIR}/" "${IMAGE_DIR}/" --exclude "*" --include "*.tar" --delete
# Alternatively, using rsync:
# rsync -avh --delete "${TEMP_DIR}/"*.tar "${IMAGE_DIR}/"
echo ">>> Image sync complete."

# Sync assets (downloaded by nf-core download)
# Note: nf-core download already placed these in the target ASSET_DIR.
# If we downloaded elsewhere, we would sync here.
# We might still run a sync to ensure consistency if the script is re-run
echo ">>> Ensuring assets in ${ASSET_DIR} are synced (nf-core download already placed them there)..."
# aws s3 sync "${ASSET_DIR}/" "${ASSET_DIR}/" --delete # Example if sync needed
echo ">>> Asset sync check complete."

# Sync data (part of nf-core download assets)
# If test data was moved to DATA_DIR, sync it here
# echo ">>> Syncing test data to ${DATA_DIR}..."
# aws s3 sync <path_to_test_data> "${DATA_DIR}/" --delete
# echo ">>> Data sync complete."


echo ">>> Online cache setup complete for ${PIPELINE}."
echo ">>> Cache located at: ${CACHE_BASE_DIR}"
echo ">>> Saved images are in: ${IMAGE_DIR}"
echo ">>> Pipeline assets/code are in: ${ASSET_DIR}"

exit 0 