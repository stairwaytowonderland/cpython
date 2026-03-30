#!/bin/sh

VERSION="${VERSION:-latest}"

export DEBIAN_FRONTEND=noninteractive
export GITHUB_API_HEADER_ACCEPT="Accept: application/vnd.github.v3+json"
export API_TOKEN="${API_TOKEN-}"

__default_makeflags() {
    _makeflags="${MAKEFLAGS-} "
    if type nproc > /dev/null 2>&1; then
        if [ -r /.dockerenv ] || [ -r /proc/1/cgroup ]; then
            # Inside a container, use all available CPU cores for optimal performance
            _threads_offset=0
        else
            # Outside a container, use all available CPU cores minus 1 for optimal performance
            _threads_offset=1
        fi
        _nproc="$(nproc 2> /dev/null || echo 1)"
        _nproc_min="$((_threads_offset + 1))"
        if [ "$_nproc" -ge "$_nproc_min" ]; then
            _makeflags="${_makeflags} -j$(("$_nproc" - "$_threads_offset"))"
        fi
    fi
    echo "$_makeflags"
    unset _makeflags _nproc _threads_offset
}

__get_platform() {
    uname -s | tr '[:upper:]' '[:lower:]' | xargs -I{} echo "{} $(dpkg --print-architecture)"
}

__get_os() {
    _platform="${1:-$(__get_platform)}"
    _platform_os="${_platform%% *}"
    case "$_platform_os" in
        linux)
            _download_os=linux
            ;;
        darwin)
            _download_os=darwin
            ;;
        *)
            LEVEL=error $LOGGER "Unsupported OS: $_platform_os"
            return 1
            ;;
    esac

    echo "$_download_os"
    unset _platform _platform_os _download_os
}

__get_arch() {
    _platform="${1:-$(__get_platform)}"
    _platform_arch="${_platform##* }"
    case "$_platform_arch" in
        x86_64 | amd64)
            _download_arch=amd64
            ;;
        aarch64 | armv8* | arm64)
            _download_arch=arm64
            ;;
        aarch32 | armv7* | armvhf*)
            _download_arch=arm
            ;;
        i?86) _download_arch=386 ;;
        *)
            LEVEL=error $LOGGER "Unsupported architecture: $_platform_arch"
            return 1
            ;;
    esac

    echo "$_download_arch"
    unset _platform _platform_arch _download_arch
}

# OS Detection
os() {
    _os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    # arch="$(dpkg --print-architecture)"
    if [ -r /etc/os-release ]; then
        # os="$(. /etc/os-release; echo "${os}:${ID-}-${VERSION_CODENAME-}:${VERSION_ID-}")"
        while IFS='=' read -r _os_name _os_value; do
            case "$_os_name" in
                ID) _os_id="$(echo "$_os_value" | tr '[:upper:]' '[:lower:]' | tr -d '"')" ;;
                VERSION_ID) _os_version_id="$(echo "$_os_value" | tr '[:upper:]' '[:lower:]' | tr -d '"')" ;;
                VERSION_CODENAME) _os_codename="$(echo "$_os_value" | tr '[:upper:]' '[:lower:]' | tr -d '"')" ;;
            esac
        done < /etc/os-release
        _os="${_os}:${_os_id}-${_os_codename}:${_os_version_id}"
    fi
    echo "${_os}"
    unset _os _os_id _os_codename _os_version_id _os_name _os_value
}
os_platform() { os | cut -d: -f1; }
os_type() { os_platform | cut -d- -f1; }
os_arch() { os_platform | cut -d- -f2; }
os_name() { os | cut -d: -f2; }
os_id() { os_name | cut -d- -f1; }
os_codename() { os_name | cut -d- -f2; }
os_version() { os | cut -d: -f3; }

# Version parsing
get_major_version() { echo "$1" | cut -d. -f1; }
get_minor_version() { echo "$1" | cut -d. -f2; }
get_patch_version() { echo "$1" | cut -d. -f3; }
get_major_minor_version() { echo "$1" | cut -d. -f1,2; }

updaterc() {
    _newline="${2-}"
    if [ "$_newline" = "true" ]; then _newline="\n"; else unset _newline; fi
    case "$(cat "${3:-/etc/bash.bashrc}")" in
        *"$1"*) ;;
        *) printf '%b%s\n' "$_newline" "$1" >> "${3:-/etc/bash.bashrc}" ;;
    esac
    unset _newline
}

get_alternatives_priority() {
    { update-alternatives --display "${1}${2-}" 2> /dev/null || echo "priority -1"; } | awk '/priority/ {print $NF}' | sort -n | head -n 1
}

ensure_root() {
    if [ "$(id -u)" -ne 0 ]; then
        LEVEL='error' $LOGGER '(!)' "This script must be run as root. Current user ID: $(id -u)"
        return 1
    fi
}

install_packages() {
    # shellcheck disable=SC2086
    LEVEL='*' $LOGGER "Installing the following packages: "$*
    # shellcheck disable=SC2086,SC2048
    apt-get -y install --no-install-recommends $*
}

update_and_install() {
    apt-get update
    install_packages "$@"
}

# shellcheck disable=SC2086
remove_packages() {
    LEVEL='*' $LOGGER "Removing the following packages: "$*
    # shellcheck disable=SC2048
    for pkg in $*; do
        ! dpkg -s "$pkg" > /dev/null 2>&1 || apt-get -y remove --purge "$pkg"
    done
}

# Usage example for defining packages to install:
#
# PACKAGES_TO_INSTALL="${PACKAGES_TO_INSTALL% } $(
#     cat << EOF
# list
# of
# packages
# EOF
# )"
#
# [ -z "$PACKAGES_TO_INSTALL" ] \
#     && update_and_install "$PACKAGES_TO_INSTALL" \
#     || echo "Warning: No packages to install."

__check_semver() {
    _version="${1-}"
    [ "$(echo "${_version}" | grep -o '\.' | wc -l)" = "2" ] && echo "$_version" >&2 || return 1
    unset _version
}

# __get_semver() {
#     _version="${1-}"

#     __check_semver "$_version" > /dev/null 2>&1 \
#         && echo "$_version" 2> /dev/null 2>&1 \
#         || return $?
# }

# GITHUB_TOKEN="YOUR_GITHUB_PAT"
# AUTH_HEADER="Authorization: token ${GITHUB_TOKEN}"
# Use `git ls-remote --tags` for public repositories to avoid hitting API rate limits, and fallback to API if needed or if authentication is required.
# (see `find_version_from_git_tags`, below)
__rest_call() {
    if [ -n "$API_TOKEN" ]; then
        # curl -fsSL --include "$1" -H "${GITHUB_API_HEADER_ACCEPT}" -H "Authorization: token ${API_TOKEN}"
        wget -q --save-headers -O- \
            --header="${GITHUB_API_HEADER_ACCEPT}" \
            --header="Authorization: token ${API_TOKEN}" \
            "$1"
    else
        # curl -fsSL --include "$1" -H "${GITHUB_API_HEADER_ACCEPT}"
        wget -q --save-headers -O- \
            --header="${GITHUB_API_HEADER_ACCEPT}" \
            "$1"
    fi
}

__rest_github_tags_paged() {
    URL="https://api.github.com/repos/${1}/tags?per_page=100"

    _page=0
    _max_pages="${2:-10}"  # safety to prevent long running loops
    type __rest_call > /dev/null 2>&1 || return 1
    while [ ! -z "$URL" ] && [ $_page -lt "$_max_pages" ]; do
        _response=$(__rest_call "$URL")
        _body=$(echo "$_response" | sed -E '1,/^\r?$/d')
        _tags=$(echo "$_body" | grep -oP '"name":\s*"v?\K[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | sort -ruV)

        echo "$_tags"

        # Extract the 'Link' header for the next page URL
        # https://docs.github.com/en/rest/using-the-rest-api/using-pagination-in-the-rest-api?apiVersion=2022-11-28
        _next_url=$(echo "$_response" | grep -Fi 'link: <' | sed -e 's/[Ll]ink: <\([^>]*\)>.*rel="next".*/\1/' -e 't' -e 'd')

        URL="$_next_url"
        _page=$((_page + 1))
    done | sort -ruV

    unset _response _body _tags _next_url _page _max_pages
}

# https://github.com/devcontainers/features/blob/main/src/python/install.sh
__find_version_from_git_tags() {
    _repository=$1
    _requested_version=${2:-latest}
    [ "${_requested_version}" != "none" ] || return
    _url="https://${GIT_SERVER:-github.com}/${_repository}"
    _prefix=${3:-"tags/v"}
    _separator=${4:-"."}
    _last_part_optional=${5:-"false"}
    if [ "$(echo "${_requested_version}" | grep -o "." | wc -l)" != "2" ]; then
        # escaped_separator=${_separator//./\\.}
        _escaped_separator=$(printf '%s\n' "$_separator" | sed "s/[][\.*^$(){}?+|/]/\\\&/g")
        [ "${ENABLE_PRE_RELEASE:-false}" != "true" ] || _pre_release_pattern="${_pre_release_pattern:-acr}"
        if [ "${_last_part_optional}" = "true" ]; then
            _last_part="(${_escaped_separator}[0-9${_pre_release_pattern}]+)?"
        else
            _last_part="${_escaped_separator}[0-9${_pre_release_pattern}]+"
        fi
        _regex="$(echo "$_prefix" | sed 's|\/|\\/|g')\\K[0-9]+${_escaped_separator}[0-9]+${_last_part}$"
        _version_list="$(git ls-remote --tags "${_url}" | grep -oP "${_regex}" | sed "s|$_prefix||" | tr "${_separator}" "." | sort -ruV)"
        if [ "${_requested_version}" = "latest" ] || [ "${_requested_version}" = "current" ] || [ "${_requested_version}" = "lts" ]; then
            VERSION="$(echo "${_version_list}" | head -n 1)"
        else
            VERSION="$(echo "${_version_list}" | grep -E -m 1 "^$(printf '%s' "$_requested_version" | sed "s/[.[\*^$(){}?+|/]/\\\&/g")([\\.\\s]|$)")"
        fi
    fi

    unset _repository _requested_version _url _prefix _separator _last_part_optional _escaped_separator _regex _version_list
}

__get_version_with_rest_api() {
    _github_repo="${1-}"
    _version="${2:-latest}"

    if [ -z "$_github_repo" ]; then
        LEVEL='error' $LOGGER "GitHub repository is required to fetch version (${_version}) from tags."
        return 1
    fi

    if ! __check_semver > /dev/null 2>&1 "$_version"; then
        # https://github.com/devcontainers/features/blob/main/src/git/install.sh#L291C76-L291C117
        # version_list="$(curl -sSL -H "Accept: application/vnd.github.v3+json" "https://api.github.com/repos/${_github_repo}/tags" | grep -oP '"name":\s*"v\K[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' | sort -rV)"
        _version_list="$(__rest_github_tags_paged "$_github_repo")"
        if [ "${_version}" = "latest" ] || [ "${_version}" = "lts" ] || [ "${_version}" = "current" ]; then
            VERSION="$(echo "${_version_list}" | head -n 1)"
        else
            _escaped_version="$(echo "${_version}" | sed 's/\./\\./g')"
            VERSION="$(echo "${_version_list}" | grep -E -m 1 "^${_escaped_version}([\\.\\s]|$)")"
        fi
        _escaped_version_check="$(echo "${VERSION}" | sed 's/\./\\./g')"
        if [ -z "${VERSION}" ] || ! echo "${_version_list}" | grep "^${_escaped_version_check}$" > /dev/null 2>&1; then
            LEVEL='error' $LOGGER "Invalid git version: ${VERSION}"
            return 2
        fi
    fi

    # shellcheck disable=SC2015
    __check_semver > /dev/null 2>&1 "$VERSION" && echo "$VERSION" || {
        LEVEL='error' $LOGGER "Version must be a semantic version (e.g., 1.2.3): ${VERSION}"
        return 3
    }

    unset _github_repo _version _version_list _escaped_version _escaped_version_check
}

__set_url_parts() {
    _github_repo="${1-}"
    _version="${2-}"

    if [ $# -gt 3 ]; then
        _version_prefix="${3-}"
        _url_prefix="${4%"$_version_prefix"}"
        DOWNLOAD_URL_PREFIX="${_url_prefix%/}"
    else
        _url_prefix="${3-}"
        _version_prefix=""
        DOWNLOAD_URL_PREFIX="${_url_prefix}"
    fi

    # ? swap for __find_version_from_git_tags?
    _download_version="$(__get_version_with_rest_api "$_github_repo" "$_version")" || return $?
    DOWNLOAD_VERSION="${_version_prefix}${_download_version#"$_version_prefix"}"
    DOWNLOAD_PLATFORM="$(uname -sm | tr '[:upper:]' '[:lower:]')"
    DOWNLOAD_OS="$(__get_os "$DOWNLOAD_PLATFORM")" || return $?
    DOWNLOAD_ARCH="$(__get_arch "$DOWNLOAD_PLATFORM")" || return $?

    unset _github_repo _version _version_prefix _url_prefix
}

__install_from_tarball() {
    DOWNLOAD_URL="${1-}"
    INSTALL_PREFIX="${2-"/usr/local"}"
    _file_ext="${DOWNLOAD_URL##*.}"
    case "$_file_ext" in
        gz | tgz)
            _tar_opts="z"
            ;;
        xz)
            _tar_opts="J"
            ;;
        bz2 | bz)
            _tar_opts="j"
            ;;
        *)
            LEVEL='error' $LOGGER "Unsupported tarball extension: $_file_ext"
            return 1
            ;;
    esac

    mkdir -p "$INSTALL_PREFIX"
    LEVEL='*' $LOGGER "Downloading from $DOWNLOAD_URL ..."
    # (
    #     set -x
    #     curl -fsSL "$DOWNLOAD_URL" | tar -C "$INSTALL_PREFIX" -"xv${tar_opts}f" -
    # )
    # (
    #     set -x
    #     wget -qO- "$DOWNLOAD_URL" | tar -C "$INSTALL_PREFIX" -"xv${tar_opts}f" -
    # )
    (
        set -x
        _tmpfile="$(mktemp)"
        wget -q -O "$_tmpfile" "$DOWNLOAD_URL" \
            && tar -C "$INSTALL_PREFIX" -"xv${_tar_opts}f" "$_tmpfile"
        _rc=$?
        rm -f "$_tmpfile"
        [ $_rc -eq 0 ] || return $_rc
    )

    unset _file_ext _tar_opts _tmpfile
}

__install_from_package() {
    DOWNLOAD_URL="${1-}"
    _file_ext="${DOWNLOAD_URL##*.}"
    [ "$_file_ext" = "deb" ] || {
        LEVEL='error' $LOGGER "Unsupported package extension: $_file_ext"
        return 1
    }

    LEVEL='*' $LOGGER "Downloading from $DOWNLOAD_URL ..."
    # (
    #     set -x
    #     curl -fsOSL "$DOWNLOAD_URL" \
    #         && dpkg -i "${DOWNLOAD_URL##*/}" \
    #         && rm -f "${DOWNLOAD_URL##*/}"
    # )
    (
        set -x
        wget -q "$DOWNLOAD_URL" \
            && dpkg -i "${DOWNLOAD_URL##*/}" \
            && rm -f "${DOWNLOAD_URL##*/}"
    )

    unset _file_ext
}

export DOWNLOAD_VERSION DOWNLOAD_PLATFORM DOWNLOAD_OS DOWNLOAD_ARCH DOWNLOAD_URL_PREFIX

# Usage example for downloading and installing from a tarball:
#
# # Include install-helper.sh
# . install-helper.sh
#
# main() {
#     if __set_url_parts "owner/repo" "$VERSION"; then
#         build_url() {
#             url_prefix="https://github.com/owner/repo/releases/download/v"
#             echo "${url_prefix}${DOWNLOAD_VERSION}/file-name-${DOWNLOAD_VERSION}-${DOWNLOAD_OS}-${DOWNLOAD_ARCH}.tar.gz"
#         }
#         DOWNLOAD_URL="$(build_url)"
#     else
#         $LOGGER "Failed to determine download parameters for owner/repo version $VERSION"
#         exit 1
#     fi
#     __install_from_tarball "$DOWNLOAD_URL"
# }
