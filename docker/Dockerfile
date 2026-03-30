# Must be debian-based image
ARG IMAGE_NAME=ubuntu
ARG VARIANT=${VARIANT:-latest}
ARG PARENT_IMAGE=${IMAGE_NAME}:${VARIANT}
ARG PYTHON_VERSION=latest
ARG INSTALL_TOOLS=false
ARG PYTHON_DEV=false
ARG PYTHON_INSTALL_PREFIX=/usr/local
ARG PYTHON_INSTALL_PATH=${PYTHON_INSTALL_PREFIX%/}/lib
ARG LOGGER=/usr/local/bin/logger.sh
ARG PIP_INSTALL=/usr/local/bin/pip-install.sh
ARG INSTALL_HELPER=/usr/local/bin/install-helper.sh
ARG MAKEFLAGS="-j 8 --no-print-directory"
FROM $PARENT_IMAGE AS builder

ARG IMAGE_NAME \
    PARENT_IMAGE \
    PYTHON_VERSION \
    PYTHON_INSTALL_PREFIX \
    PYTHON_INSTALL_PATH \
    INSTALL_TOOLS \
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
    ENABLE_PRE_RELEASE=false \
    ENABLE_SHARED=true \
    ENABLE_OPTIMIZATIONS=false \
    ENABLE_BOLT=$PYTHON_DEV \
    UPDATE_NCURSES=$PYTHON_DEV \
    UPDATE_READLINE=$PYTHON_DEV \
    UPDATE_PACKAGES=$PYTHON_DEV \
    SYSTEM_INSTALL_PREFIX=/usr \
    PIP_INSTALL_FLAGS="--no-cache-dir --disable-pip-version-check --break-system-packages --root-user-action=ignore" \
    PYTHON_TOOLS="pipx poetry uv"

# Set non-interactive mode for apt-get to avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive \
    # Prevent Python from writing .pyc files (keeps source code directories free of __pycache__ folders and .pyc files)
    PYTHONDONTWRITEBYTECODE=1 \
    # Ensure Python output is sent straight to the terminal without buffering (important for logging)
    PYTHONUNBUFFERED=1
    # Custom environment variables for debugging the builder stage
    # PYTHON_VERSION=$PYTHON_VERSION \
    # PYTHON_INSTALL_PREFIX=$PYTHON_INSTALL_PREFIX \
    # PYTHON_INSTALL_PATH=$PYTHON_INSTALL_PATH \
    # INSTALL_TOOLS=$INSTALL_TOOLS \
    # PYTHON_DEV=$PYTHON_DEV \
    # LOGGER=$LOGGER \
    # PIP_INSTALL=$PIP_INSTALL \
    # INSTALL_HELPER=$INSTALL_HELPER \
    # PIP_INSTALL_FLAGS="$PIP_INSTALL_FLAGS" \
    # MAKEFLAGS="$MAKEFLAGS" \
    # ENABLE_PRE_RELEASE=$ENABLE_PRE_RELEASE \
    # ENABLE_SHARED=$ENABLE_SHARED \
    # ENABLE_OPTIMIZATIONS=$ENABLE_OPTIMIZATIONS \
    # ENABLE_BOLT=$ENABLE_BOLT \
    # SYSTEM_INSTALL_PREFIX=$SYSTEM_INSTALL_PREFIX \
    # UPDATE_NCURSES=$UPDATE_NCURSES \
    # UPDATE_READLINE=$UPDATE_READLINE \
    # UPDATE_PACKAGES=$UPDATE_PACKAGES

# Copy library scripts, utilities, and helpers for installing Python and dependencies.
# These will be used in this builder stage to install Python, and then copied to subsequent stages as needed.
COPY --chmod=755 docker/lib-scripts/*-install.sh /tmp/lib-scripts/
COPY --chmod=755 docker/utils/logger.sh $LOGGER
COPY docker/helpers/install-helper.sh $INSTALL_HELPER

USER root

RUN \
  PACKAGES_TO_INSTALL="ca-certificates build-essential wget pkg-config checkinstall git openssl" \
  && PACKAGES_TO_KEEP="openssl" \
  && apt-get update \
  && apt-get install -y --no-install-recommends $PACKAGES_TO_INSTALL \
    # Either already included or installded as a dependency (probably of build-essential),
    # but listed here for clarity and to ensure availability for the Python installation process
    # gcc \
    # make \
    # tar \
    # xz-utils \
  && { [ "$UPDATE_NCURSES" != "true" ] || /tmp/lib-scripts/ncurses-install.sh; } \
  && { [ "$UPDATE_READLINE" != "true" ] || /tmp/lib-scripts/readline-install.sh; } \
  && /tmp/lib-scripts/python-install.sh \
  && if [ "$UPDATE_PACKAGES" = "true" ]; then \
    # Move the installed Python .deb packages to the specified installation path for copying to subsequent stages
    mv /tmp/*.deb "${PYTHON_INSTALL_PATH}/" \
    # Persist the necessary installation scripts for ncurses and readline
    && mv /tmp/lib-scripts/ncurses-install.sh "${PYTHON_INSTALL_PATH}/" \
    && mv /tmp/lib-scripts/readline-install.sh "${PYTHON_INSTALL_PATH}/"; \
  fi \
  # Cleanup build dependencies but keep the Python installation
  && [ "$PYTHON_DEV" = "true" ] || find "${PYTHON_INSTALL_PREFIX%/}/include" -mindepth 1 -maxdepth 1 -exec rm -rf {} \; \
  && [ "$PYTHON_DEV" = "true" ] || find "${PYTHON_INSTALL_PATH}/pkgconfig" -mindepth 1 -maxdepth 1 -exec rm -rf {} \; \
  && "${PYTHON_INSTALL_PATH}/python-setup" false \
  && . /etc/environment \
  && "${PYTHON_LIBDIR}/python-setup" true \
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
  # Create a non-root user to run the application, if it doesn't already exist
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
  && apt-get -s dist-upgrade | grep "^Inst" | grep -i securi | cut -d " " -f 2 | xargs apt-get install -y --no-install-recommends \
  # Cleanup
  && for pkg in $PACKAGES_TO_INSTALL; do \
      case "$pkg" in \
          *$PACKAGES_TO_KEEP*) ;; \
          *) PACKAGES_TO_REMOVE="${PACKAGES_TO_REMOVE% } $pkg" ;; \
      esac; \
  done \
  && for pkg in ${PACKAGES_TO_REMOVE-}; do \
      ! dpkg -s "$pkg" > /dev/null 2>&1 || apt-get -y remove --purge "$pkg"; \
  done \
  && rm -rf /tmp/* \
  && apt-get clean -y \
  && apt-get -y autoremove \
  && rm -rf /var/lib/apt/lists/*

USER $USERNAME
WORKDIR /home/$USERNAME


FROM builder AS appbuilder

USER root
WORKDIR /src

# Copy application requirements
# COPY src/ .

# Install application dependencies
RUN [ ! -f requirements.txt ] || $PIP_INSTALL -r requirements.txt


FROM builder AS devcontainer

ARG USERNAME=vscode

# COPY --from=appbuilder /usr/local/bin /usr/local/bin/
COPY --from=appbuilder $PYTHON_INSTALL_PATH $PYTHON_INSTALL_PATH

USER root

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
    sudo \
	&& mkdir -p /opt/venv \
	&& chown $USERNAME:$USERNAME /opt/venv \
	# Cleanup
  && rm -rf /tmp/* \
	&& apt-get clean -y \
	&& apt-get -y autoremove \
	&& rm -rf /var/lib/apt/lists/* \
	# Add the user to the sudo group with passwordless sudo permissions
	&& echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME" \
	&& chmod 0440 "/etc/sudoers.d/$USERNAME" \
	# Create a post-create script to set permissions on the /app directory for the non-root user
	&& touch /usr/local/bin/post-start \
	&& chmod +x /usr/local/bin/post-start \
	&& echo '. /opt/venv/bin/activate' >> /home/$USERNAME/.bashrc \
  && cat <<'EOF' | tee -a /home/$USERNAME/.bashrc /root/.bashrc > /dev/null
if [ "${VIRTUAL_ENV_ENABLED:-false}" = "true" ] && \
  { [ -z "${VIRTUAL_ENV:-}" ] || [ "${VIRTUAL_ENV:-}" != "/opt/venv" ]; }; then
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

RUN python3 -m venv --prompt /opt/venv \
	&& . /opt/venv/bin/activate \
	&& [ ! -f requirements-dev.txt ] \
    || python3 -m pip install --upgrade --no-cache-dir -r requirements-dev.txt


FROM builder AS app

USER root

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
