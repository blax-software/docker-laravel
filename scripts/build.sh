#!/usr/bin/env bash
# ===========================================================================
# build.sh — Build all PHP version images with full Laravel tag matrix
#
# Usage:
#   ./build.sh                  # build all versions
#   ./build.sh 8.4              # build only PHP 8.4
#   ./build.sh 8.3 8.4          # build PHP 8.3 + 8.4
#
# Environment:
#   IMAGE_NAME   — image name          (default: docker-laravel)
#   NODE_MAJOR   — Node.js major ver   (default: 22)
#   PLATFORM     — e.g. linux/amd64    (default: current platform)
# ===========================================================================
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-blaxsoftware/laravel}"
NODE_MAJOR="${NODE_MAJOR:-22}"

# ---------------------------------------------------------------------------
# PHP → Laravel version mapping
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

# Recommended (highest) PHP version per Laravel version → gets the bare `laravelN` tag
declare -A LARAVEL_RECOMMENDED_PHP=(
    ["9"]="8.1"
    ["10"]="8.3"
    ["11"]="8.4"
    ["12"]="8.5"
    ["13"]="8.5"
)

# Which PHP version gets the `latest` tag
LATEST_PHP="8.4"

ALL_PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3" "8.4" "8.5")

# ---------------------------------------------------------------------------
# Determine which versions to build
# ---------------------------------------------------------------------------
if [ $# -gt 0 ]; then
    BUILD_VERSIONS=("$@")
else
    BUILD_VERSIONS=("${ALL_PHP_VERSIONS[@]}")
fi

# Validate requested versions
for v in "${BUILD_VERSIONS[@]}"; do
    if [[ ! -v "PHP_LARAVEL_MAP[$v]" ]]; then
        echo "ERROR: Unknown PHP version: $v"
        echo "Available: ${ALL_PHP_VERSIONS[*]}"
        exit 1
    fi
done

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
TOTAL=${#BUILD_VERSIONS[@]}
CURRENT=0
FAILED=()

PLATFORM_ARG=""
if [ -n "${PLATFORM:-}" ]; then
    PLATFORM_ARG="--platform=${PLATFORM}"
fi

for PHP_VERSION in "${BUILD_VERSIONS[@]}"; do
    CURRENT=$((CURRENT + 1))

    # Collect all tags for this PHP version
    TAGS=()
    TAGS+=("${IMAGE_NAME}:php${PHP_VERSION}")

    # Laravel combo tags: laravel12-php8.4, etc.
    LARAVEL_VERSIONS="${PHP_LARAVEL_MAP[$PHP_VERSION]}"
    for LV in $LARAVEL_VERSIONS; do
        TAGS+=("${IMAGE_NAME}:laravel${LV}-php${PHP_VERSION}")

        # Convenience bare tag: laravelN → recommended PHP
        if [ "${LARAVEL_RECOMMENDED_PHP[$LV]}" = "$PHP_VERSION" ]; then
            TAGS+=("${IMAGE_NAME}:laravel${LV}")
        fi
    done

    # latest tag
    if [ "$PHP_VERSION" = "$LATEST_PHP" ]; then
        TAGS+=("${IMAGE_NAME}:latest")
    fi

    TAG_ARGS=""
    TAG_LIST=""
    for T in "${TAGS[@]}"; do
        TAG_ARGS="${TAG_ARGS} -t ${T}"
        TAG_LIST="${TAG_LIST}  ${T}\n"
    done

    echo ""
    echo "==========================================="
    echo "  [${CURRENT}/${TOTAL}] Building PHP ${PHP_VERSION}"
    echo "==========================================="
    echo -e "Tags:\n${TAG_LIST}"

    if docker build ${PLATFORM_ARG} \
        --build-arg PHP_VERSION="${PHP_VERSION}" \
        --build-arg NODE_MAJOR="${NODE_MAJOR}" \
        ${TAG_ARGS} \
        . ; then
        echo "[${CURRENT}/${TOTAL}] PHP ${PHP_VERSION} — OK"
    else
        echo "[${CURRENT}/${TOTAL}] PHP ${PHP_VERSION} — FAILED"
        FAILED+=("$PHP_VERSION")
    fi
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "==========================================="
echo "  Build complete"
echo "==========================================="
echo "Succeeded: $((TOTAL - ${#FAILED[@]}))/${TOTAL}"

if [ ${#FAILED[@]} -gt 0 ]; then
    echo "Failed:    ${FAILED[*]}"
    exit 1
fi
