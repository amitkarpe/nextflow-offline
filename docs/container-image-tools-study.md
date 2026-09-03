# Container image tools study for Phase 1

## Decision

For PR #6 Phase 1, keep the executable path **Podman + AWS CLI**.

- **Podman**: pull images, save portable archives, load archives, and run the offline validation.
- **Buildah**: useful when we need to build or modify an image; not required for copying existing nf-core images into the Phase 1 bundle.
- **Skopeo**: very useful for remote image inspect/copy/sync, especially registry-to-registry. It does **not** provide an S3 transport, so it cannot directly copy `docker://...` to `s3://...`.

Skopeo is therefore documented here as a proven historical pattern and future optimization, but is not added as a mandatory Phase 1 dependency.

## Historical repository evidence

### 1. `mytestlab123/pipeline`

Historical branch:

`next-action/pull-images-script`

File:

`pull-images.sh`

The old script already used Skopeo specifically to avoid the normal pull/tag/push workflow and copy an image directly between registries:

```bash
local skopeo_cmd=(
    docker run --rm
    -v "${HOME}/.docker:/root/.docker:ro"
    "${SKOPEO_IMAGE}"
    copy
    --dest-creds "${DOCKER_USER}:${DOCKER_PAT}"
    "docker://${source_image}"
    "docker://${dest_image}"
)
```

Source:

https://github.com/mytestlab123/pipeline/blob/next-action/pull-images-script/pull-images.sh

That script also validated the destination with Skopeo `inspect`.

### 2. `amitkarpe/rnaseq`

File:

`wave-to-quay.sh`

The same registry-to-registry pattern was used for Wave images:

```bash
docker run --rm \
  -v ~/.docker:/root/.docker \
  quay.io/skopeo/stable copy \
    --dest-creds "${QUAY_USER}:${QUAY_TOKEN}" \
    "docker://${SRC}" "docker://${DST}"
```

Source:

https://github.com/amitkarpe/rnaseq/blob/2142e8d76d1bd0f3d2593c275f4038b6ba509f03/wave-to-quay.sh

This proves that Skopeo has already been useful in this project family for **remote registry copy without first materializing the image in a Docker daemon**.

### 3. `amitkarpe/nextflow-offline`

The merged Sarek scaffold uses the more traditional Podman path:

```bash
podman pull "$image"
podman tag "$image" "$target"
podman push "$target"
```

Source:

https://github.com/amitkarpe/nextflow-offline/blob/d01e394c26382e8d6960199fbbbd1f39cfa7b763/offline/prepare_sarek_offline_test.sh

### 4. `amitkarpe/rnaseq` S3 pattern

The older `justfile` already separates bundle preparation from object-storage transfer:

```bash
aws s3 sync "$OFFLINE_DIR" "$S3_ROOT"
```

Source:

https://github.com/amitkarpe/rnaseq/blob/2142e8d76d1bd0f3d2593c275f4038b6ba509f03/justfile

## Current upstream capability check

The containers/image transport model shared by Skopeo, Buildah, and Podman supports transports such as:

- `docker://` registry
- `containers-storage:`
- `dir:`
- `oci:`
- `oci-archive:`
- `docker-archive:`

There is no native `s3:` transport.

Skopeo can therefore do this efficiently:

```text
registry -> registry
registry -> OCI/archive/local directory
local archive/layout -> registry
```

But not this directly:

```text
registry -> S3 bucket
```

For S3, an object-storage step is still required, for example `aws s3 cp` or `aws s3 sync`.

## Recommended Phase 1 image flow

Keep the first demonstration easy to understand:

```text
online server
    |
    | podman pull
    v
local image storage
    |
    | podman save --format oci-archive
    v
<bundle>/containers/*.tar
    |
    | aws s3 sync
    v
S3 offline bundle
```

Representative implementation pattern:

```bash
podman pull "$image"
podman save --format oci-archive \
  --output "$BUNDLE_ROOT/containers/$archive_name" \
  "$image"

aws s3 sync "$BUNDLE_ROOT/" "$S3_ROOT/"
```

Offline consumption remains simple:

```bash
aws s3 sync "$S3_ROOT/" "$BUNDLE_ROOT/"
podman load --input "$BUNDLE_ROOT/containers/$archive_name"
```

This makes the S3 bundle self-contained and keeps Phase 1 independent from an internal registry.

## Where Skopeo would help later

If a later phase uses a private registry such as ECR or Quay as the container destination, Skopeo is attractive because it can copy registry-to-registry without the explicit local `pull -> tag -> push` lifecycle.

Conceptually:

```bash
skopeo copy \
  "docker://$SOURCE_IMAGE" \
  "docker://$PRIVATE_REGISTRY_IMAGE"
```

It can also copy a registry image to a local OCI archive/layout before the AWS CLI uploads that file/tree to S3. That may reduce dependence on Podman local image storage, but it still does not remove the S3 copy step.

## Buildah role

Buildah should remain out of the Phase 1 dependency list unless the magic script must **build or modify** a container image.

For nf-core offline bundling we are primarily moving existing published images, not creating new images. Adding Buildah would therefore increase the tool surface without solving a Phase 1 requirement.

## Phase 1 rule

The magic script should remain parameter-driven and should not care whether a future image backend is S3 archives or a private registry.

For PR #6:

```text
container source   = upstream approved image
bundle format      = OCI archive files
bundle destination = local bundle + S3
runtime            = Podman
```

Skopeo/registry mirroring can be reconsidered in a later optimization milestone after the portable S3 bundle path is proven.