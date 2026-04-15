# Examples

## Quick Start with plug-n-pray

The fastest way to Dockerize any Laravel project:

```bash
# From your Laravel project root:
curl -fsSL https://raw.githubusercontent.com/blax-software/docker-laravel/main/scripts/plug-n-pray.sh | bash

# Or with options:
curl -fsSL https://raw.githubusercontent.com/blax-software/docker-laravel/main/scripts/plug-n-pray.sh | bash -s -- \
  --php=8.4 \
  --name=my-app \
  --host=my-app.localhost
```

Or if you have `blax-software/laravel-workkit` installed:

```bash
php artisan workkit:plug-n-pray
```

This generates:
- `docker-compose.yml` — Full stack with app, MySQL, Redis, and Traefik
- `.env.docker` — Database/Redis connection values to merge into `.env`
- `docker/supervisor/` — Directory for custom supervisor programs

Then:
```bash
docker network create web    # once per machine
docker compose up -d
```

---

## Example: Minimal API (no frontend tooling)

```yaml
services:
  app:
    image: blaxsoftware/laravel:php8.4
    volumes:
      - ./:/var/www/html
    ports:
      - "80:80"
    environment:
      ENABLE_QUEUE: "true"
      ENABLE_SCHEDULER: "true"
```

---

## Example: Full Stack with Traefik

Assumes Traefik is already running on the `web` network.

```yaml
networks:
  web:
    external: true
  internal:

volumes:
  mysql-data:
  redis-data:

services:
  app:
    image: blaxsoftware/laravel:php8.4
    volumes:
      - ./:/var/www/html
      - ./docker/supervisor:/etc/supervisor/custom.d
    environment:
      ENABLE_QUEUE: "true"
      ENABLE_SCHEDULER: "true"
      ENABLE_LARAVEL_PERMS: "1"
    networks:
      - web
      - internal
    depends_on:
      mysql:
        condition: service_healthy
      redis:
        condition: service_healthy
    labels:
      - traefik.enable=true
      - traefik.docker.network=web
      - traefik.http.routers.my-app.rule=Host(`my-app.localhost`)
      - traefik.http.routers.my-app.entrypoints=web
      - traefik.http.routers.my-app.service=my-app-http
      - traefik.http.services.my-app-http.loadbalancer.server.port=80

  mysql:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: secret
      MYSQL_DATABASE: my_app
    volumes:
      - mysql-data:/var/lib/mysql
    networks:
      - internal
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-psecret"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7-alpine
    volumes:
      - redis-data:/data
    networks:
      - internal
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
```

---

## Example: With Horizon

```yaml
services:
  app:
    image: blaxsoftware/laravel:php8.4
    volumes:
      - ./:/var/www/html
    environment:
      ENABLE_HORIZON: "true"       # replaces basic queue worker
      ENABLE_SCHEDULER: "true"
```

---

## Example: Custom Supervisor Programs

Mount your own `.conf` files into `/etc/supervisor/custom.d/`:

```yaml
services:
  app:
    image: blaxsoftware/laravel:php8.4
    volumes:
      - ./:/var/www/html
      - ./docker/supervisor/reverb.conf:/etc/supervisor/custom.d/reverb.conf
```

`docker/supervisor/reverb.conf`:
```ini
[program:reverb]
command=/usr/local/bin/php -d variables_order=EGPCS /var/www/html/artisan reverb:start --host=0.0.0.0 --port=8080
autostart=true
autorestart=true
user=www-data
priority=25
startsecs=5
stdout_logfile=/proc/1/fd/1
stdout_logfile_maxbytes=0
stderr_logfile=/proc/1/fd/2
stderr_logfile_maxbytes=0
```

---

## Example: Override PHP-FPM

```yaml
volumes:
  - ./docker/php-fpm.conf:/etc/supervisor/conf.d/php-fpm.conf
```

---

## Example: Multiple PHP Versions in One Compose

```yaml
services:
  app-legacy:
    image: blaxsoftware/laravel:php8.1
    volumes:
      - ../legacy-app:/var/www/html

  app-new:
    image: blaxsoftware/laravel:php8.4
    volumes:
      - ../new-app:/var/www/html
```

---

## plug-n-pray.sh Options

| Flag             | Default                | Description                                              |
|------------------|------------------------|----------------------------------------------------------|
| `--php=VERSION`  | `8.4`                  | PHP version                                              |
| `--name=NAME`    | directory name         | Project name (used for container names & Traefik router) |
| `--host=HOST`    | `NAME.localhost`       | Traefik hostname                                         |
| `--db=NAME`      | project name           | MySQL database name                                      |
| `--db-pass=PASS` | `secret`               | MySQL root password                                      |
| `--image=IMAGE`  | `blaxsoftware/laravel` | Docker image                                             |
| `--no-queue`     | —                      | Disable queue worker                                     |
| `--no-scheduler` | —                      | Disable scheduler                                        |
| `--horizon`      | —                      | Enable Horizon (auto-disables basic queue)               |
| `--no-redis`     | —                      | Skip Redis service                                       |
| `--no-mysql`     | —                      | Skip MySQL service                                       |
| `--force`        | —                      | Overwrite existing files                                 |
