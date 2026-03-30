#!/bin/sh

# https://www.linuxfromscratch.org/lfs/view/development/chapter08/readline.html

# Only check for errors (set -e)
# Don't check for unset variables (set -u) since variables are set in Dockerfile
# Pipepail (set -o pipefail) is not available in sh
set -e

LEVEL='ƒ' $LOGGER "Installing readline from source..."

PYTHON_INSTALL_PREFIX="${PYTHON_INSTALL_PREFIX:-/opt/python}"
PYTHON_INSTALL_PATH="${PYTHON_INSTALL_PATH:-"${PYTHON_INSTALL_PREFIX%/}/lib"}"
SYSTEM_INSTALL_PREFIX="${SYSTEM_INSTALL_PREFIX:-/usr}"
READLINE_INSTALL_PREFIX="${READLINE_INSTALL_PREFIX:-$SYSTEM_INSTALL_PREFIX}"
NCURSES_INSTALL_PREFIX="${NCURSES_INSTALL_PREFIX:-$SYSTEM_INSTALL_PREFIX}"
DEB_DIR="${DEB_DIR:-/tmp}"

# shellcheck disable=SC1090
. "$INSTALL_HELPER"

export MAKEFLAGS="${MAKEFLAGS:-$(__default_makeflags)}"

install_dependencies() {
    for pkg in ${PACKAGES_TO_INSTALL-}; do
        if ! dpkg -s "$pkg" > /dev/null 2>&1; then
            _packages_to_install="${_packages_to_install% } $pkg"
        fi
    done

    PACKAGES_TO_INSTALL="$_packages_to_install"

    update_and_install "${PACKAGES_TO_INSTALL# }"
}

download_readline() {
    LEVEL='*' $LOGGER "Downloading readline from ${READLINE_DOWNLOAD_URL}..."

    cd /tmp
    __install_from_tarball "$READLINE_DOWNLOAD_URL" "$PWD"
    DOWNLOAD_DIR="$(find "$PWD" -maxdepth 1 -type d -name 'readline-*' | head -n 1)"
}

install_readline() {
    LEVEL='*' $LOGGER "Building and installing readline to ${READLINE_INSTALL_PREFIX}..."

    GIT_SERVER="git.savannah.gnu.org/git" \
        __find_version_from_git_tags "readline.git" "latest" "tags/readline-" "." "true"
    readline_version="$VERSION"
    READLINE_DOWNLOAD_URL="https://ftp.gnu.org/gnu/readline/readline-${readline_version}.tar.gz"

    cwd="$PWD"
    download_readline

    if [ ! -d "$DOWNLOAD_DIR" ]; then
        LEVEL='error' $LOGGER "Failed to locate extracted readline source directory."
        exit 1
    fi

    cd "$DOWNLOAD_DIR"

    # Prevent readline from installing its own docs where a previous version may exist
    sed -i '/MV.*old/d' Makefile.in
    sed -i '/{OLDSUFF}/c:' support/shlib-install

    LEVEL='*' $LOGGER "Configuring readline..."
    CFLAGS="-I${NCURSES_INSTALL_PREFIX}/include/ncursesw" \
        LDFLAGS="-L${NCURSES_INSTALL_PREFIX}/lib" \
        LIBS="-lncursesw" \
        ./configure \
            --prefix="$READLINE_INSTALL_PREFIX" \
            --with-curses \
            --disable-static \
            --enable-multibyte

    LEVEL='*' $LOGGER "Building readline..."
    make SHLIB_LIBS="-lncursesw"

    LEVEL='*' $LOGGER "Creating .deb package with checkinstall..."
    readline_version="${DOWNLOAD_DIR##*readline-}"
    checkinstall \
        --type=debian \
        --install=no \
        --fstrans=no \
        --pkgname=readline \
        --pkgversion="$readline_version" \
        --pkgrelease=1 \
        --pkglicense=GPL \
        --pkggroup=libs \
        --requires="" \
        --replaces=libreadline8,libreadline-dev \
        --conflicts=libreadline8,libreadline-dev \
        --pakdir=/tmp \
        --nodoc \
        --default \
        make install

    cat > "${PYTHON_INSTALL_PATH}/readline-env" << EOF
readline_version="$readline_version"
readline_major_version="${readline_version%%.*}"
readline_install_prefix="$READLINE_INSTALL_PREFIX"
python_install_path="$PYTHON_INSTALL_PATH"
EOF
}

setup_readline() {
    LEVEL='*' $LOGGER "Setting up readline library..."

    # shellcheck disable=SC1091
    . "${PYTHON_INSTALL_PATH}/readline-env"

    deb_file="$(find "$DEB_DIR" -maxdepth 1 -type f -name "readline_${readline_version}-1_*.deb" | head -n 1)"
    if [ -f "$deb_file" ]; then
        LEVEL='*' $LOGGER "Installing generated package: $deb_file"
        # shellcheck disable=SC2154
        # dpkg --force-depends --purge -i "libreadline${readline_major_version}" libreadline-dev || true
        dpkg -i --force-overwrite "$deb_file"

        #         ln -sv libreadline.so "${READLINE_INSTALL_PREFIX}/lib/libreadline.so"
        #         ln -sv "libreadline.so.${readline_major_version}" "${READLINE_INSTALL_PREFIX}/lib/libreadline.so.${readline_major_version}"
        #         ln -sv "libreadline.so.${readline_major_version}" "${READLINE_INSTALL_PREFIX}/lib/libreadline.so"

        #         for stub_pkg in libreadline-dev "libreadline${readline_major_version}"; do
        #             stub_dir="$(mktemp -d)"
        #                 cat > "${stub_dir}/${stub_pkg}" << EOF
        # Section: libs
        # Priority: optional
        # Standards-Version: 4.7.3

        # Package: ${stub_pkg}
        # Version: ${readline_version}-1
        # Provides: ${stub_pkg}
        # Replaces: ${stub_pkg}
        # Conflicts: ${stub_pkg}
        # Description: Stub replacement for ${stub_pkg} provided by readline ${readline_version}
        # EOF
        #             ( cd "$stub_dir" && equivs-build "${stub_pkg}" )
        #             mv "${stub_dir}/${stub_pkg}"*.deb "$DEB_DIR/"
        #             dpkg -i --force-overwrite "$DEB_DIR/${stub_pkg}_${readline_version}_all.deb"
        #             rm -rf "$stub_dir"
        #         done
    else
        LEVEL='error' $LOGGER "Failed to locate generated .deb package for readline."
        exit 1
    fi
}

main() {
    _install=false
    install_dependencies

    if [ "${1-}" = "false" ]; then
        setup_readline
    elif [ "${1-}" = "true" ]; then
        _install=true
        install_readline
    else
        _install=true
        install_readline
        setup_readline
    fi

    if [ "$_install" = "true" ]; then
        cd "$cwd" && rm -rf "$DOWNLOAD_DIR"
        remove_packages "${PACKAGES_TO_INSTALL# }"
        LEVEL='√' $LOGGER "readline installed to ${READLINE_INSTALL_PREFIX}."
    fi
}

main "$@"
