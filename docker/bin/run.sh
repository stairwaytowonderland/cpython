#!/usr/bin/env bash
# shellcheck disable=SC1091

# [REMOTE_HUB=<your-remote-hub>] ./docker/bin/run.sh \
#   cpython:<target> \
#   appuser \
#   .

echo "(ƒ) Preparing to run Docker container..." >&2

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

. "${script_dir}/loader.sh" "${script_dir}/.."

# ---------------------------------------

BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-ubuntu}"
BASE_IMAGE_VARIANT="${BASE_IMAGE_VARIANT:-latest}"
TERM="${TERM-}"
TIMEZONE="${TIMEZONE-$(zoneinfo)}"
[ "$BASE_IMAGE_VARIANT" = "latest" ] \
    && BASE_IMAGE_REF="$BASE_IMAGE_NAME" \
    || BASE_IMAGE_REF="${BASE_IMAGE_VARIANT}"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <image-name[:build_target]> [remote-user] [context]" >&2
    exit 1
fi
# Determine IMAGE_NAME and DOCKER_TARGET
IMAGE_NAME=${IMAGE_NAME:-$1}
shift
if [ -n "${IMAGE_NAME##*:}" ] && [ "${IMAGE_NAME##*:}" != "$IMAGE_NAME" ]; then
    DOCKER_TARGET="${IMAGE_NAME##*:}"
    IMAGE_NAME="${IMAGE_NAME%%:*}"
fi
DOCKER_TARGET=${DOCKER_TARGET:-"base"}
if [ -d "$last_arg" ]; then
    RUN_CONTEXT="$last_arg"
else
    RUN_CONTEXT="${RUN_CONTEXT:-"${script_dir}/../.."}"
fi
if [ ! -d "$RUN_CONTEXT" ]; then
    echo "(!) Docker context directory not found at expected path: ${RUN_CONTEXT}" >&2
    exit 1
fi
# Determine REMOTE_USER
if [ $# -gt 0 ]; then
    if [ "$1" != "$RUN_CONTEXT" ]; then
        REMOTE_USER="${1-}"
        shift
    fi
fi
REMOTE_USER="${REMOTE_USER:-devcontainer}"
IMAGE_VERSION="${IMAGE_VERSION:-latest}"

TAG_PREFIX="${TAG_PREFIX:-$DOCKER_TARGET}"
REMOTE_HUB="${REMOTE_HUB-}"
if [ -n "$REMOTE_HUB" ]; then
    docker_tag="${REMOTE_HUB}/${IMAGE_NAME}:${TAG_PREFIX}"
else
    build_tag="${IMAGE_NAME}:${BASE_IMAGE_REF}"
    if [ "$BASE_IMAGE_VARIANT" = "latest" ] && [ -n "$TAG_PREFIX" ]; then
        tag_prefix="${IMAGE_NAME}:${TAG_PREFIX}"
        build_tag="${tag_prefix}-${BASE_IMAGE_REF}"
    fi

    if [ "$TAG_PREFIX" = "latest" ]; then
        build_tag="${IMAGE_NAME}:${BASE_IMAGE_REF}"
    fi

    publish_tag="${build_tag}"
    [ "$IMAGE_VERSION" = "latest" ] || publish_tag="${publish_tag}-${IMAGE_VERSION}"

    build_id="$(docker images -q "$build_tag")"
    publish_id="$(docker images -q "$publish_tag")"
    image_id="${build_id:-$publish_id}"

    echo "(*) Looking for Docker image id '${image_id}' ('${build_tag}' or '${publish_tag}') locally..." >&2

    if docker image inspect "$build_id" > /dev/null 2>&1; then
        echo "(*) Found Docker image '${build_tag}'" >&2
        docker_tag="$build_tag"
    elif docker image inspect "$publish_id" > /dev/null 2>&1; then
        echo "(*) Found Docker image '${publish_tag}'" >&2
        docker_tag="$publish_tag"
    else
        echo "(!) Docker image not found locally. Please build the image first." >&2
        exit 1
    fi
fi

workspace_dir="/home/${REMOTE_USER}/workspace"

echo "(*) Running Docker container for ${REMOTE_USER}..." >&2
com=(docker run -it --rm)
# TZ not needed, but included for reference and clarity
com_env=()
if [ -n "${IGNOREEOF-}" ]; then
    com_env+=("-e" "IGNOREEOF=${IGNOREEOF}")
fi
com_env+=("-e" "TZ=${TIMEZONE}")
com_env+=("-e" "TERM=${TERM}")
if [ "${DEV:-false}" = "true" ]; then
    com_env+=("-e" "DEV=true")
    com_env+=("-e" "RESET_ROOT_PASS=${RESET_ROOT_PASS:-false}")
    com_env+=("-e" "DEBUG=${DEBUG:-false}")
fi
# Automatically pass environment variables prefixed with DOCKER_VAR_
# Strip the prefix and pass the variable to the container
while IFS='=' read -r name value; do
    if [[ $name == DOCKER_RUN_*   ]]; then
        var_name="${name#DOCKER_RUN_}"
        com_env+=("-e" "${var_name}=${value}")
    fi
done < <(env)
while [ $# -gt 0 ]; do
    case "$1" in
        -e)
            com_env+=("-e" "$2")
            shift 2
            ;;
        --env=*)
            com_env+=("$1")
            shift
            ;;
        *)
            break
            ;;
    esac
done
com_vol=()
if [ "$DOCKER_TARGET" = "builder" ]; then
    com_vol+=("-v" "${RUN_CONTEXT}/docker/helpers:/helpers:ro")
    com_vol+=("-v" "${RUN_CONTEXT}/docker/lib-scripts:/tmp/lib-scripts:ro")
else
    com_vol+=("-v" "${RUN_CONTEXT}:${workspace_dir}")
    if [ -d "${HOME}/.ssh" ]; then
        com_vol+=("-v" "${HOME}/.ssh:/home/${REMOTE_USER}/.ssh:ro")
    fi
    if [ -r "${HOME}/.gitconfig" ]; then
        com_vol+=("-v" "${HOME}/.gitconfig:/etc/gitconfig:ro")
    fi
fi

[ "${com_env+x}" != "x" ] || com+=("${com_env[@]}")
[ "${com_vol+x}" != "x" ] || com+=("${com_vol[@]}")
[ "${com_port+x}" != "x" ] || com+=("${com_port[@]}")
com+=("$docker_tag")

for arg in "$@"; do
    if [ "$arg" != "$RUN_CONTEXT" ]; then
        com+=("$arg")
    fi
done

set -- "${com[@]}"
. "${script_dir}/executer.sh" "$@"

echo "(√) Done! Docker container exited." >&2
# echo "_______________________________________" >&2
echo >&2
