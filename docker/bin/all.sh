#!/usr/bin/env bash
# shellcheck disable=SC1091

# ./docker/bin/all.sh .

echo "(ƒ) Preparing to build and publish all Docker images..." >&2

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

if [ -d "$last_arg" ]; then
    BUILD_CONTEXT="$last_arg"
else
    BUILD_CONTEXT="${BUILD_CONTEXT:-"${script_dir}/../.."}"
fi
if [ ! -d "$BUILD_CONTEXT" ]; then
    echo "(!) Docker context directory not found at expected path: ${BUILD_CONTEXT}" >&2
    exit 1
fi

DEFAULT_BASE_IMAGE_NAME="${DEFAULT_BASE_IMAGE_NAME:-ubuntu}"
REMOTE_USER="${REMOTE_USER:-appuser}"
REPO_NAME="${REPO_NAME-}"
REPO_NAMESPACE="${REPO_NAMESPACE-}"
bin_dir="docker/bin"

if ! . "${script_dir}/login.sh" "$REPO_NAMESPACE" "$REPO_NAME"; then
    echo "Error: Not logged in to ${REGISTRY_PROVIDER} Container Registry." >&2
    exit 1
fi

# Force timezone to UTC (if unset) for consistent build timestamps
export TIMEZONE=${TIMEZONE:-UTC}

main() {
    # Newline-separated list of commands to run
    local all_commands=""
    while IFS= read -r cmd || [ -n "$cmd" ]; do
        [ -n "$cmd" ] || continue
        [ -n "$all_commands" ] \
            && all_commands="$all_commands && $cmd" \
            || all_commands="$cmd"
    done << EOF
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.10 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.10 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.10 $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.11 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.11 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.11 $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.12 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.12 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.12 $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.12-perf $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.12 --build-arg ENABLE_OPTIMIZATIONS=true $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.12-perf $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.12-ext $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.12 --build-arg PYTHON_DEV=true --build-arg ENABLE_BOLT=false $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.12-ext $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.13 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.13 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.13 $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.14 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.14 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.14 $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.14-perf $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.14 --build-arg ENABLE_OPTIMIZATIONS=true $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.14-perf $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.14-ext $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.14 --build-arg PYTHON_DEV=true --build-arg ENABLE_BOLT=false $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false TAG_PREFIX=3.14-ext $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false UNSTABLE=true TAG_PREFIX=unstable $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=latest $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=false UNSTABLE=true TAG_PREFIX=unstable $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST="${LATEST:-false}" TAG_PREFIX=latest $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=current $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST="${LATEST:-false}" TAG_PREFIX=latest $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
EOF

    "${script_dir}/executer.sh" sh -c "$all_commands"
}

dhi() {
    # Newline-separated list of commands to run
    local all_commands=""
    while IFS= read -r cmd || [ -n "$cmd" ]; do
        [ -n "$cmd" ] || continue
        [ -n "$all_commands" ] \
            && all_commands="$all_commands && $cmd" \
            || all_commands="$cmd"
    done << EOF
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.12 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.12 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.12 $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.14 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.14 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.14 $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
EOF

    "${script_dir}/executer.sh" sh -c "$all_commands"
}

for arg in "$@"; do
    if [ "$arg" != "$BUILD_CONTEXT" ]; then
        com+=("$arg")
    fi
done

export TIME_MSG_LABEL="==> " TIME_MSG_PREFIX="TOTAL time"

# shellcheck disable=SC2043
for base_image in dhi:bookworm-debian12-dev; do
    export BASE_IMAGE_NAME="${base_image%%:*}" BASE_IMAGE_VARIANT="${base_image##*:}"
    echo "(*) Building and publishing Hardened images based on ${base_image}..." >&2
    echo "BASE_IMAGE_NAME=${BASE_IMAGE_NAME}" >&2
    echo "BASE_IMAGE_VARIANT=${BASE_IMAGE_VARIANT}" >&2
    dhi "${com[@]}"
done

for base_image in debian:bookworm-slim ubuntu:latest; do
    export BASE_IMAGE_NAME="${base_image%%:*}" BASE_IMAGE_VARIANT="${base_image##*:}"
    [ "$DEFAULT_BASE_IMAGE_NAME" != "$BASE_IMAGE_NAME" ] || export LATEST=true
    echo "(*) Building and publishing Standard images based on ${base_image}..." >&2
    echo "BASE_IMAGE_NAME=${BASE_IMAGE_NAME}" >&2
    echo "BASE_IMAGE_VARIANT=${BASE_IMAGE_VARIANT}" >&2
    echo "LATEST=${LATEST:-false}" >&2
    main "${com[@]}"
done

echo "(√) Done! All Docker images built and published." >&2
# echo "_______________________________________" >&2
echo >&2
