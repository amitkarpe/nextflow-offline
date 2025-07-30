# Task Template: Provision Two EC2 instances to demonstrate Nextflow Offline

**(Copy and fill out this section for each new task)**

## Task Details

*   **Repository:** https://github.com/amitkarpe/nextflow-offline
*   **Local Workspace:** /home/ec2-user/git/github/nextflow-offline
*   **Task Title:** demonstrate Nextflow Offline for scrnaseq
*   **Goal:** Have two ec2 instances. First will install all containers using internet (online) and copy then into s3 bucket which will be used by other ec2 instance (offline). Using docker load, all containers will be loaded and nextflow must able to run in offline mode.

*   **References:**
    *  Main guide: https://nf-co.re/docs/usage/getting_started/offline
    * "How to use nf-core pipelines without an internet connection." guide talks about singularity. But we need to support for docker and not singularity.
    * Using `nextflow inspect` command, we get list of all container for each process in a pipeline without running the pipeline.
    * Using this list need to download all containers/ docker images and save into S3 bucket using `docker save` command.
    * i.e. Need to have S3 bucket, where using rsync command copy all required docker images, plugins, assets, input data (or test-datasets) to run pipeline on other instance in offline mode.
   * Other (offline) ec2 instance must able to load all containers/ docker images using `docker load` command.
   * While running on offline ec2 instance using command like: `nxtflow run ${PIPELINE_MAIN_NF} \
    -profile docker \
    --input ${INPUT_SHEET} \
    --outdir ${OUTPUT_DIR} \
    -work-dir ${WORK_DIR} \
    -c cache_override.config \
    -offline \
    -resume`
    Need to provide all path, env variables, or might be need to modify docker / process names.
   **Preferences/Constraints:** 
   * Consider that offline instance don't have internet
   * Bucket will be mounted at /mnt/s3/
   * In next step need to test using AWS ECR Registry instead of local docker images. 

---

**(Instructions for Cursor AI - Do not modify below this line for the task)**

## AI Workflow Instructions

Okay Cursor, let's tackle the task defined above. Please follow this workflow precisely:

1.  **Acknowledge & Plan:**
    *   Read the "Task Details" section above carefully.
    *   State that you are starting the task: "[Task Title]".
    *   Briefly outline your plan, including the main files you expect to modify or create and the general sequence of steps (e.g., "1. Analyze reference scripts. 2. Add installation commands to `scripts/devops.sh`. 3. Create a test function/script. 4. Update README.").

2.  **Branch Creation:**
    *   Suggest a suitable branch name based on the task title (e.g., `feature/add-nextflow-support`).
    *   Ask me to create this branch locally using a `git checkout -b [suggested-branch-name]` command. Wait for confirmation or execution.

3.  **Implementation:**
    *   Based on your plan and the provided references, proceed with the necessary code changes.
    *   Request specific file edits (using `edit_file`) or provide code snippets incrementally.
    *   Consult the reference links/paths provided in "Task Details" as needed.
    *   If Makefiles are preferred and suitable, propose additions or modifications to a `Makefile`.
    *   Commit changes locally frequently after logical steps are completed. Propose clear commit messages (e.g., "feat: Add Nextflow installation command").

4.  **Documentation:**
    *   Identify or create relevant documentation (e.g., update `README.md`, add comments in scripts).
    *   Propose specific changes to documentation to explain the new functionality or installation steps.
    *   Commit documentation changes.

5.  **Testing:**
    *   Create a test script (e.g., `scripts/test_nextflow.sh`) or add a test function/target (e.g., in a Makefile) to verify the installation or functionality.
    *   The test should perform a basic check (e.g., run `nextflow --version`, `nf-core --version`).
    *   Propose the content for the test script/function.
    *   Commit testing additions.

6.  **Push Branch:**
    *   Once implementation, documentation, and testing additions are committed locally, propose the command to push the feature branch to the remote repository: `git push -u origin [feature-branch-name]`.

7.  **Create Pull Request:**
    *   Propose using the GitHub tool (`mcp_github_create_pull_request`) to create a **Draft Pull Request**.
    *   Specify the `head` branch (your feature branch), `base` branch (`main`), `owner` (`amitkarpe`), `repo` (`setup`).
    *   Suggest a clear PR Title (e.g., "feat: Add Nextflow and nf-core Installation").
    *   Suggest a brief PR body summarizing the changes and linking to this issue (if this `issues.md` is tracked as a GitHub issue, otherwise just summarize).
    *   Set `draft: true`.

8.  **Pause for User Review:**
    *   State clearly: "The feature branch `[feature-branch-name]` has been pushed and a draft Pull Request has been created. **I will now pause and wait for you (Amit Karpe) to review the code, test the changes thoroughly, and provide feedback or approval.**"
    *   Do not proceed further until explicitly told to.

9.  **Final Steps (After User Confirmation):**
    *   **Wait for explicit confirmation** from me (Amit Karpe) that the PR has been reviewed, tested, approved, and **merged into `main`**.
    *   Once confirmation of merge is received, if this task corresponds to a GitHub Issue, propose closing that specific issue using `mcp_github_update_issue` with `state: closed`.
    *   Conclude the task: "Task '[Task Title]' is complete and the corresponding issue (if applicable) has been closed."

**Remember to follow the general Cursor best practices:** Be specific in your requests, break down complex edits, and use the available tools appropriately.
