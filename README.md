# Nextflow Offline Execution Demo

This project provides scripts to demonstrate running Nextflow pipelines (specifically nf-core pipelines using Docker) in an environment without internet access, using a pre-populated cache stored in an S3 bucket.

## Goal

To enable running Nextflow pipelines on an "offline" machine (e.g., an EC2 instance in a private subnet with no internet gateway) by:
1.  Using an "online" machine to download the pipeline assets and generate a list of required Docker images.
2.  Using the "online" machine again with the generated list to pull the Docker images and save them to a shared S3 location.
3.  Using the offline machine to load the assets and images from S3 and run the pipeline with the `-offline` flag.

## Prerequisites

*   **AWS Account & S3 Bucket:** You need an AWS account and an S3 bucket accessible by both the online and offline machines.
*   **S3 Mount:** The S3 bucket must be mounted on *both* the online and offline machines at the *same* path: `/mnt/s3` (This path is configurable in the scripts).
    *   Tools like `s3fs-fuse` or the AWS Mountpoint for S3 can be used for this.
*   **Online Machine:** An internet-connected machine (e.g., EC2 instance) with:
    *   `bash`
    *   `Nextflow` installed.
    *   `nf-core` tools installed (`pip install nf-core`).
    *   `Docker` installed and running.
    *   `jq` installed (for parsing the JSON image list, e.g., `sudo apt-get install jq` or `sudo yum install jq`).
    *   (Optional: `AWS CLI` if using S3 sync within scripts, though current scripts assume direct write to mount point for images).
*   **Offline Machine:** A machine *without* internet access, but with access to the mounted S3 bucket (`/mnt/s3`), and with:
    *   `bash`
    *   `Nextflow` installed (can be transferred via S3 if necessary).
    *   `Docker` installed and running (can be transferred via S3 if necessary).

## Workflow

### 1. Online Instance: Setup Assets & Image List (`scripts/setup_online_cache.sh`)

This script prepares the pipeline assets and generates a list of required Docker images.

**Usage:**

```bash
# Ensure your S3 bucket is mounted at /mnt/s3

# Navigate to the project directory
cd /path/to/nextflow-offline

# Run the script
./scripts/setup_online_cache.sh
```

**What it does:**

1.  **Configuration:** Reads pipeline (`nf-core/scrnaseq`) and S3 mount point (`/mnt/s3`) for assets from variables.
2.  **Creates Directories:** Ensures the asset cache directory (`/mnt/s3/nextflow-offline-cache/assets/`) and local list directory (`./pipeline_lists/`) exist.
3.  **Downloads Pipeline Assets:** Uses `nf-core download` to fetch the pipeline code, configuration, and test data into `/mnt/s3/nextflow-offline-cache/assets/`.
4.  **Generates Image List:** Uses `nextflow inspect` for the specified pipeline and profile (`docker`) to generate a JSON file (`./pipeline_lists/<pipeline_name>.list.json`) containing the URIs of all required Docker containers.
5.  **Outputs Next Step:** Prints the command needed to run the image fetching script using the generated list.

### 2. Online Instance: Fetch & Save Images (`scripts/fetch_and_save_images.sh`)

This script reads the generated JSON list, pulls the Docker images, and saves them to the designated S3 image cache directory.

**Usage (run after `setup_online_cache.sh`):**

```bash
# Ensure your S3 bucket is mounted at /mnt/s3

# Navigate to the project directory
cd /path/to/nextflow-offline

# Make the script executable if you haven't already
# chmod +x ./scripts/fetch_and_save_images.sh

# Run the script, providing the list file and the target image directory
# (Use the exact command printed by the previous script)
./scripts/fetch_and_save_images.sh "./pipeline_lists/scrnaseq.list.json" "/mnt/s3/pipe/images"
```

**What it does:**

1.  **Parses List:** Reads the specified JSON file (e.g., `./pipeline_lists/scrnaseq.list.json`) using `jq` to extract unique container image URIs.
2.  **Ensures Directory:** Creates the target image directory (`/mnt/s3/pipe/images`) if it doesn't exist.
3.  **Pulls & Saves Images:** For each unique image URI:
    *   Pulls the image using `docker pull`.
    *   Sanitizes the image URI into a valid filename (replacing `/` and `:` with `_`).
    *   Saves the pulled image as a `.tgz` file (e.g., `quay.io_biocontainers_fastqc_0.12.1--hdfd78af_0.tgz`) directly into the target directory (`/mnt/s3/pipe/images`).

After this script completes successfully, the `/mnt/s3/pipe/images` directory should contain the required Docker images saved as `.tgz` files.

### 3. Offline Instance: Run Pipeline (`scripts/run_nextflow_offline.sh`)

This script runs the Nextflow pipeline using the assets and images prepared by the online instance scripts.

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

1.  **Configuration:** Reads S3 mount point, pipeline name, asset cache path (`/mnt/s3/nextflow-offline-cache/assets/`), and image cache path (`/mnt/s3/pipe/images`) from variables.
2.  **Locates Assets:** Finds the downloaded pipeline workflow (`main.nf`) and a test samplesheet within the asset cache directory.
3.  **Loads Images:** Iterates through all `.tgz` files in the image cache directory (`/mnt/s3/pipe/images`) and loads them into the local Docker daemon using `docker load`.
4.  **Runs Nextflow:** Executes the `nextflow run` command:
    *   Targets the `main.nf` script found in the assets.
    *   Uses `-profile docker`.
    *   Uses the automatically located test `--input` sheet.
    *   Specifies local `--outdir` and `-work-dir`.
    *   Includes `-c config/cache_override.config`.
    *   Critically, uses the `-offline` flag.
    *   Uses `-resume`.
5.  **Checks Result:** Exits with 0 if Nextflow completes successfully, otherwise exits with Nextflow's error code.

## Configuration Files

*   `scripts/setup_online_cache.sh`: Contains variables for `PIPELINE`, `PROFILE`, asset `S3_MOUNT_POINT`, etc. Generates the image list file.
*   `scripts/fetch_and_save_images.sh`: Takes image list file and output directory as arguments.
*   `scripts/run_nextflow_offline.sh`: Contains variables for asset and image cache paths on `S3_MOUNT_POINT`, `PIPELINE_NAME`, output/work directories.
*   `config/cache_override.config`: A Nextflow configuration file used via `-c`. Currently minimal, but can be used to override specific settings for the offline environment if needed.

## Future Considerations

*   **Error Handling:** Add more robust error checking and dependency validation.
*   **Configuration:** Make paths and pipeline names command-line arguments.
*   **Plugins:** Handle offline Nextflow plugins.
*   **ECR:** Explore using AWS ECR instead of saving/loading `.tgz` files.
*   **Singularity:** Adapt the process for Singularity containers.

## Agent Workflow

For repository work, read [AGENTS.md](AGENTS.md), [CONTEXT.md](CONTEXT.md),
and [SPEC.md](SPEC.md) first. The next planned proof is one offline Sarek happy
path; the existing scripts currently describe the `scrnaseq` demonstration.
Reusable repository guidance is available in
[Agent OS](https://github.com/amitkarpe/agent-os).
