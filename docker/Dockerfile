# Must be debian-based image
ARG IMAGE_NAME=ubuntu
ARG VARIANT=${VARIANT:-latest}
ARG PARENT_IMAGE=${IMAGE_NAME}:${VARIANT}
ARG PYTHON_VERSION=latest
ARG INSTALL_TOOLS=false
ARG PYTHON_INSTALL_PREFIX=/usr/local
ARG PYTHON_INSTALL_PATH=${PYTHON_INSTALL_PREFIX%/}/lib
ARG LOGGER=/usr/local/bin/logger.sh
ARG PIP_INSTALL=/usr/local/bin/pip-install.sh
ARG INSTALL_HELPER=/usr/local/bin/install-helper.sh
FROM $PARENT_IMAGE AS pybuilder

ARG IMAGE_NAME
ARG PARENT_IMAGE
ARG PYTHON_VERSION
ARG PYTHON_INSTALL_PREFIX
ARG PYTHON_INSTALL_PATH
ARG INSTALL_TOOLS
ARG LOGGER
ARG PIP_INSTALL
ARG INSTALL_HELPER

ARG PIP_INSTALL_FLAGS="--no-cache-dir --disable-pip-version-check --ignore-installed --break-system-packages --root-user-action=ignore"

# Set non-interactive mode for apt-get to avoid prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
# Prevent Python from writing .pyc files (keeps source code directories free of __pycache__ folders and .pyc files)
ENV PYTHONDONTWRITEBYTECODE=1
# Ensure Python output is sent straight to the terminal without buffering (important for logging)
ENV PYTHONUNBUFFERED=1

# Copy library scripts, utilities, and helpers for installing Python and dependencies.
# These will be used in this builder stage to install Python, and then copied to subsequent stages as needed.
COPY --chmod=755 docker/lib-scripts/python-install.sh /tmp/lib-scripts/
COPY --chmod=755 docker/utils/logger.sh $LOGGER
COPY docker/helpers/install-helper.sh $INSTALL_HELPER

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends openssl \
  && /tmp/lib-scripts/python-install.sh \
  # Cleanup build dependencies but keep the Python installation
  && rm -rf ${PYTHON_INSTALL_PREFIX%/}/include/* \
  # && find "$PYTHON_INSTALL_PREFIX/include" -mindepth 1 -maxdepth 1 -exec rm -rf {} \; \
  && apt-get clean -y \
  && apt-get -y autoremove \
  && rm -rf /var/lib/apt/lists/*

RUN $PYTHON_INSTALL_PATH/setup true \
    && . /etc/environment \
    && VERSION="$PYTHON_VERSION" \
    && touch $PIP_INSTALL \
    && chmod +x $PIP_INSTALL \
    && cat > $PIP_INSTALL <<EOF
#!/bin/sh
set -e
pip_install() {
  "${PYTHON_INSTALL_PREFIX%/}/bin/python${VERSION%.*}" -m pip install $PIP_INSTALL_FLAGS "\$@"
}
pip_install "\$@"
EOF

RUN $PIP_INSTALL --upgrade pip \
    # setuptools wheel \
  && for tool in pipx poetry uv; do \
    LEVEL='*' $LOGGER "Installing $tool..." \
      && { [ "$INSTALL_TOOLS" != "true" ] || $PIP_INSTALL "$tool"; } \
      || LEVEL='error' $LOGGER "Failed to install $tool"; \
  done \
  && $PYTHON_INSTALL_PATH/setup false \
  && rm -rf /tmp/*


FROM $PARENT_IMAGE AS base

ARG PYTHON_INSTALL_PATH \
    INSTALL_TOOLS \
    LOGGER \
    PIP_INSTALL \
    INSTALL_HELPER \
    TIMEZONE=UTC \
    USERNAME=appuser \
    USER_UID=1000 \
    USER_GID=1000 \
    DEBUG=false \
    BIND_ADDR=0.0.0.0:8000

ENV TZ=$TIMEZONE \
    # Set non-interactive mode for apt-get to avoid prompts during package installation
    DEBIAN_FRONTEND=noninteractive \
    # Prevent Python from writing .pyc files (keeps source code directories free of __pycache__ folders and .pyc files)
    PYTHONDONTWRITEBYTECODE=1 \
    # Ensure Python output is sent straight to the terminal without buffering (important for logging)
    PYTHONUNBUFFERED=1

COPY --from=pybuilder $LOGGER $PIP_INSTALL $INSTALL_HELPER /usr/local/bin /usr/local/bin/
COPY --from=pybuilder $PYTHON_INSTALL_PATH $PYTHON_INSTALL_PATH

USER root

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
    ca-certificates \
    jq \
    openssl \
		tini \
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
  && apt-get -s dist-upgrade | grep "^Inst" | grep -i securi | cut -d " " -f 2 | xargs apt-get install -y --no-install-recommends \
  && $PYTHON_INSTALL_PATH/setup \
	# Cleanup
  && rm -rf /tmp/* \
	&& apt-get clean -y \
	&& apt-get -y autoremove \
	&& rm -rf /var/lib/apt/lists/* \
	# Create a non-root user to run the application, if it doesn't already exist
	&& id "$USERNAME" >/dev/null 2>&1 || { \
		groupadd --gid "$USER_GID" "$USERNAME" \
		&& useradd --uid "$USER_UID" --gid "$USER_GID" -m "$USERNAME" -s /bin/bash; \
	} || true

USER $USERNAME
WORKDIR /home/$USERNAME


FROM base AS appbuilder

USER root
WORKDIR /src

# Copy application requirements
# COPY src/ .

# Install application dependencies
RUN [ ! -f requirements.txt ] || $PIP_INSTALL -r requirements.txt


FROM base AS devcontainer

ARG USERNAME=vscode

COPY --from=pybuilder /usr/local/bin /usr/local/bin/
COPY --from=appbuilder $PYTHON_INSTALL_PATH $PYTHON_INSTALL_PATH

USER root

RUN apt-get update \
	&& apt-get install -y --no-install-recommends sudo \
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
	&& cat >> /usr/local/bin/post-start <<'EOF'
#!/bin/sh
set -e
python3 --version
EOF

USER $USERNAME
WORKDIR /home/$USERNAME

COPY --chown=$USERNAME:$USERNAME . .

RUN python3 -m venv /opt/venv \
	&& . /opt/venv/bin/activate \
	&& [ ! -f requirements-dev.txt ] \
    || python3 -m pip install --upgrade --no-cache-dir -r requirements-dev.txt \
	&& echo '. /opt/venv/bin/activate' >> /home/$USERNAME/.bashrc


FROM base AS app

USER $USERNAME
WORKDIR /app

# Copy Python installation from the builder stage
COPY --from=pybuilder /usr/local/bin /usr/local/bin/
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
