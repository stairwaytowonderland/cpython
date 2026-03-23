#!/usr/bin/env bash
# shellcheck disable=SC1091

# ./docker/bin/build.sh \
#   cpython \
#   --build-arg USERNAME=appuser \
#   --build-arg PYTHON_VERSION=3.14 \
#   --no-cache
#   --progress=plain
#   .

echo "(ƒ) Preparing for Docker image build..." >&2

# ---------------------------------------
set -euo pipefail

if [ -z "$0" ]; then
    echo "(!) Cannot determine script path" >&2
    exit 1
fi

script_name="$0"
script_dir="$(cd "$(dirname "$script_name")" && pwd)"
# ---------------------------------------

# Specify last argument as context if it's a directory
last_arg="${*: -1}"
# Parse first argument as IMAGE_NAME, second as REMOTE_USER (if not a build-arg or option)
first_arg="${1-}"
[ -z "$first_arg" ] || shift
# Check if next argument begins with '-' (indicating a build-arg or option)
# (if so, do not consume it as the second argument)
second_arg=""
if [ $# -gt 0 ]; then
    case "$1" in
        -*) ;;
        "$last_arg"*)
            [ $# -gt 1 ] || {
                second_arg="$1"
                shift
                last_arg=""
            }
            ;;
        *)
            second_arg="$1"
            shift
            ;;
    esac
else
    case "$first_arg" in
        "$last_arg"*) last_arg="" ;;
    esac
fi

. "${script_dir}/loader.sh" "${script_dir}/.."

# ---------------------------------------

BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-ubuntu}"
BASE_IMAGE_VARIANT="${BASE_IMAGE_VARIANT:-latest}"
DEFAULT_PLATFORM="linux/$(uname -m)"
FILEZ_TARGET="${FILEZ_TARGET:-filez}"
[ "$BASE_IMAGE_VARIANT" = "latest" ] \
    && BASE_IMAGE_REF="$BASE_IMAGE_NAME" \
    || BASE_IMAGE_REF="${BASE_IMAGE_VARIANT}"

# Determine Docker context
if [ -d "$last_arg" ]; then
    BUILD_CONTEXT="$last_arg"
else
    BUILD_CONTEXT="${BUILD_CONTEXT:-"${script_dir}/../.."}"
fi
if [ ! -d "$BUILD_CONTEXT" ]; then
    echo "(!) Docker context directory not found at expected path: $BUILD_CONTEXT" >&2
    exit 1
fi
# Determine IMAGE_NAME and DOCKER_TARGET
IMAGE_NAME=${IMAGE_NAME:-$first_arg}
if [ -z "$IMAGE_NAME" ]; then
    echo "Usage: $0 <image-name[:build_target]> [build-args...] [options] [context]" >&2
    exit 1
fi
if [ -n "${IMAGE_NAME##*:}" ] && [ "${IMAGE_NAME##*:}" != "$IMAGE_NAME" ]; then
    DOCKER_TARGET="${IMAGE_NAME##*:}"
    IMAGE_NAME="${IMAGE_NAME%%:*}"
fi
DOCKER_TARGET=${DOCKER_TARGET:-"base"}
# Determine REMOTE_USER (the devcontainer non-root user, e.g., 'vscode' or 'devcontainer')
REMOTE_USER="${REMOTE_USER:-$second_arg}"
TAG_PREFIX="${TAG_PREFIX:-$DOCKER_TARGET}"
if [ "$DOCKER_TARGET" = "$FILEZ_TARGET" ]; then
    build_tag="${TAG_PREFIX}"
else
    build_tag="${IMAGE_NAME}:${BASE_IMAGE_REF}"
    if [ "$BASE_IMAGE_VARIANT" = "latest" ] || [ -n "$TAG_PREFIX" ]; then
        tag_prefix="${IMAGE_NAME}:${TAG_PREFIX}"
        build_tag="${tag_prefix}-${BASE_IMAGE_REF}"
    fi

    if [ "$TAG_PREFIX" = "latest" ]; then
        build_tag="${IMAGE_NAME}:${BASE_IMAGE_REF}"
    fi
fi

dockerfile_path="${BUILD_CONTEXT}/docker/Dockerfile"

if [ ! -f "$dockerfile_path" ]; then
    echo "(!) Dockerfile not found at expected path: ${dockerfile_path}" >&2
    exit 1
fi

echo "(*) Building Docker image for ${DOCKER_TARGET}..." >&2
echo "(*) Dockerfile path: ${dockerfile_path}" >&2
echo "(*) Docker context: ${BUILD_CONTEXT}" >&2
com=(docker build)
com+=("-f" "${dockerfile_path}")
com+=("--label" "org.opencontainers.image.ref.name=${build_tag}")
com+=("--target" "${DOCKER_TARGET}")
com+=("-t" "${build_tag}")
com+=("--platform=$(dedupe "${PLATFORM:-$DEFAULT_PLATFORM}")")
# The `debian:bookworm-slim` image provides a minimal base for development containers
com_arg=()
com_arg+=("--build-arg" "IMAGE_NAME=${BASE_IMAGE_NAME}")
com_arg+=("--build-arg" "VARIANT=${BASE_IMAGE_VARIANT}")
if [ -n "$REMOTE_USER" ]; then
    com_arg+=("--build-arg" "USERNAME=${REMOTE_USER}")
fi
# com_arg+=("--build-arg" "PYTHON_VERSION=${PYTHON_VERSION:-latest}")
com_arg+=("--build-arg" "TIMEZONE=$(zoneinfo)")
com_arg+=("--build-arg" "DEV=${DEV:-false}")
# Automatically pass build arguments prefixed with DOCKER_BUILD_
# Strip the prefix and pass the variable to docker build
while IFS='=' read -r name value; do
    if [[ $name == DOCKER_BUILD_*   ]]; then
        arg_name="${name#DOCKER_BUILD_}"
        com_arg+=("--build-arg" "${arg_name}=${value}")
    fi
done < <(env)
for arg in "$@"; do
    if [ "$arg" != "$BUILD_CONTEXT" ]; then
        com_arg+=("$arg")
    fi
done
com+=("${com_arg[@]}")
com+=("$BUILD_CONTEXT")

set -- "${com[@]}"
. "${script_dir}/executer.sh" "$@"

echo "(√) Done! Docker image build complete." >&2
# echo "_______________________________________" >&2
echo >&2
