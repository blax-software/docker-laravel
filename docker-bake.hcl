# ===========================================================================
# docker-laravel — Multi-version build matrix
#
# Usage:
#   docker buildx bake                    # build all versions
#   docker buildx bake php-84             # build PHP 8.4 only
#   docker buildx bake --set "*.platform=linux/amd64,linux/arm64"
#
# Override registry:
#   REGISTRY=ghcr.io/myorg IMAGE_NAME=docker-laravel docker buildx bake
# ===========================================================================

variable "REGISTRY" {
  default = ""
}

variable "IMAGE_NAME" {
  default = "docker-laravel"
}

variable "NODE_MAJOR" {
  default = "22"
}

function "tag" {
  params = [php_version]
  result = REGISTRY != "" ? "${REGISTRY}/${IMAGE_NAME}:php${php_version}" : "${IMAGE_NAME}:php${php_version}"
}

function "latest_tag" {
  params = []
  result = REGISTRY != "" ? "${REGISTRY}/${IMAGE_NAME}:latest" : "${IMAGE_NAME}:latest"
}

# ---------------------------------------------------------------------------
# Individual targets
# ---------------------------------------------------------------------------

target "php-74" {
  context    = "."
  dockerfile = "Dockerfile"
  args = {
    PHP_VERSION = "7.4"
    NODE_MAJOR  = "${NODE_MAJOR}"
  }
  tags = [tag("7.4")]
}

target "php-80" {
  context    = "."
  dockerfile = "Dockerfile"
  args = {
    PHP_VERSION = "8.0"
    NODE_MAJOR  = "${NODE_MAJOR}"
  }
  tags = [tag("8.0")]
}

target "php-81" {
  context    = "."
  dockerfile = "Dockerfile"
  args = {
    PHP_VERSION = "8.1"
    NODE_MAJOR  = "${NODE_MAJOR}"
  }
  tags = [tag("8.1")]
}

target "php-82" {
  context    = "."
  dockerfile = "Dockerfile"
  args = {
    PHP_VERSION = "8.2"
    NODE_MAJOR  = "${NODE_MAJOR}"
  }
  tags = [tag("8.2")]
}

target "php-83" {
  context    = "."
  dockerfile = "Dockerfile"
  args = {
    PHP_VERSION = "8.3"
    NODE_MAJOR  = "${NODE_MAJOR}"
  }
  tags = [tag("8.3")]
}

target "php-84" {
  context    = "."
  dockerfile = "Dockerfile"
  args = {
    PHP_VERSION = "8.4"
    NODE_MAJOR  = "${NODE_MAJOR}"
  }
  tags = [tag("8.4"), latest_tag()]
}

target "php-85" {
  context    = "."
  dockerfile = "Dockerfile"
  args = {
    PHP_VERSION = "8.5"
    NODE_MAJOR  = "${NODE_MAJOR}"
  }
  tags = [tag("8.5")]
}

# ---------------------------------------------------------------------------
# Groups
# ---------------------------------------------------------------------------

group "default" {
  targets = ["php-74", "php-80", "php-81", "php-82", "php-83", "php-84", "php-85"]
}

group "active" {
  targets = ["php-82", "php-83", "php-84", "php-85"]
}

group "legacy" {
  targets = ["php-74", "php-80", "php-81"]
}
