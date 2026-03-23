#!/usr/bin/env bash

REGISTRY_HOST="${REGISTRY_HOST:-registry-1.docker.io}"
REGISTRY_PROVIDER="${REGISTRY_PROVIDER:-Docker Hub}"
REGISTRY_PROVIDER_FQDN="${REGISTRY_PROVIDER_FQDN:-hub.docker.com}"

CR_PAT="${CR_PAT-}"

# Determine Container Registry username
if [ $# -gt 0 ]; then
    REGISTRY_USER="${1:-$REPO_NAMESPACE}"
    shift
fi
if [ -z "${REGISTRY_USER-}" ]; then
    echo "(!) Please provide your ${REGISTRY_PROVIDER} username as the first argument or set the REPO_NAMESPACE environment variable." >&2
    exit 1
fi

if [ $# -gt 0 ]; then
    REGISTRY_IMAGE="${1:-$REPO_NAME}"
    shift
fi

REGISTRY_URL_PREFIX="${REGISTRY_HOST}/${REGISTRY_USER}"

if [ "${LOGGED_IN:-false}" != "true" ]; then
    echo "(+) Logging in to ${REGISTRY_PROVIDER} Container Registry..." >&2
    echo "$CR_PAT" | docker login "$REGISTRY_HOST" -u "$REGISTRY_USER" --password-stdin \
        && export LOGGED_IN=true
    echo "You can now publish images to ${REGISTRY_URL_PREFIX}/${REGISTRY_IMAGE}" >&2
    echo "Re-run this script with LOGGED_IN=true to skip logging in again." >&2
    echo -e "\033[2m~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~\033[0m" >&2
fi
