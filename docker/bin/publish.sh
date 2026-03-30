#!/usr/bin/env bash
# shellcheck disable=SC1091

# ./docker/bin/publish.sh \
#   stairwaytowonderland

echo "(ƒ) Preparing for Docker image publish (push)..." >&2

# ---------------------------------------
set -euo pipefail

if [ -z "$0" ]; then
    echo "(!) Cannot determine script path" >&2
    exit 1
fi

script_name="$0"
script_dir="$(cd "$(dirname "$script_name")" && pwd)"
# ---------------------------------------

# Parse first argument as IMAGE_NAME, second as REGISTRY_USER, third as IMAGE_VERSION
first_arg="${1-}"
[ -z "$first_arg" ] || shift

. "${script_dir}/loader.sh" "${script_dir}/.."

# ---------------------------------------

DEFAULT_TARGET="${DEFAULT_TARGET:-builder}"
LATEST_TARGET="${LATEST_TARGET:-$DEFAULT_TARGET}"
REGISTRY_HOST="${REGISTRY_HOST:-registry-1.docker.io}"

BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-ubuntu}"
BASE_IMAGE_VARIANT="${BASE_IMAGE_VARIANT:-latest}"
DEFAULT_PLATFORM="linux/$(uname -m)"
FILEZ_TARGET="${FILEZ_TARGET:-filez}"
[ "$BASE_IMAGE_VARIANT" = "latest" ] \
    && BASE_IMAGE_REF="$BASE_IMAGE_NAME" \
    || BASE_IMAGE_REF="${BASE_IMAGE_VARIANT}"

REGISTRY_PROVIDER="${REGISTRY_PROVIDER:-Docker Hub}"
REGISTRY_PROVIDER_FQDN="${REGISTRY_PROVIDER_FQDN:-hub.docker.com}"
REPO_NAMESPACE="${REPO_NAMESPACE-}"
REPO_NAME="${REPO_NAME-}"

# Determine IMAGE_NAME
IMAGE_NAME=${first_arg:-$REPO_NAME}
if [ -z "$IMAGE_NAME" ]; then
    echo "Usage: $0 <image-name[:build_target]> [registry-username] [image-version]" >&2
    exit 1
fi
if [ -n "${IMAGE_NAME##*:}" ] && [ "${IMAGE_NAME##*:}" != "$IMAGE_NAME" ]; then
    DOCKER_TARGET="${IMAGE_NAME##*:}"
    IMAGE_NAME="${IMAGE_NAME%%:*}"
fi
DOCKER_TARGET="${DOCKER_TARGET:-$DEFAULT_TARGET}"
# Determine REGISTRY_USER
if [ $# -gt 0 ]; then
    REGISTRY_USER="${1:-$REGISTRY_USER}"
    shift
fi
# Determine IMAGE_VERSION
if [ $# -gt 0 ]; then
    IMAGE_VERSION="${1-}"
    shift
fi
IMAGE_VERSION="${IMAGE_VERSION:-latest}"

TAG_SUFFIX="${TAG_SUFFIX:-$DOCKER_TARGET}"
[ -n "${TAG_PREFIX-}" ] && TAG_SUFFIX="$DOCKER_TARGET" || TAG_PREFIX="$DOCKER_TARGET"
title_prefix="${REPO_NAME} - ${DOCKER_TARGET}"
if [ "$DOCKER_TARGET" = "$FILEZ_TARGET" ]; then
    build_tag="${TAG_PREFIX}"
    docker_tag="${IMAGE_NAME}:${build_tag}"
else
    title_suffix=" - ${BASE_IMAGE_NAME} - ${BASE_IMAGE_VARIANT}"
    build_tag="${IMAGE_NAME}:${BASE_IMAGE_REF}"
    if [ "$BASE_IMAGE_VARIANT" = "latest" ] || [ -n "$TAG_PREFIX" ]; then
        tag_prefix="${IMAGE_NAME}:${TAG_PREFIX}"
        build_tag="${tag_prefix}-${BASE_IMAGE_REF}"
    fi

    if [ "$TAG_PREFIX" = "latest" ]; then
        build_tag="${IMAGE_NAME}:${BASE_IMAGE_REF}"
    fi

    [ "$TAG_SUFFIX" = "$DEFAULT_TARGET" ] || build_tag="${build_tag}-${TAG_SUFFIX}"

    [ "$IMAGE_VERSION" = "latest" ] || build_tag="${build_tag}-${IMAGE_VERSION}"

    if [ "$DOCKER_TARGET" = "$LATEST_TARGET" ] && [ "${LATEST:-false}" = "true" ]; then
        LATEST_TAG="${IMAGE_NAME}:latest"
        build_tag="$LATEST_TAG"
    fi

    docker_tag="$build_tag"
fi

# * Registry login happens here
if ! . "${script_dir}/login.sh" "${REGISTRY_USER:-$REPO_NAMESPACE}" "$REPO_NAME"; then
    echo "Error: Not logged in to ${REGISTRY_PROVIDER} Container Registry." >&2
    exit 1
elif [ -z "$REGISTRY_URL_PREFIX" ]; then
    echo "Error: REGISTRY_URL_PREFIX is not set." >&2
    exit 1
fi

REGISTRY_URL="${REGISTRY_URL_PREFIX}/${docker_tag}"

capitalize() {
    printf "%s" "$1" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}' | tr -d '\n'
}

lowercase() {
    printf "%s" "$1" | tr '[:upper:]' '[:lower:]' | tr -d '\n'
}

build_date() {
    echo "(+) Retrieving build date from image: $1" >&2
    (
        set -x
        docker inspect -f '{{.Created}}' "$(docker images --no-trunc -q -f reference="$1")"
    )
    echo -e "\033[2m~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\033[0m" >&2
}

IFS="," read -r -a platforms <<< "${PLATFORM:-$DEFAULT_PLATFORM}"
description_arch=""
title_arch=""
multiarch=false
annotation_prefix="index:"
if [ ${#platforms[*]} -gt 1 ]; then
    multiarch=true
    annotation_prefix="index:"
    # if echo "${platforms[*]}" | grep -q "linux/amd64"; then
    #     #     annotation_prefix="manifest[linux/amd64]:"
    #     description_arch="Built for AMD64."
    #     title_arch=" - AMD64"
    # elif echo "${platforms[*]}" | grep -q "linux/arm64"; then
    #     #     annotation_prefix="manifest[linux/arm64]:"
    #     description_arch="Built for ARM64."
    #     title_arch=" - ARM64"
    # fi
fi

base_image_name_cap="$(capitalize "$BASE_IMAGE_NAME")"
image_title="${title_prefix}${title_suffix-}"
repo_source="https://${REGISTRY_PROVIDER_FQDN}/${REPO_NAMESPACE}/${REPO_NAME}"
revision="$(git -C "${script_dir}/../.." rev-parse HEAD)"
description_url="${repo_source}/blob/main/docker"
description_image="Built from \`${BASE_IMAGE_NAME}:${BASE_IMAGE_VARIANT}\`."
description_docs="For documentation and source, visit: ${description_url}"
if [ "$multiarch" = "true" ]; then
    description_prefix="This multiarch ${base_image_name_cap:-Debian}-based"
else
    description_prefix="This ${base_image_name_cap:-Debian}-based"
fi
image_description=$(
    {
        cat <<- EOF
${description_prefix:-This}
Docker image is part of the **${REPO_NAME}** collection of container images.
${description_image}
${description_arch}
${description_docs}
EOF
    } | xargs echo
)

if [ "${BUILDX_PUSH:-true}" != "true" ]; then
    echo "(∫) Publishing Docker image to ${REGISTRY_PROVIDER} Container Registry..." >&2
    com=(docker push)
    com+=("$REGISTRY_URL")

    set -- "${com[@]}"
    . "${script_dir}/executer.sh" "$@"

    if [ -z "${LATEST_TAG-}" ] && [ "$DOCKER_TARGET" = "$LATEST_TARGET" ] && [ "${LATEST:-false}" = "true" ]; then
        latest_tag="${IMAGE_NAME}:latest"
        REGISTRY_URL="${REGISTRY_URL_PREFIX}/${latest_tag}"

        echo "(*) Tagging with 'latest'..." >&2
        tag_image "$build_tag" "$REGISTRY_URL"

        com=(docker push)
        com+=("$REGISTRY_URL")

        set -- "${com[@]}"
        . "${script_dir}/executer.sh" "$@"
    fi
fi

remove_danglers() {
    echo "(+) Removing dangling Docker images..." >&2
    (
        set -x
        docker images \
            --filter label="org.opencontainers.image.ref.name=${1}" \
            --filter dangling=true -q \
            | xargs -r docker rmi
    )
    echo -e "\033[2m~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\033[0m" >&2
}

remove_danglers "$build_tag"

echo "(∫) Adding annotations to ${REGISTRY_URL} ..." >&2

# Add OCI annotations to the image manifest
# https://docs.docker.com/reference/cli/docker/buildx/imagetools/
# https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry#labelling-container-images
# https://github.com/opencontainers/image-spec/blob/main/annotations.md#pre-defined-annotation-keys
com=(docker buildx imagetools create)
com+=("-t" "${REGISTRY_URL}")
# https://specs.opencontainers.org/image-spec/annotations/
com+=("--annotation" "${annotation_prefix}org.opencontainers.image.description=${image_description//\\\`/\`}")
com+=("--annotation" "${annotation_prefix}org.opencontainers.image.title=${image_title%.}${title_arch# }")
com+=("--annotation" "${annotation_prefix}org.opencontainers.image.source=${repo_source}")
if [ "$(lowercase "$REGISTRY_PROVIDER")" = "github" ]; then
    github_pkg_url="${repo_source}/pkgs/container/${repo_source##*/}"
    github_pkg_doc="${repo_source}/blob/main/docker/README.md"
    com+=("--annotation" "${annotation_prefix}org.opencontainers.image.url=${github_pkg_url}")
    com+=("--annotation" "${annotation_prefix}org.opencontainers.image.documentation=${github_pkg_doc}")
fi
com+=("--annotation" "${annotation_prefix}org.opencontainers.image.version=${build_tag##*:}")
com+=("--annotation" "${annotation_prefix}org.opencontainers.image.revision=${revision}")
com+=("--annotation" "${annotation_prefix}org.opencontainers.image.created=$(build_date "$build_tag")")
com+=("--annotation" "${annotation_prefix}org.opencontainers.image.vendor=${REPO_NAMESPACE}")
com+=("--annotation" "${annotation_prefix}org.opencontainers.image.base.name=${BASE_IMAGE_NAME}")
com+=("--annotation" "${annotation_prefix}org.opencontainers.image.base.variant=${BASE_IMAGE_VARIANT}")
com+=("--annotation" "${annotation_prefix}org.opencontainers.image.licenses=MIT")
com+=("$REGISTRY_URL")

set -- "${com[@]}"
. "${script_dir}/executer.sh" "$@"

# Pull the manifest to ensure local availability
# echo "Pulling the published Docker image manifest to ensure local availability..."
# pull_com=(docker pull)
# pull_com+=("$REGISTRY_URL")

# set -- "${pull_com[@]}"
# . "${script_dir}/executer.sh" "$@"

echo "(√) Done! Docker image publishing complete." >&2
# echo "_______________________________________" >&2
echo >&2
