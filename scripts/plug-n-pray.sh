#!/usr/bin/env bash
# ===========================================================================
# plug-n-pray.sh — Generate a boilerplate Docker setup for any Laravel project
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/blax-software/docker-laravel/main/scripts/plug-n-pray.sh | bash
#   # or locally:
#   ./plug-n-pray.sh
#   ./plug-n-pray.sh --php=8.4 --name=my-app --host=my-app.localhost
#
# Assumes Traefik is already running on the "web" network.
#
# What it creates:
#   docker-compose.yml        — App + MySQL + Redis (with Traefik labels)
#   .env.docker               — Docker-specific env vars
#   docker/supervisor/         — Empty custom supervisor dir
# ===========================================================================
set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
PHP_VERSION="8.4"
PROJECT_NAME=""
TRAEFIK_HOST=""
DB_NAME=""
DB_PASSWORD="secret"
IMAGE="blaxsoftware/laravel"
ENABLE_QUEUE="true"
ENABLE_SCHEDULER="true"
ENABLE_HORIZON="false"
ENABLE_REDIS="true"
ENABLE_MYSQL="true"
ENABLE_WEBSOCKET="false"
WEBSOCKET_PORT="6001"
FORCE="false"

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
for arg in "$@"; do
    case $arg in
        --php=*)       PHP_VERSION="${arg#*=}" ;;
        --name=*)      PROJECT_NAME="${arg#*=}" ;;
        --host=*)      TRAEFIK_HOST="${arg#*=}" ;;
        --db=*)        DB_NAME="${arg#*=}" ;;
        --db-pass=*)   DB_PASSWORD="${arg#*=}" ;;
        --image=*)     IMAGE="${arg#*=}" ;;
        --no-queue)    ENABLE_QUEUE="false" ;;
        --no-scheduler) ENABLE_SCHEDULER="false" ;;
        --horizon)     ENABLE_HORIZON="true" ;;
        --no-redis)    ENABLE_REDIS="false" ;;
        --no-mysql)    ENABLE_MYSQL="false" ;;
        --websocket)   ENABLE_WEBSOCKET="true" ;;
        --websocket-port=*) WEBSOCKET_PORT="${arg#*=}" ;;
        --force)       FORCE="true" ;;
        --help|-h)
            echo "Usage: plug-n-pray.sh [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --php=VERSION        PHP version (default: 8.4)"
            echo "  --name=NAME          Project/compose name (default: directory name)"
            echo "  --host=HOST          Traefik hostname (default: NAME.localhost)"
            echo "  --db=NAME            Database name (default: PROJECT_NAME)"
            echo "  --db-pass=PASS       Database password (default: secret)"
            echo "  --image=IMAGE        Docker image (default: blaxsoftware/laravel)"
            echo "  --no-queue           Disable queue worker"
            echo "  --no-scheduler       Disable scheduler"
            echo "  --horizon            Enable Horizon (disables basic queue)"
            echo "  --no-redis           Skip Redis service"
            echo "  --no-mysql           Skip MySQL service"
            echo "  --websocket          Enable WebSocket server (blax/laravel-websockets)"
            echo "  --websocket-port=N   WebSocket port (default: 6001)"
            echo "  --force              Overwrite existing files"
            echo "  --help               Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg (try --help)"
            exit 1
            ;;
    esac
done

# Derive defaults from current directory
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="$(basename "$(pwd)")"
    # Sanitize: lowercase, replace non-alnum with dash
    PROJECT_NAME="$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')"
fi

if [ -z "$TRAEFIK_HOST" ]; then
    TRAEFIK_HOST="${PROJECT_NAME}.localhost"
fi

if [ -z "$DB_NAME" ]; then
    DB_NAME="$(echo "$PROJECT_NAME" | sed 's/-/_/g')"
fi

# If horizon is on, disable basic queue
if [ "$ENABLE_HORIZON" = "true" ]; then
    ENABLE_QUEUE="false"
fi

# ---------------------------------------------------------------------------
# Safety check
# ---------------------------------------------------------------------------
if [ "$FORCE" != "true" ] && [ -f "docker-compose.yml" ]; then
    echo "docker-compose.yml already exists. Use --force to overwrite."
    exit 1
fi

echo "=========================================="
echo "  plug-n-pray 🙏"
echo "=========================================="
echo "  Project:    $PROJECT_NAME"
echo "  PHP:        $PHP_VERSION"
echo "  Image:      ${IMAGE}:php${PHP_VERSION}"
echo "  Traefik:    $TRAEFIK_HOST"
echo "  Database:   ${ENABLE_MYSQL:+MySQL ($DB_NAME)}${ENABLE_MYSQL:+}$([ "$ENABLE_MYSQL" = "false" ] && echo "disabled")"
echo "  Redis:      $ENABLE_REDIS"
echo "  Queue:      $ENABLE_QUEUE"
echo "  Scheduler:  $ENABLE_SCHEDULER"
echo "  Horizon:    $ENABLE_HORIZON"
echo "  WebSocket:  ${ENABLE_WEBSOCKET}$([ "$ENABLE_WEBSOCKET" = "true" ] && echo " (port ${WEBSOCKET_PORT})")"
echo "=========================================="

# ---------------------------------------------------------------------------
# Create directory for custom supervisor configs
# ---------------------------------------------------------------------------
mkdir -p docker/supervisor

# ---------------------------------------------------------------------------
# Generate docker-compose.yml
# ---------------------------------------------------------------------------
cat > docker-compose.yml <<YAML
# ===========================================================================
# Generated by plug-n-pray.sh — $(date +%Y-%m-%d)
# Image: ${IMAGE}:php${PHP_VERSION}
# ===========================================================================

networks:
  web:
    external: true
  internal:
    driver: bridge

YAML

# --- Volumes ---
VOLUMES_SECTION=""
if [ "$ENABLE_MYSQL" = "true" ]; then
    VOLUMES_SECTION="volumes:
  mysql-data:
"
fi
if [ "$ENABLE_REDIS" = "true" ]; then
    if [ -n "$VOLUMES_SECTION" ]; then
        VOLUMES_SECTION="${VOLUMES_SECTION}  redis-data:
"
    else
        VOLUMES_SECTION="volumes:
  redis-data:
"
    fi
fi

if [ -n "$VOLUMES_SECTION" ]; then
    echo "$VOLUMES_SECTION" >> docker-compose.yml
fi

# --- Services ---
cat >> docker-compose.yml <<YAML
services:
  # -------------------------------------------------------------------------
  # App (PHP-FPM + Nginx)
  # -------------------------------------------------------------------------
  app:
    image: ${IMAGE}:php${PHP_VERSION}
    container_name: ${PROJECT_NAME}-app
    restart: unless-stopped
    working_dir: /var/www/html
    volumes:
      - ./:/var/www/html
      - ./docker/supervisor:/etc/supervisor/custom.d
    environment:
      ENABLE_QUEUE: "${ENABLE_QUEUE}"
      ENABLE_SCHEDULER: "${ENABLE_SCHEDULER}"
      ENABLE_HORIZON: "${ENABLE_HORIZON}"
      ENABLE_LARAVEL_PERMS: "1"
$([ "$ENABLE_WEBSOCKET" = "true" ] && echo "      PUSHER_PORT: \"${WEBSOCKET_PORT}\"")
    networks:
      - web
      - internal
    depends_on:
YAML

if [ "$ENABLE_MYSQL" = "true" ]; then
cat >> docker-compose.yml <<YAML
      mysql:
        condition: service_healthy
YAML
fi

if [ "$ENABLE_REDIS" = "true" ]; then
cat >> docker-compose.yml <<YAML
      redis:
        condition: service_healthy
YAML
fi

cat >> docker-compose.yml <<YAML
    labels:
      - traefik.enable=true
      - traefik.docker.network=web
      # HTTP
      - traefik.http.routers.${PROJECT_NAME}.rule=Host(\`${TRAEFIK_HOST}\`)
      - traefik.http.routers.${PROJECT_NAME}.entrypoints=web
      - traefik.http.routers.${PROJECT_NAME}.service=${PROJECT_NAME}-http
      - traefik.http.services.${PROJECT_NAME}-http.loadbalancer.server.port=80
      # HTTPS
      - traefik.http.routers.${PROJECT_NAME}-tls.rule=Host(\`${TRAEFIK_HOST}\`)
      - traefik.http.routers.${PROJECT_NAME}-tls.entrypoints=websecure
      - traefik.http.routers.${PROJECT_NAME}-tls.tls=true
      - traefik.http.routers.${PROJECT_NAME}-tls.service=${PROJECT_NAME}-https
      - traefik.http.services.${PROJECT_NAME}-https.loadbalancer.server.port=80
$(if [ "$ENABLE_WEBSOCKET" = "true" ]; then
cat <<WSLABELS
      # WebSocket
      - traefik.http.routers.${PROJECT_NAME}-ws.rule=Host(\`ws-${TRAEFIK_HOST}\`)
      - traefik.http.routers.${PROJECT_NAME}-ws.entrypoints=web
      - traefik.http.routers.${PROJECT_NAME}-ws.service=${PROJECT_NAME}-ws
      - traefik.http.services.${PROJECT_NAME}-ws.loadbalancer.server.port=${WEBSOCKET_PORT}
      - traefik.http.routers.${PROJECT_NAME}-wss.rule=Host(\`ws-${TRAEFIK_HOST}\`)
      - traefik.http.routers.${PROJECT_NAME}-wss.entrypoints=websecure
      - traefik.http.routers.${PROJECT_NAME}-wss.tls=true
      - traefik.http.routers.${PROJECT_NAME}-wss.service=${PROJECT_NAME}-wss
      - traefik.http.services.${PROJECT_NAME}-wss.loadbalancer.server.port=${WEBSOCKET_PORT}
WSLABELS
fi)
YAML

# --- MySQL ---
if [ "$ENABLE_MYSQL" = "true" ]; then
cat >> docker-compose.yml <<YAML

  # -------------------------------------------------------------------------
  # MySQL
  # -------------------------------------------------------------------------
  mysql:
    image: mysql:8.0
    container_name: ${PROJECT_NAME}-mysql
    restart: unless-stopped
    environment:
      MYSQL_ROOT_PASSWORD: "${DB_PASSWORD}"
      MYSQL_DATABASE: "${DB_NAME}"
    volumes:
      - mysql-data:/var/lib/mysql
    networks:
      - internal
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-p${DB_PASSWORD}"]
      interval: 10s
      timeout: 5s
      retries: 5
YAML
fi

# --- Redis ---
if [ "$ENABLE_REDIS" = "true" ]; then
cat >> docker-compose.yml <<YAML

  # -------------------------------------------------------------------------
  # Redis
  # -------------------------------------------------------------------------
  redis:
    image: redis:7-alpine
    container_name: ${PROJECT_NAME}-redis
    restart: unless-stopped
    volumes:
      - redis-data:/data
    networks:
      - internal
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
YAML
fi

# --- WebSocket supervisor config ---
if [ "$ENABLE_WEBSOCKET" = "true" ]; then
cat > docker/supervisor/websocket.conf <<CONF
[program:websocket]
command=/usr/local/bin/php -d variables_order=EGPCS /var/www/html/artisan websockets:serve --host=0.0.0.0 --port=${WEBSOCKET_PORT}
autostart=true
autorestart=true
user=www-data
priority=30
startsecs=5
startretries=100
stopsignal=TERM
stopwaitsecs=15
stdout_logfile=/proc/1/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/proc/1/fd/2
stderr_logfile_maxbytes=0
CONF
    echo "  Created docker/supervisor/websocket.conf"
fi

# ---------------------------------------------------------------------------
# Generate .env.docker
# ---------------------------------------------------------------------------
cat > .env.docker <<ENV
# ===========================================================================
# Docker environment — generated by plug-n-pray.sh
# Merge these into your .env or source this file
# ===========================================================================

# App
APP_URL=http://${TRAEFIK_HOST}
ENV

if [ "$ENABLE_MYSQL" = "true" ]; then
cat >> .env.docker <<ENV

# Database
DB_CONNECTION=mysql
DB_HOST=mysql
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=root
DB_PASSWORD=${DB_PASSWORD}
ENV
fi

if [ "$ENABLE_REDIS" = "true" ]; then
cat >> .env.docker <<ENV

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
CACHE_STORE=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis
ENV
fi

if [ "$ENABLE_WEBSOCKET" = "true" ]; then
cat >> .env.docker <<ENV

# WebSocket (blax/laravel-websockets)
BROADCAST_CONNECTION=pusher
PUSHER_APP_ID=app-id
PUSHER_APP_KEY=app-key
PUSHER_APP_SECRET=app-secret
PUSHER_HOST=127.0.0.1
PUSHER_PORT=${WEBSOCKET_PORT}
PUSHER_SCHEME=http
LARAVEL_WEBSOCKETS_PORT=${WEBSOCKET_PORT}
ENV
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "=========================================="
echo "  Files created:"
echo "=========================================="
echo "  docker-compose.yml    — Full stack (app + db + redis, Traefik labels)"
echo "  .env.docker           — Environment variables to merge into .env"
echo "  docker/supervisor/    — Mount dir for custom supervisor programs"
echo ""
echo "  Next steps:"
echo "    1. Merge .env.docker into your .env"
echo "    2. Create the external network (once):  docker network create web"
echo "    3. Start:  docker compose up -d"
echo "    4. Visit:  http://${TRAEFIK_HOST}"
echo ""
echo "  Pray it works. 🙏"
echo "=========================================="
