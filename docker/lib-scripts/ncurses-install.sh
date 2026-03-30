#!/bin/sh

# https://www.linuxfromscratch.org/lfs/view/development/chapter06/ncurses.html

# Only check for errors (set -e)
# Don't check for unset variables (set -u) since variables are set in Dockerfile
# Pipepail (set -o pipefail) is not available in sh
set -e

LEVEL='ƒ' $LOGGER "Installing ncurses from source..."

PYTHON_INSTALL_PREFIX="${PYTHON_INSTALL_PREFIX:-/opt/python}"
PYTHON_INSTALL_PATH="${PYTHON_INSTALL_PATH:-"${PYTHON_INSTALL_PREFIX%/}/lib"}"
SYSTEM_INSTALL_PREFIX="${SYSTEM_INSTALL_PREFIX:-/usr}"
NCURSES_INSTALL_PREFIX="${NCURSES_INSTALL_PREFIX:-$SYSTEM_INSTALL_PREFIX}"
DEB_DIR="${DEB_DIR:-/tmp}"

# shellcheck disable=SC1090
. "$INSTALL_HELPER"

export MAKEFLAGS="${MAKEFLAGS:-$(__default_makeflags)}"

PACKAGES_TO_INSTALL="$(
    cat << EOF
equivs
EOF
)"

install_dependencies() {
    for pkg in ${PACKAGES_TO_INSTALL-}; do
        if ! dpkg -s "$pkg" > /dev/null 2>&1; then
            _packages_to_install="${_packages_to_install% } $pkg"
        fi
    done

    PACKAGES_TO_INSTALL="$_packages_to_install"

    update_and_install "${PACKAGES_TO_INSTALL# }"
}

download_ncurses() {
    LEVEL='*' $LOGGER "Downloading ncurses (latest) from ${NCURSES_DOWNLOAD_URL}..."

    NCURSES_DOWNLOAD_URL="https://invisible-island.net/archives/ncurses/current/ncurses.tar.gz"

    cd /tmp
    __install_from_tarball "$NCURSES_DOWNLOAD_URL" "$PWD"
    DOWNLOAD_DIR="$(find "$PWD" -maxdepth 1 -type d -name 'ncurses-*' | head -n 1)"
}

install_ncurses() {
    LEVEL='*' $LOGGER "Building and installing ncurses to ${NCURSES_INSTALL_PREFIX}..."

    cwd="$PWD"
    download_ncurses

    if [ ! -d "$DOWNLOAD_DIR" ]; then
        LEVEL='error' $LOGGER "Failed to locate extracted ncurses source directory."
        exit 1
    fi

    cd "$DOWNLOAD_DIR"

    LEVEL='*' $LOGGER "Building tic (ncurses terminfo compiler) as a prerequisite for ncurses installation..."
    mkdir build && cd build
    mkdir -p "$PWD/bin"
    ../configure --prefix="$PWD" AWK=awk
    make -C include
    make -C progs tic
    install progs/tic "$PWD/bin"
    PATH="$PWD/bin:$PATH"
    cd "$cwd" && cd "$DOWNLOAD_DIR"

    LEVEL='*' $LOGGER "Configuring ncurses..."
    ./configure --prefix="$NCURSES_INSTALL_PREFIX" \
        --build="$(./config.guess)" \
        --mandir="${NCURSES_INSTALL_PREFIX}/share/man" \
        --with-shared \
        --with-termlib \
        --enable-widec \
        --enable-pc-files \
        --without-normal \
        --with-cxx-shared \
        --without-debug \
        --without-ada \
        --disable-stripping \
        --with-versioned-syms \
        --with-pkg-config-libdir="${NCURSES_INSTALL_PREFIX}/lib/pkgconfig" \
        AWK=awk

    LEVEL='*' $LOGGER "Building ncurses..."
    make

    LEVEL='*' $LOGGER "Creating .deb package with checkinstall..."
    ncurses_version="${DOWNLOAD_DIR##*ncurses-}"
    checkinstall \
        --type=debian \
        --install=no \
        --fstrans=no \
        --pkgname=ncurses \
        --pkgversion="$ncurses_version" \
        --pkgrelease=1 \
        --pkglicense=MIT \
        --pkggroup=libs \
        --requires="" \
        --replaces=libncursesw6,ncurses-bin \
        --conflicts=ncurses-bin \
        --pakdir=/tmp \
        --nodoc \
        --default \
        make install

    cat > "${PYTHON_INSTALL_PATH}/ncurses-env" << EOF
ncurses_version="$ncurses_version"
ncurses_major_version="${ncurses_version%%.*}"
ncurses_install_prefix="$NCURSES_INSTALL_PREFIX"
python_install_path="$PYTHON_INSTALL_PATH"
EOF
}

setup_ncurses() {
    LEVEL='*' $LOGGER "Setting up ncurses installation..."

    # shellcheck disable=SC1091
    . "${PYTHON_INSTALL_PATH}/ncurses-env"

    deb_file="$(find "$DEB_DIR" -maxdepth 1 -type f -name "ncurses_${ncurses_version}-1_*.deb" | head -n 1)"
    if [ -f "$deb_file" ]; then
        LEVEL='*' $LOGGER "Installing generated package: $deb_file"
        # Purge the Debian packages we're replacing before installing ours.
        # --force-depends bypasses reverse-dependency checks; the files they own
        # will be overwritten by our package, so their dependents continue to work.
        # shellcheck disable=SC2154
        dpkg --force-depends --purge "libncursesw${ncurses_major_version}" "libtinfo${ncurses_major_version}" "ncurses-base" "ncurses-bin" 2> /dev/null || true
        dpkg -i --force-overwrite "$deb_file"

        ln -sv libncursesw.so "${NCURSES_INSTALL_PREFIX}/lib/libncurses.so"
        type "${NCURSES_INSTALL_PREFIX}/lib/libncurses.so" > /dev/null 2>&1 || LEVEL='!' $LOGGER "Failed to create symlink for libncurses.so"
        ln -sv "libtinfow.so.${ncurses_major_version}" "${NCURSES_INSTALL_PREFIX}/lib/libtinfo.so.${ncurses_major_version}"
        type "${NCURSES_INSTALL_PREFIX}/lib/libtinfo.so.${ncurses_major_version}" > /dev/null 2>&1 || LEVEL='!' $LOGGER "Failed to create symlink for libtinfo.so.${ncurses_major_version}"
        ln -sv "libtinfow.so.${ncurses_major_version}" "${NCURSES_INSTALL_PREFIX}/lib/libtinfo.so"
        type "${NCURSES_INSTALL_PREFIX}/lib/libtinfo.so" > /dev/null 2>&1 || LEVEL='!' $LOGGER "Failed to create symlink for libtinfo.so"

        sed -e 's/^#if.*XOPEN.*$/#if 1/' -i "${NCURSES_INSTALL_PREFIX}/include/curses.h"

        # Create stub .deb packages so dpkg tracks libtinfo6 and ncurses-base
        # at the new ncurses version (files are already installed by our ncurses package)
        for stub_pkg in "libncursesw${ncurses_major_version}" "libtinfo${ncurses_major_version}" ncurses-base; do
            LEVEL='*' $LOGGER "Creating stub replacement package for ${stub_pkg}..."
            stub_dir="$(mktemp -d)"
            cat > "${stub_dir}/${stub_pkg}" << EOF
Section: libs
Priority: optional
Standards-Version: 4.7.3

Package: ${stub_pkg}
Version: ${ncurses_version}
Provides: ${stub_pkg}
Replaces: ${stub_pkg}
Conflicts: ${stub_pkg}
Description: Stub replacement for ${stub_pkg} provided by ncurses ${ncurses_version}
EOF
            ( cd "$stub_dir" && equivs-build "${stub_pkg}" )
            mv "${stub_dir}/${stub_pkg}"*.deb "$DEB_DIR/"
            dpkg -i --force-overwrite "$DEB_DIR/${stub_pkg}_${ncurses_version}_all.deb"
            rm -rf "$stub_dir"
        done
    else
        LEVEL='error' $LOGGER "Failed to locate generated .deb package for ncurses."
        exit 1
    fi
}

main() {
    _install=false
    install_dependencies

    if [ "${1-}" = "false" ]; then
        setup_ncurses
    elif [ "${1-}" = "true" ]; then
        _install=true
        install_ncurses
    else
        _install=true
        install_ncurses
        setup_ncurses
    fi

    if [ "$_install" = "true" ]; then
        cd "$cwd" && rm -rf "$DOWNLOAD_DIR"
        remove_packages "${PACKAGES_TO_INSTALL# }"
        LEVEL='√' $LOGGER "ncurses installed to ${NCURSES_INSTALL_PREFIX}."
    fi
}

main "$@"
