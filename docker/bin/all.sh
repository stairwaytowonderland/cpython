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
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.10 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.10 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.10 $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.11 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.11 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.11 $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.12 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.12 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.12 $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.12-perf ENABLE_OPTIMIZATIONS=true UPDATE_LLVM=true LLVM_VERSION=20 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.12 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.12-perf $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.13 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.13 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.13 $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.14 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.14 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.14 $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.14-dev UPDATE_NCURSES=true UPDATE_READLINE=true FORCE_GCC=true $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=3.14 $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= TAG_PREFIX=3.14-dev $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=true TAG_PREFIX=latest LLVM_VERSION=20 $BUILD_CONTEXT/$bin_dir/build.sh $REPO_NAME $REMOTE_USER --build-arg PYTHON_VERSION=latest $* $BUILD_CONTEXT
TIME_MSG_LABEL= TIME_MSG_PREFIX= LATEST=true TAG_PREFIX=latest LLVM_VERSION=20 $BUILD_CONTEXT/$bin_dir/publish.sh $REPO_NAME $REPO_NAMESPACE
EOF

    "${script_dir}/executer.sh" sh -c "$all_commands"
}

for arg in "$@"; do
    if [ "$arg" != "$BUILD_CONTEXT" ]; then
        com+=("$arg")
    fi
done

TIME_MSG_LABEL="==> " TIME_MSG_PREFIX="TOTAL time" main "${com[@]}"

echo "(√) Done! All Docker images built and published." >&2
# echo "_______________________________________" >&2
echo >&2
