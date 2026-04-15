#!/usr/bin/env bash
# ===========================================================================
# publish.sh — Push all built images to a container registry
#
# Usage:
#   REGISTRY=ghcr.io/myorg ./publish.sh          # push all versions
#   REGISTRY=ghcr.io/myorg ./publish.sh 8.4       # push only PHP 8.4 tags
#   REGISTRY=ghcr.io/myorg ./publish.sh 8.3 8.4   # push PHP 8.3 + 8.4
#
# Environment:
#   REGISTRY     — registry prefix     (REQUIRED, e.g. ghcr.io/myorg)
#   IMAGE_NAME   — image name          (default: docker-laravel)
#   DRY_RUN      — set to 1 to print commands without executing
# ===========================================================================
set -euo pipefail

if [ -z "${REGISTRY:-}" ]; then
    echo "ERROR: REGISTRY is required."
    echo ""
    echo "Usage: REGISTRY=ghcr.io/myorg ./publish.sh [php_versions...]"
    echo ""
    echo "Examples:"
    echo "  REGISTRY=ghcr.io/myorg ./publish.sh"
    echo "  REGISTRY=docker.io/myuser ./publish.sh 8.4"
    exit 1
fi

IMAGE_NAME="${IMAGE_NAME:-docker-laravel}"
LOCAL="${IMAGE_NAME}"
REMOTE="${REGISTRY}/${IMAGE_NAME}"

# ---------------------------------------------------------------------------
# PHP → Laravel version mapping (must match build.sh)
# ---------------------------------------------------------------------------
declare -A PHP_LARAVEL_MAP=(
    ["7.4"]=""
    ["8.0"]="9"
    ["8.1"]="9 10"
    ["8.2"]="9 10 11 12"
    ["8.3"]="10 11 12 13"
    ["8.4"]="11 12 13"
    ["8.5"]="12 13"
)

declare -A LARAVEL_RECOMMENDED_PHP=(
    ["9"]="8.1"
    ["10"]="8.3"
    ["11"]="8.4"
    ["12"]="8.5"
    ["13"]="8.5"
)

LATEST_PHP="8.4"
ALL_PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3" "8.4" "8.5")

# ---------------------------------------------------------------------------
# Determine which versions to push
# ---------------------------------------------------------------------------
if [ $# -gt 0 ]; then
    PUSH_VERSIONS=("$@")
else
    PUSH_VERSIONS=("${ALL_PHP_VERSIONS[@]}")
fi

for v in "${PUSH_VERSIONS[@]}"; do
    if [[ ! -v "PHP_LARAVEL_MAP[$v]" ]]; then
        echo "ERROR: Unknown PHP version: $v"
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------
run() {
    if [ "${DRY_RUN:-0}" = "1" ]; then
        echo "[dry-run] $*"
    else
        "$@"
    fi
}

tag_and_push() {
    local LOCAL_TAG="$1"
    local REMOTE_TAG="$2"
    run docker tag "${LOCAL_TAG}" "${REMOTE_TAG}"
    run docker push "${REMOTE_TAG}"
}

# ---------------------------------------------------------------------------
# Push
# ---------------------------------------------------------------------------
TOTAL=0
PUSHED=0

for PHP_VERSION in "${PUSH_VERSIONS[@]}"; do
    echo ""
    echo "==========================================="
    echo "  Pushing PHP ${PHP_VERSION}"
    echo "==========================================="

    # Base PHP tag
    tag_and_push "${LOCAL}:php${PHP_VERSION}" "${REMOTE}:php${PHP_VERSION}"
    TOTAL=$((TOTAL + 1)); PUSHED=$((PUSHED + 1))

    # Laravel combo tags
    LARAVEL_VERSIONS="${PHP_LARAVEL_MAP[$PHP_VERSION]}"
    for LV in $LARAVEL_VERSIONS; do
        tag_and_push "${LOCAL}:php${PHP_VERSION}" "${REMOTE}:laravel${LV}-php${PHP_VERSION}"
        TOTAL=$((TOTAL + 1)); PUSHED=$((PUSHED + 1))

        # Bare laravelN tag
        if [ "${LARAVEL_RECOMMENDED_PHP[$LV]}" = "$PHP_VERSION" ]; then
            tag_and_push "${LOCAL}:php${PHP_VERSION}" "${REMOTE}:laravel${LV}"
            TOTAL=$((TOTAL + 1)); PUSHED=$((PUSHED + 1))
        fi
    done

    # latest
    if [ "$PHP_VERSION" = "$LATEST_PHP" ]; then
        tag_and_push "${LOCAL}:php${PHP_VERSION}" "${REMOTE}:latest"
        TOTAL=$((TOTAL + 1)); PUSHED=$((PUSHED + 1))
    fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==========================================="
echo "  Publish complete"
echo "==========================================="
echo "Pushed ${PUSHED} tags to ${REGISTRY}/${IMAGE_NAME}"
