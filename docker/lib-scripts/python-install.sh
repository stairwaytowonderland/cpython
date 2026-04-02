#!/bin/sh

# Only check for errors (set -e)
# Don't check for unset variables (set -u) since variables are set in Dockerfile
# Pipepail (set -o pipefail) is not available in sh
set -e

LEVEL='ƒ' $LOGGER "Installing Python utilities..."

VERSION="${PYTHON_VERSION:-latest}"
PYTHON_VERSION="$VERSION"
PYTHON_INSTALL_PREFIX="${PYTHON_INSTALL_PREFIX:-/opt/python}"
PYTHON_INSTALL_PATH="${PYTHON_INSTALL_PATH:-"${PYTHON_INSTALL_PREFIX%/}/lib"}"
PYTHON_LIBDIR="${PYTHON_INSTALL_PATH%/lib}/lib"
PYTHON_DEV="${PYTHON_DEV:-false}"
SYSTEM_INSTALL_PREFIX="${SYSTEM_INSTALL_PREFIX:-/usr}"
LLVM_VERSION="${LLVM_VERSION:-18}"
UPDATE_NCURSES="${UPDATE_NCURSES:-false}"
UPDATE_READLINE="${UPDATE_READLINE:-false}"
ENABLE_SHARED="${ENABLE_SHARED:-true}"
ENABLE_OPTIMIZATIONS="${ENABLE_OPTIMIZATIONS:-false}"
ENABLE_BOLT="${ENABLE_BOLT:-false}"

# Override USE_CLANG if updating LLVM to allow for updating llvm and compiling with gcc
USE_CLANG="${USE_CLANG:-false}"
FORCE_GCC="${FORCE_GCC:-false}"

# Always update LLVM to avvoid installing unnecessary packages
UPDATE_LLVM=true

# shellcheck disable=SC1090
. "$INSTALL_HELPER"

export MAKEFLAGS="${MAKEFLAGS:-$(__default_makeflags)}"

download_cpython_version() {
    LEVEL='*' $LOGGER "Downloading Python version ${1}..."

    cd /tmp
    cpython_download_prefix="Python-${2:-$1}"
    if type xz > /dev/null 2>&1; then
        cpython_download_filename="${cpython_download_prefix}.tar.xz"
    elif type gzip > /dev/null 2>&1; then
        cpython_download_filename="${cpython_download_prefix}.tgz"
    else
        LEVEL='error' $LOGGER "Required package (xz-utils or gzip) not found."
        return 1
    fi

    DOWNLOAD_URL="https://www.python.org/ftp/python/${1}/${cpython_download_filename}"

    __install_from_tarball "$DOWNLOAD_URL" "$PWD" && DOWNLOAD_DIR="${PWD}/${cpython_download_prefix}"
}

__pre_install() {
    cwd="$PWD"
    mkdir -p "$INSTALL_PATH"
    if [ -n "${PRE_RELEASE_SUFFIX-}" ]; then
        download_cpython_version "$(__major_minor_patch_version)" "${VERSION}"
    else
        download_cpython_version "${VERSION}"
    fi

    if [ ! -d "$DOWNLOAD_DIR" ]; then
        LEVEL='error' $LOGGER "Failed to download Python version ${VERSION}."
        exit 1
    fi

    cd "$DOWNLOAD_DIR"

    install_packages "${PYTHON_BUILD_DEPENDENCIES# }"

    LEVEL='*' $LOGGER "Configuring and building Python ${VERSION}..."
    LEVEL='*' $LOGGER "Installation prefix: ${PYTHON_INSTALL_PREFIX}"
    LEVEL='*' $LOGGER "Library directory: ${PYTHON_LIBDIR}"

    _configure_libdir="${PYTHON_LIBDIR:+--libdir="$PYTHON_LIBDIR"}"

    if [ "$USE_CLANG" = "true" ]; then
        if type "clang-${LLVM_VERSION}" > /dev/null 2>&1; then
            LEVEL='*' $LOGGER "Using clang as the compiler for Python ${VERSION}..."

            CC=clang
            CXX=clang++
        else
            LEVEL='!' $LOGGER "clang-${LLVM_VERSION} not found; falling back to default compiler for Python ${VERSION}..."
        fi
    fi

    # if [ "$ENABLE_OPTIMIZATIONS" = "true" ]; then
    #     CFLAGS="${CFLAGS:-O3 -march=native -flto=auto}"
    #     LDFLAGS="${LDFLAGS:-flto=auto}"
    #     # LDFLAGS="-fno-lto"
    # fi
}

__post_install() {
    # Ensure the Python library directory is included in the dynamic linker configuration
    echo "${PYTHON_INSTALL_PREFIX}/lib" > /etc/ld.so.conf.d/python.conf
    ldconfig

    # Cleanup
    cd "$cwd" && rm -rf "$DOWNLOAD_DIR"

    remove_packages "${PYTHON_BUILD_DEPENDENCIES# }"

    # Strip unnecessary files to reduce image size
    find "$PYTHON_INSTALL_PATH" -type d -name 'test' -exec rm -rf {} + 2> /dev/null || true
    find "$PYTHON_INSTALL_PATH" -type d -name '__pycache__' -exec rm -rf {} + 2> /dev/null || true
    find "$PYTHON_INSTALL_PATH" -type f -name '*.pyc' -delete
    find "$PYTHON_INSTALL_PATH" -type f -name '*.pyo' -delete
    find "$PYTHON_INSTALL_PATH"/python* -name 'config-*' -exec rm -rf {} + 2> /dev/null || true

    if [ "$PYTHON_DEV" != "true" ]; then
        # Remove additional unnecessary build dependencies
        find "$PYTHON_INSTALL_PATH" -type f -name '*.a' -delete
        [ ! -d "${PYTHON_INSTALL_PREFIX}/include" ] || find "${PYTHON_INSTALL_PREFIX}/include" -mindepth 1 -maxdepth 1 -exec rm -rf {} \;
        [ ! -d "${PYTHON_INSTALL_PATH}/pkgconfig" ] || find "${PYTHON_INSTALL_PATH}/pkgconfig" -mindepth 1 -maxdepth 1 -exec rm -rf {} \;
    fi

    updaterc "if [[ \"\${PATH}\" != *\"${PYTHON_INSTALL_PREFIX}/bin\"* ]]; then export \"PATH=${PYTHON_INSTALL_PREFIX}/bin:\${PATH}\"; fi" true

    PYTHON_SRC_ACTUAL="${PYTHON_INSTALL_PREFIX}/bin/python${_major_minor_version}"
    PATH="${PYTHON_INSTALL_PREFIX}/bin:${PATH}"

    cat >> "${PYTHON_INSTALL_PATH}/.manifest" << EOF
{"path":"${PYTHON_SRC_ACTUAL}","url":"${DOWNLOAD_URL}","version":"${VERSION}","major_version":"${_major_version}","major_minor_version":"${_major_minor_version}"}
EOF
}

install_cpython() {
    LEVEL='*' $LOGGER "Preparing to install Python version ${VERSION} ($PYTHON_VERSION) to ${INSTALL_PATH}..."

    # Check if the specified Python version is already installed
    if [ -d "$INSTALL_PATH" ]; then
        LEVEL='!' $LOGGER "Requested Python version ${VERSION} already installed at ${INSTALL_PATH}."
        return
    fi

    __pre_install

    # https://docs.python.org/3/using/configure.html#performance-options
    # shellcheck disable=SC2086
    CC="${CC:-gcc}" CXX="${CXX:-g++}" CFLAGS="${CFLAGS-}" LDFLAGS="${LDFLAGS-}" \
        PKG_CONFIG_LIBDIR="${SYSTEM_INSTALL_PREFIX}/lib/$(uname -m)-linux-gnu/pkgconfig" \
        PKG_CONFIG_PATH="${SYSTEM_INSTALL_PREFIX}/lib/pkgconfig${PKG_CONFIG_PATH:+:${PKG_CONFIG_PATH}}" \
        ./configure \
        --with-ssl-default-suites="${CIPHER_SUITES:-python}" \
        --prefix="$PYTHON_INSTALL_PREFIX" \
        --with-ensurepip=install \
        --disable-test-modules \
        ${_configure_libdir} \
        ${_shared_flag-} \
        ${_optimization_flags-} \
        ${_bolt_flag-}
    make && make install

    __post_install
}

PACKAGES_TO_KEEP=""
PACKAGES_TO_REMOVE=""
PACKAGES_TO_INSTALL="$(
    cat << EOF
lsb-release
EOF
)"

PYTHON_BUILD_DEPENDENCIES="$(
    cat << EOF
libbz2-dev
libffi-dev
libgdbm-dev
liblzma-dev
libnss3-dev
libssl-dev
libsqlite3-dev
libxml2-dev
libxmlsec1-dev
zlib1g-dev
tk-dev
EOF
)"

[ "$UPDATE_NCURSES" = "true" ] || PYTHON_BUILD_DEPENDENCIES="${PYTHON_BUILD_DEPENDENCIES% } libncursesw5-dev libncurses5-dev"
[ "$UPDATE_READLINE" = "true" ] || PYTHON_BUILD_DEPENDENCIES="${PYTHON_BUILD_DEPENDENCIES% } libreadline-dev"

if [ "$ENABLE_SHARED" = "true" ]; then
    LEVEL='*' $LOGGER "Enabling shared library build for Python ${VERSION}..."
    _shared_flag="--enable-shared"
fi
if [ "$ENABLE_OPTIMIZATIONS" = "true" ]; then
    LEVEL='*' $LOGGER "Enabling optimizations for Python ${VERSION}..."
    _optimization_flags="--enable-optimizations --with-lto --with-computed-gotos"
    UPDATE_LLVM=true
fi
if [ "$ENABLE_BOLT" = "true" ] && [ "$(__get_arch)" = "amd64" ]; then
    LEVEL='*' $LOGGER "Enabling BOLT support for Python ${VERSION} (LLVM ${LLVM_VERSION})..."
    _bolt_flag="--enable-bolt"
else
    ENABLE_BOLT=false
    LEVEL='*' $LOGGER "BOLT support not enabled for Python ${VERSION}."
fi

install_dependencies() {
    for pkg in ${PACKAGES_TO_INSTALL-}; do
        if ! dpkg -s "$pkg" > /dev/null 2>&1; then
            _packages_to_install="${_packages_to_install% } $pkg"
        fi
    done

    PACKAGES_TO_INSTALL="$_packages_to_install"

    update_and_install "${PACKAGES_TO_INSTALL# }"

    packages_to_remove "${PACKAGES_TO_INSTALL# }" "${PACKAGES_TO_KEEP# }"
}

upgrade_pip() {
    if type "pip${PYTHON_VERSION}" > /dev/null 2>&1; then
        LEVEL='*' $LOGGER "Upgrading pip and setuptools for Python ${PYTHON_VERSION}..."

        # Run upgrades without --ignore-installed so pip properly uninstalls the
        # old bundled versions (e.g. setuptools/_vendor/wheel-0.45.1.dist-info)
        # before installing the new ones.
        # _upgrade_flags="--upgrade --no-cache-dir --root-user-action=ignore"
        "$PIP_INSTALL" --upgrade pip
        "$PIP_INSTALL" --upgrade setuptools wheel
    fi
}

install_llvm() {
    _llvm_version="${1:-$LLVM_VERSION}"
    if [ "$UPDATE_LLVM" = "true" ]; then
        LEVEL='*' $LOGGER "Updating LLVM to version ${_llvm_version}..."

        _codename="$(os_codename)"
        wget -qO /etc/apt/trusted.gpg.d/apt.llvm.org.asc https://apt.llvm.org/llvm-snapshot.gpg.key
        echo "deb http://apt.llvm.org/${_codename}/ llvm-toolchain-${_codename}-${_llvm_version} main" \
            > "/etc/apt/sources.list.d/llvm-${_llvm_version}".list

        _packages_to_install="llvm-${_llvm_version}"

        update_and_install "${_packages_to_install# }"

        packages_to_remove "${_packages_to_install# }" "${PACKAGES_TO_KEEP# }"
    fi
}

remove_llvm() {
    if [ -d "${SYSTEM_INSTALL_PREFIX}/lib/llvm-${LLVM_VERSION}" ]; then
        LEVEL='*' $LOGGER "Removing LLVM ${LLVM_VERSION}..."

        apt-get remove -y --purge "llvm-${LLVM_VERSION}"
        rm -rf "${SYSTEM_INSTALL_PREFIX}/lib/llvm-${LLVM_VERSION}"
    fi
}

install_bolt() {
    # BOLT is only supported on x86_64; set up the LLVM apt repo and install the bolt tool
    # (the unversioned llvm-bolt binary lives in the LLVM bin dir)
    # https://github.com/llvm/llvm-project/blob/main/bolt/README.md
    if [ "$ENABLE_BOLT" = "true" ]; then
        if ! type type "${SYSTEM_INSTALL_PREFIX}/lib/llvm-${LLVM_VERSION}/bin/llvm-bolt" > /dev/null 2>&1; then
            UPDATE_LLVM=true
            install_llvm "$LLVM_VERSION"
        fi

        _python_build_dependencies="bolt-${LLVM_VERSION}"
        PYTHON_BUILD_DEPENDENCIES="${PYTHON_BUILD_DEPENDENCIES} ${_python_build_dependencies}"

        # shellcheck disable=SC2015
        update_and_install "$_python_build_dependencies" \
            && LEVEL='*' $LOGGER "Installed BOLT from LLVM ${LLVM_VERSION} repository" \
            || LEVEL='!' $LOGGER "Failed to install BOLT from LLVM ${LLVM_VERSION} repository"
        if type "${SYSTEM_INSTALL_PREFIX}/lib/llvm-${LLVM_VERSION}/bin/llvm-bolt" > /dev/null 2>&1; then
            export PATH="${SYSTEM_INSTALL_PREFIX}/lib/llvm-${LLVM_VERSION}/bin:${PATH}"
            ENABLE_BOLT=true
        else
            ENABLE_BOLT=false
        fi
    fi
}

__major_version() { printf "%s" "${_major_version-}"; }
__major_minor_version() { printf "%s" "${_major_minor_version-}"; }
__major_minor_patch_version() { printf "%s" "${_major_minor_patch_version-}"; }

prep_install() {
    _version="$VERSION"
    __find_version_from_git_tags "python/cpython" "${VERSION}" "tags/v" "."

    # _major_version="${VERSION%%.*}"
    # _major_minor_version="${VERSION%.*}"
    _major_version=$(get_major_version "$VERSION")
    _major_minor_version=$(get_major_minor_version "$VERSION")
    _major_minor_patch_version=$(echo "$VERSION" | sed -E 's/^([0-9][0-9]?\.[0-9][0-9]?\.[0-9][0-9]?)([0-9acr]+)?$/\1/')

    if [ "$_major_minor_patch_version" != "$VERSION" ]; then
        LEVEL='*' $LOGGER "Interpreted version ${_version} (${VERSION}) as major.minor.patch version ${_major_minor_patch_version} with pre-release suffix '${VERSION#"$_major_minor_patch_version"}'."
        PRE_RELEASE_SUFFIX="${VERSION#"$_major_minor_patch_version"}"
    fi

    INSTALL_PATH="${INSTALL_PATH:-"${PYTHON_INSTALL_PATH}/python${_major_minor_version}"}"

    if  [ "$ENABLE_OPTIMIZATIONS" = "true" ]; then
        # CFLAGS="${CFLAGS:-O3 -march=native -flto=auto}"
        # CFLAGS="${CFLAGS:-flto=auto}"
        # _ldflags="${LDFLAGS-}"
        # LDFLAGS="${_ldflags:-flto=auto}"

        if [ "$(__get_arch)" = "amd64" ] && [ "${_major_minor_version##*.}" -ge 14 ]; then
            UPDATE_LLVM=true
            if [ "$FORCE_GCC" != "true" ]; then
                LEVEL='*' $LOGGER "Enabling Clang for Python ${VERSION} optimizations..."
                USE_CLANG=true
            fi
            # LDFLAGS="${_ldflags% } -fno-lto"
        fi
    fi

    if [ "$UPDATE_LLVM" = "true" ]; then
        PACKAGES_TO_INSTALL="$(
            cat << EOF
gnupg
EOF
        )"
    fi

    install_packages "${PACKAGES_TO_INSTALL# }"
    packages_to_remove "${PACKAGES_TO_INSTALL# }" "${PACKAGES_TO_KEEP# }"
}

install_python() {
    install_llvm "$LLVM_VERSION"
    install_bolt "$LLVM_VERSION"
    install_cpython "$VERSION"
}

create_pip_installer() {
    LEVEL='*' $LOGGER "Creating pip installer script for Python ${PYTHON_VERSION}..."

    touch "$PIP_INSTALL" \
        && chmod +x "$PIP_INSTALL" \
        && cat > "$PIP_INSTALL" << EOF
#!/bin/sh
set -e
pip_install() {
  "${PYTHON_INSTALL_PREFIX}/bin/python${PYTHON_VERSION}" -m pip install $PIP_INSTALL_FLAGS "\$@"
}
pip_install "\$@"
EOF
}

create_setup() {
    LEVEL='*' "$LOGGER" "Creating configuration script for Python ${PYTHON_VERSION}..."

    # shellcheck disable=SC2154
    touch "${PYTHON_LIBDIR}/python-setup" \
        && chmod +x "${PYTHON_LIBDIR}/python-setup" \
        && cat > "${PYTHON_LIBDIR}/python-setup" << EOF
#!/bin/sh
LEVEL='*' "$LOGGER" "Configuring Python ${PYTHON_VERSION}..."

VERSION="$VERSION"
PYTHON_VERSION="$PYTHON_VERSION"
PYTHON_INSTALL_PREFIX="$PYTHON_INSTALL_PREFIX"
PYTHON_LIBDIR="$PYTHON_LIBDIR"
INSTALL_PATH="$INSTALL_PATH"
PYTHON_INSTALL_PATH="\${PYTHON_INSTALL_PATH:-$PYTHON_INSTALL_PATH}"
INSTALL_TOOLS="\${INSTALL_TOOLS:-$INSTALL_TOOLS}"
PYTHON_TOOLS="\${PYTHON_TOOLS:-$PYTHON_TOOLS}"
PIP_INSTALL="\${PIP_INSTALL:-$PIP_INSTALL}"

UPDATE_PACKAGES="\${UPDATE_PACKAGES:-${UPDATE_PACKAGES:-false}}"
UPDATE_NCURSES="\${UPDATE_NCURSES:-${UPDATE_NCURSES:-false}}"
UPDATE_READLINE="\${UPDATE_READLINE:-${UPDATE_READLINE:-false}}"

export LOGGER="\${LOGGER:-$LOGGER}"
export INSTALL_HELPER="\${INSTALL_HELPER:-$INSTALL_HELPER}"

# shellcheck disable=SC1090
. "\$INSTALL_HELPER"

export MAKEFLAGS="\${MAKEFLAGS:-$MAKEFLAGS}"

major_version=\$(get_major_version "\$VERSION")
major_minor_version=\$(get_major_minor_version "\$VERSION")

SYSTEM_PYTHON="\$(command -v "/usr/bin/python\${major_minor_version}" || true)"
ALTERNATIVES_PATH="\${ALTERNATIVES_PATH:-/usr/local/bin}"

make_links() {
    "\$LOGGER" "Creating symbolic links for Python binaries and libraries..."
    for py in python pip idle pydoc; do
        type "\${PYTHON_INSTALL_PREFIX}/bin/\${py}" >/dev/null 2>&1 || ln -s "\${py}\${major_version}" "\${PYTHON_INSTALL_PREFIX}/bin/\${py}"
    done
    type "\${PYTHON_INSTALL_PREFIX}/bin/python-config" >/dev/null 2>&1 || ln -s "python\${major_version}-config" "\${PYTHON_INSTALL_PREFIX}/bin/python-config"
}

update_env() {
    "\$LOGGER" "Updating environment variables for Python \${PYTHON_VERSION}..."
    updaterc "if [[ \"\\\${PATH}\" != *\"\${PYTHON_INSTALL_PREFIX}/bin\"* ]]; then export \"PATH=\${PYTHON_INSTALL_PREFIX}/bin:\\\${PATH}\"; fi" true
    (
        . /etc/environment
        case ":\${PATH}:" in
            *":\${PYTHON_INSTALL_PREFIX}/bin:"*) ;;
            *) printf 'PATH="%s/bin:%s"\n' "\${PYTHON_INSTALL_PREFIX}" "\${PATH}" >> /etc/environment ;;
        esac
    )
    updaterc "PYTHON_VERSION=\${VERSION}" true
    {
        echo "PYTHON_VERSION=\"\${VERSION}\""
        echo "PYTHON_LIBDIR=\"\${PYTHON_LIBDIR}\""
        echo "PYTHON_INSTALL_PATH=\"\${INSTALL_PATH}\""
    } >> /etc/environment
}

update_alternatives() {
    "\$LOGGER" "Configuring update-alternatives for Python \${PYTHON_VERSION}..."
    for py in python pip idle pydoc; do
        priority=\$((\$( get_alternatives_priority "\$py" "\$major_version") + 1))
        [ "\$priority" -ge 0 ] || priority=\$((priority + 1))
        if [ "\${ALTERNATIVES_PATH}" != "\${PYTHON_INSTALL_PREFIX}/bin" ]; then
            syspy="\$(readlink -f "\${SYSTEM_PYTHON%/bin/python*}/bin/\${py}\${major_minor_version}")"
            if type "\$syspy" > /dev/null 2>&1; then
                (set -x ; update-alternatives --install "\${ALTERNATIVES_PATH}/\${py}\${major_version}" "\${py}\${major_version}" "\$syspy" "\$priority" && priority="\$((priority + 1))")
            fi
        fi
        [ "\$priority" -ge 1 ] || priority=\$((priority + 1))
        {
            if type "\${PYTHON_INSTALL_PREFIX}/bin/\${py}" > /dev/null 2>&1 && ! type "\${ALTERNATIVES_PATH}/\${py}" >/dev/null 2>&1; then
                (set -x ; update-alternatives --install "\${ALTERNATIVES_PATH}/\${py}" "\${py}" "\${PYTHON_INSTALL_PREFIX}/bin/\${py}" "\$priority")
            fi
            if type "\${PYTHON_INSTALL_PREFIX}/bin/\${py}\${major_version}" > /dev/null 2>&1 && ! type "\${ALTERNATIVES_PATH}/\${py}" >/dev/null 2>&1; then
                (set -x ; update-alternatives --install "\${ALTERNATIVES_PATH}/\${py}" "\${py}" "\${PYTHON_INSTALL_PREFIX}/bin/\${py}\${major_version}" "\$priority")
            fi
            if type "\${PYTHON_INSTALL_PREFIX}/bin/\${py}\${major_version}" > /dev/null 2>&1 && ! type "\${ALTERNATIVES_PATH}/\${py}\${major_version}" >/dev/null 2>&1; then
                (set -x ; update-alternatives --install "\${ALTERNATIVES_PATH}/\${py}\${major_version}" "\${py}\${major_version}" "\${PYTHON_INSTALL_PREFIX}/bin/\${py}\${major_version}" "\$priority")
            fi
        } && priority="\$((priority + 1))"
    done
    for suffix in "-config"; do
        prefix="python"
        for version in \${major_minor_version}; do
            tool="\${prefix}\${suffix}"
            py_major="\${prefix}\${version%.*}\${suffix}"
            py="\${prefix}\${version}\${suffix}"
            priority=\$((\$( get_alternatives_priority "\$py") + 1))
            [ "\$priority" -ge 0 ] || priority=\$((priority + 1))
            if [ "\${ALTERNATIVES_PATH}" != "\${PYTHON_INSTALL_PREFIX}/bin" ]; then
                syspy="\$(readlink -f "\${SYSTEM_PYTHON%/bin/python*}/bin/\${py}")"
                if type "\$syspy" >/dev/null 2>&1; then
                    (set -x ; update-alternatives --install "\${ALTERNATIVES_PATH}/\${py}" "\${py}" "\$syspy" "\$priority" && priority="\$((priority + 1))")
                fi
            fi
            [ "\$priority" -ge 1 ] || priority=\$((priority + 1))
            {
                if type "\${PYTHON_INSTALL_PREFIX}/bin/\${py_major}" > /dev/null 2>&1 && ! type "\${ALTERNATIVES_PATH}/\${tool}" >/dev/null 2>&1; then
                    (set -x ; update-alternatives --install "\${ALTERNATIVES_PATH}/\${tool}" "\${tool}" "\${PYTHON_INSTALL_PREFIX}/bin/\${py_major}" "\$priority")
                fi
                if type "\${PYTHON_INSTALL_PREFIX}/bin/\${py_major}" > /dev/null 2>&1 && ! type "\${ALTERNATIVES_PATH}/\${py}" >/dev/null 2>&1; then
                    (set -x ; update-alternatives --install "\${ALTERNATIVES_PATH}/\${py}" "\${py}" "\${PYTHON_INSTALL_PREFIX}/bin/\${py_major}" "\$priority")
                fi
                if type "\${PYTHON_INSTALL_PREFIX}/bin/\${py}" > /dev/null 2>&1 && ! type "\${ALTERNATIVES_PATH}/\${py}" >/dev/null 2>&1; then
                    (set -x ; update-alternatives --install "\${ALTERNATIVES_PATH}/\${py}" "\${py}" "\${PYTHON_INSTALL_PREFIX}/bin/\${py}" "\$priority")
                fi
            } && priority="\$((priority + 1))"
        done
    done
}

install_tools() {
    if [ "\$INSTALL_TOOLS" = "true" ]; then
        if [ "\${1:-false}" = "true" ]; then
            "\$PIP_INSTALL" --upgrade pip && return || return 1
        fi
        "\$LOGGER" "Installing Python tools: {\${PYTHON_TOOLS}}..."
        for tool in \$PYTHON_TOOLS; do
            ! type "\${PYTHON_INSTALL_PREFIX}/bin/\${tool}" >/dev/null 2>&1 || continue
            LEVEL='*' "\$LOGGER" "Installing Python tool: \${tool}..."
            "\$PIP_INSTALL" "\${tool}"
        done
    fi
}

update_packages() {
    if [ "\$UPDATE_PACKAGES" = "true" ]; then
        LEVEL='*' "\$LOGGER" "Updating system packages for Python \${PYTHON_VERSION}..."
        [ "\$UPDATE_NCURSES" != "true" ] || PYTHON_INSTALL_PATH="\$PYTHON_LIBDIR" DEB_DIR="\$PYTHON_LIBDIR" "\${PYTHON_LIBDIR}/ncurses-install.sh" false
        [ "\$UPDATE_READLINE" != "true" ] || PYTHON_INSTALL_PATH="\$PYTHON_LIBDIR" DEB_DIR="\$PYTHON_LIBDIR" "\${PYTHON_LIBDIR}/readline-install.sh" false
    fi
}

main() {
    if [ "\${1-}" = "false" ]; then
        update_env
    else
        install_tools true

        if [ "\${1-}" = "true" ]; then
            # make_links
            update_alternatives
        else
            update_env
            # make_links
            update_packages
            update_alternatives
        fi
    fi

    install_tools
}

main "\$@"

LEVEL='√' "\$LOGGER" "Python \${PYTHON_VERSION} configuration complete. Installed at \${INSTALL_PATH}."
EOF
}

main() {
    install_dependencies
    prep_install
    install_python
    create_pip_installer
    upgrade_pip
    create_setup
    remove_llvm
    remove_packages "${PACKAGES_TO_REMOVE-}"
}

main "$@"

LEVEL='√' $LOGGER "Done! Python ${VERSION} installed at ${INSTALL_PATH}."
