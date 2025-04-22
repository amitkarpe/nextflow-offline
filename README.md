# Nextflow Offline Execution Demo

This project provides scripts to demonstrate running Nextflow pipelines (specifically nf-core pipelines using Docker) in an environment without internet access, using a pre-populated cache stored in an S3 bucket.

## Goal

To enable running Nextflow pipelines on an "offline" machine (e.g., an EC2 instance in a private subnet with no internet gateway) by:
1.  Using an "online" machine to download the pipeline, its Docker container images, and test data.
2.  Saving these assets to a shared S3 bucket.
3.  Using the offline machine to load the assets from the S3 bucket and run the pipeline with the `-offline` flag.

## Prerequisites

*   **AWS Account & S3 Bucket:** You need an AWS account and an S3 bucket accessible by both the online and offline machines.
*   **AWS CLI:** Installed and configured with credentials on the online machine (for `aws s3 sync`).
*   **S3 Mount:** The S3 bucket must be mounted on *both* the online and offline machines at the *same* path: `/mnt/s3` (This path is configurable in the scripts).
    *   Tools like `s3fs-fuse` or the AWS Mountpoint for S3 can be used for this.
*   **Online Machine:** An internet-connected machine (e.g., EC2 instance) with:
    *   `bash`
    *   `Nextflow` installed.
    *   `nf-core` tools installed (`pip install nf-core`).
    *   `Docker` installed and running.
    *   `AWS CLI` installed and configured.
*   **Offline Machine:** A machine *without* internet access, but with access to the mounted S3 bucket (`/mnt/s3`), and with:
    *   `bash`
    *   `Nextflow` installed (can be transferred via S3 if necessary).
    *   `Docker` installed and running (can be transferred via S3 if necessary).

## Workflow

### 1. Online Instance: Setup Cache (`scripts/setup_online_cache.sh`)

This script prepares the offline cache in the mounted S3 bucket.

**Usage:**

```bash
# Ensure your S3 bucket is mounted at /mnt/s3

# Navigate to the project directory
cd /path/to/nextflow-offline

# Run the script
./scripts/setup_online_cache.sh
```

**What it does:**

1.  **Configuration:** Reads pipeline (`nf-core/scrnaseq`) and S3 mount point (`/mnt/s3`) from variables within the script.
2.  **Creates Directories:** Sets up the cache structure within `/mnt/s3/nextflow-offline-cache/` (images, assets, data).
3.  **Downloads Pipeline:** Uses `nf-core download` to fetch the pipeline code, assets, and test data into `/mnt/s3/nextflow-offline-cache/assets/`.
4.  **Inspects Images:** Uses `nextflow inspect` to find all required Docker image URIs for the pipeline and specified profile (`docker`).
5.  **Pulls & Saves Images:** Pulls each required Docker image using `docker pull` and saves it as a `.tar` file using `docker save` into a temporary local directory.
6.  **Syncs to S3:** Uses `aws s3 sync` to copy the saved `.tar` image files from the temporary directory to `/mnt/s3/nextflow-offline-cache/images/`. It also ensures the assets downloaded by `nf-core` are present.

After this script completes successfully, the `/mnt/s3/nextflow-offline-cache` directory should contain:
*   `images/`: Docker images saved as `.tar` files.
*   `assets/`: Pipeline code, nf-core assets, and test data.

### 2. Offline Instance: Run Pipeline (`scripts/run_nextflow_offline.sh`)

This script runs the Nextflow pipeline using the cache prepared by the online instance.

**Usage:**

```bash
# Ensure your S3 bucket is mounted at /mnt/s3
# Ensure Nextflow and Docker are installed

# Navigate to the project directory (can be copied via S3)
cd /path/to/nextflow-offline

# Run the script
./scripts/run_nextflow_offline.sh
```

**What it does:**

1.  **Configuration:** Reads S3 mount point and pipeline name from variables.
2.  **Locates Assets:** Finds the downloaded pipeline workflow (`main.nf`) and a test samplesheet within the `/mnt/s3/nextflow-offline-cache/assets/` directory.
3.  **Loads Images:** Iterates through all `.tar` files in `/mnt/s3/nextflow-offline-cache/images/` and loads them into the local Docker daemon using `docker load`.
4.  **Runs Nextflow:** Executes the `nextflow run` command:
    *   Targets the `main.nf` script found in the assets.
    *   Uses `-profile docker`.
    *   Uses the automatically located test `--input` sheet.
    *   Specifies local `--outdir` and `-work-dir`.
    *   Includes `-c config/cache_override.config` (though it's minimal by default).
    *   Critically, uses the `-offline` flag to prevent any internet access attempts by Nextflow.
    *   Uses `-resume`.
5.  **Checks Result:** Exits with 0 if Nextflow completes successfully, otherwise exits with Nextflow's error code.

## Configuration Files

*   `scripts/setup_online_cache.sh`: Contains variables for `PIPELINE`, `PROFILE`, `S3_MOUNT_POINT`, etc.
*   `scripts/run_nextflow_offline.sh`: Contains variables for `S3_MOUNT_POINT`, `PIPELINE_NAME`, paths for output/work directories.
*   `config/cache_override.config`: A Nextflow configuration file used via `-c`. Currently minimal, but can be used to override specific settings (e.g., process resources, plugin directories) for the offline environment if needed.

## Future Considerations

*   **Error Handling:** Add more robust error checking and dependency validation to the scripts.
*   **Configuration:** Make paths and pipeline names command-line arguments instead of hardcoded variables.
*   **Plugins:** Handle offline Nextflow plugins if required by the pipeline.
*   **ECR:** Explore using AWS ECR for caching images instead of saving/loading `.tar` files.
*   **Singularity:** Adapt the process for Singularity containers if needed. 