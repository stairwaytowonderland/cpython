# Must be debian-based image
ARG IMAGE_NAME=ubuntu
ARG VARIANT=${VARIANT:-latest}
# ARG PARENT_IMAGE=${IMAGE_NAME}:${VARIANT}
ARG PYTHON_VERSION=current
ARG INSTALL_TOOLS=false
ARG PYTHON_DEV=false
ARG PYTHON_INSTALL_PREFIX=/usr/local
ARG PYTHON_INSTALL_PATH=${PYTHON_INSTALL_PREFIX%/}/lib
ARG SCRIPT_PATH=/usr/local/bin
ARG LOGGER=$SCRIPT_PATH/logger.sh
ARG PIP_INSTALL=$SCRIPT_PATH/pip-install.sh
ARG INSTALL_HELPER=$SCRIPT_PATH/install-helper.sh
ARG MAKEFLAGS="-j 8 --no-print-directory"
FROM dhi.io/debian-base:${VARIANT} AS dhi
FROM ubuntu:${VARIANT} AS ubuntu
FROM debian:${VARIANT} AS debian


FROM $IMAGE_NAME AS builder

ARG IMAGE_NAME \
    PYTHON_VERSION \
    PYTHON_INSTALL_PREFIX \
    PYTHON_INSTALL_PATH \
    INSTALL_TOOLS \
    SCRIPT_PATH \
    LOGGER \
    PIP_INSTALL \
    INSTALL_HELPER \
    TIMEZONE=UTC \
    USERNAME=appuser \
    USER_UID=1000 \
    USER_GID=1000 \
    MAKEFLAGS \
    PYTHON_DEV  \
    LLVM_VERSION=18 \
    ENABLE_PRE_RELEASE=true \
    ENABLE_SHARED=true \
    ENABLE_OPTIMIZATIONS=false \
    UPDATE_PACKAGES=false \
    UPGRADE_DIST=$PYTHON_DEV \
    ENABLE_BOLT=$PYTHON_DEV \
    UPDATE_NCURSES=$PYTHON_DEV \
    UPDATE_READLINE=$PYTHON_DEV \
    SYSTEM_INSTALL_PREFIX=/usr \
    PIP_INSTALL_FLAGS="--no-cache-dir --disable-pip-version-check --break-system-packages --root-user-action=ignore" \
    PYTHON_TOOLS="pipx poetry uv"

# Set non-interactive mode for apt-get to avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive \
    # Prevent Python from writing .pyc files (keeps source code directories free of __pycache__ folders and .pyc files)
    PYTHONDONTWRITEBYTECODE=1 \
    # Ensure Python output is sent straight to the terminal without buffering (important for logging)
    PYTHONUNBUFFERED=1

# COPY --chmod=755 docker/lib-scripts/*-install.sh /tmp/lib-scripts/
# COPY --chmod=755 docker/utils/logger.sh $LOGGER
# COPY docker/helpers/install-helper.sh $INSTALL_HELPER
# * Copy everything to $SCRIPT_PATH to reduce the number of layers
COPY --chmod=755 docker/utils/*.sh docker/helpers/*.sh docker/lib-scripts/*.sh $SCRIPT_PATH/

USER root

RUN \
  # ---------------------------------------------
  # 01. PRE-INSTALLATION: Install necessary build tools and dependencies
  PACKAGES_TO_INSTALL="ca-certificates build-essential wget pkg-config checkinstall git openssl" \
  && PACKAGES_TO_KEEP="openssl" \
  && { [ "$PYTHON_DEV" = "true" ] || PACKAGES_TO_REMOVE="linux-libc-dev"; } \
  && apt-get update \
  && apt-get install -y --no-install-recommends $PACKAGES_TO_INSTALL \
  # Optionally perform a dist-upgrade and install any security updates
  && { [ "$UPGRADE_DIST" != "true" ] || apt-get -s dist-upgrade | grep "^Inst" | grep -i securi | cut -d " " -f 2 | xargs apt-get install -y --no-install-recommends; } \
  # ---------------------------------------------
  # 02. INSTALLATION: Install Python (and first optionally update ncurses and readline)
  && { [ "$UPDATE_NCURSES" != "true" ] || $SCRIPT_PATH/ncurses-install.sh; } \
  && { [ "$UPDATE_READLINE" != "true" ] || $SCRIPT_PATH/readline-install.sh; } \
  && $SCRIPT_PATH/python-install.sh \
  # ---------------------------------------------
  # 03. POST-INSTALLATION
  # i. Persist installed Python .deb packages and installation scripts (if UPDATE_PACKAGES is true)
  && if [ "$UPDATE_PACKAGES" = "true" ]; then \
    # Move the installed Python .deb packages to the specified installation path for copying to subsequent stages
    mv /tmp/*.deb "${PYTHON_INSTALL_PATH}/" \
    # Persist the necessary installation scripts for ncurses and readline
    && mv $SCRIPT_PATH/ncurses-install.sh "${PYTHON_INSTALL_PATH}/" \
    && mv $SCRIPT_PATH/readline-install.sh "${PYTHON_INSTALL_PATH}/"; \
  fi \
  # ii. Run the post-install python-setup script to perform any necessary post-installation setup (e.g. creating symlinks, updating environment variables, etc.)
  && "${PYTHON_INSTALL_PATH}/python-setup" false \
  && . /etc/environment \
  && "${PYTHON_LIBDIR}/python-setup" true \
  # ---------------------------------------------
  # 04. USER SETUP: Create a non-root user
  # i. Check if the default user for the base image (e.g. 'ubuntu' for Ubuntu) exists, and delete it to avoid conflicts when creating our own non-root user with the same UID/GID
  && if [ "$IMAGE_NAME" = "ubuntu" ]; then \
    # As of Ubuntu 24 (Noble Numbat), the Ubuntu base image comes with a non-root user ubuntu with UID 1000.
    # Delete this user to avoid conflicts when creating our own non-root user.
    # Use 'userdel' to perform a shallow delete, and preserve htpasswd/group integrity for UID and GID.
    if id "ubuntu" >/dev/null 2>&1; then \
      $LOGGER "Deleting user 'ubuntu' for $IMAGE_NAME" \
        && userdel -r -f ubuntu > /dev/null 2>&1 \
        || LEVEL=error $LOGGER "Failed to delete ubuntu user for $IMAGE_NAME"; \
    else \
      $LOGGER "User 'ubuntu' does not exist for $IMAGE_NAME"; \
    fi; \
  fi \
  # ii. Create a non-root user, if it doesn't already exist
  && if ! id "$USERNAME" >/dev/null 2>&1; then \
    $LOGGER "Creating user '$USERNAME' with UID $USER_UID and GID $USER_GID for $IMAGE_NAME" \
      && groupadd --gid "$USER_GID" "$USERNAME" \
      && useradd --uid "$USER_UID" --gid "$USER_GID" -m "$USERNAME" -s /bin/bash \
      || LEVEL=error $LOGGER "Failed to create user '$USERNAME' for $IMAGE_NAME"; \
      if id "$USERNAME" >/dev/null 2>&1; then \
        $LOGGER "Changing ownership of /home/$USERNAME to $USERNAME" \
        && chown "$USERNAME:$USERNAME" -R /home/"$USERNAME"; \
      else \
        $LOGGER "User '$USERNAME' does not exist for $IMAGE_NAME"; \
        exit 1; \
      fi; \
  fi \
  # ---------------------------------------------
  # 05. CLEANUP: Remove unnecessary packages and files
  # i. Determine which packages to remove
  && for pkg in $PACKAGES_TO_INSTALL; do \
    case "$pkg" in \
      *$PACKAGES_TO_KEEP*) ;; \
      *) PACKAGES_TO_REMOVE="${PACKAGES_TO_REMOVE% } $pkg" ;; \
    esac; \
  done \
  # ii. Remove selected packages, first checking if they are installed (using dpkg -s) to avoid errors
  && for pkg in ${PACKAGES_TO_REMOVE-}; do \
    ! dpkg -s "$pkg" > /dev/null 2>&1 || apt-get -y remove --purge "$pkg"; \
  done \
  # iii. General Apt cleanup
  && rm -rf /var/lib/apt/lists/* \
  && apt-get -y autoremove \
  && apt-get clean -y \
  # iv. Remove any additional files
  && rm -rf /tmp/* \
  && find $SCRIPT_PATH -mindepth 1 -maxdepth 1 \
    -name ncurses-install.sh \
    -o -name readline-install.sh \
    -o -name python-install.sh \
    -exec rm -f {} \; \
  # ---------------------------------------------
  # 06. POST SETUP
  # Create a directory for the Python virtual environment and set ownership to the non-root user
  && mkdir -p /opt/venv \
  && chown $USERNAME:$USERNAME /opt/venv


FROM builder AS base

USER $USERNAME
WORKDIR /home/$USERNAME

CMD ["python3"]


FROM builder AS appbuilder

USER root
WORKDIR /src

# Copy application requirements
# COPY src/ .

# Install application dependencies
RUN [ ! -f requirements.txt ] || $PIP_INSTALL -r requirements.txt


FROM builder AS devcontainer

ARG USERNAME=vscode \
    VIRTUAL_ENV_ENABLED=false

ENV VIRTUAL_ENV_ENABLED=$VIRTUAL_ENV_ENABLED

# COPY --from=appbuilder /usr/local/bin /usr/local/bin/
COPY --from=appbuilder $PYTHON_INSTALL_PATH $PYTHON_INSTALL_PATH

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
    openssl \
    sudo \
	&& mkdir -p /opt/venv \
	&& chown $USERNAME:$USERNAME /opt/venv \
	# Cleanup
  && rm -rf /var/lib/apt/lists/* \
  && apt-get -y autoremove \
  && apt-get clean -y \
  && rm -rf /tmp/* \
	# Add the user to the sudo group with passwordless sudo permissions
	&& echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
	&& chmod 0440 "/etc/sudoers.d/$USERNAME" \
	# Create a post-create script to set permissions on the /app directory for the non-root user
	&& touch /usr/local/bin/post-start \
	&& chmod +x /usr/local/bin/post-start \
  && cat <<EOF | tee -a /home/$USERNAME/.bashrc /root/.bashrc > /dev/null
if [ "\${VIRTUAL_ENV_ENABLED:-$VIRTUAL_ENV_ENABLED}" = "true" ] && \
  { [ -z "\${VIRTUAL_ENV:-}" ] || [ "\${VIRTUAL_ENV:-}" != "/opt/venv" ]; }; then
  python3 -m venv --prompt /opt/venv /opt/venv
  # VIRTUAL_ENV_DISABLE_PROMPT=1 . /opt/venv/bin/activate
  . /opt/venv/bin/activate
fi
EOF

RUN cat >> /usr/local/bin/post-start <<'EOF'
#!/bin/sh
set -e
python3 --version
EOF

USER $USERNAME
WORKDIR /home/$USERNAME

COPY --chown=$USERNAME:$USERNAME . .

RUN if [ "$VIRTUAL_ENV_ENABLED" = "true" ]; then \
    python3 -m venv --prompt /opt/venv /opt/venv \
    && . /opt/venv/bin/activate \
    && { [ ! -f requirements-dev.txt ] || python3 -m pip install --upgrade --no-cache-dir -r requirements-dev.txt; }; \
  fi


FROM builder AS app

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    openssl \
    tini \
  # Cleanup
  && rm -rf /tmp/* \
  && apt-get clean -y \
  && apt-get -y autoremove \
  && rm -rf /var/lib/apt/lists/*

USER $USERNAME
WORKDIR /app

# Copy Python installation from the builder stage
COPY --from=appbuilder /usr/local/bin /usr/local/bin/
COPY --from=appbuilder $PYTHON_INSTALL_PATH $PYTHON_INSTALL_PATH
# Copy application code
# COPY --chown=$USERNAME:$USERNAME src/ .

# Expose the application port
# dockerfile-utils: ignore
EXPOSE "${BIND_ADDR##*:}"

# dockerfile-utils: ignore
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
	CMD wget -qO- http://localhost/"${BIND_ADDR##*:}"/gtg || exit 1

ENTRYPOINT ["/usr/bin/tini", "--"]

# Run the application (e.g. with gunicorn)
# CMD ["gunicorn", "-c", "gunicorn.py", "api:app"]
