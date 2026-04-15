# docker-laravel

Multi-version PHP + Nginx Docker image optimized for Laravel (9 – 13).

The image provides **PHP-FPM, Nginx, Composer, Node.js, Bun**, and common PHP extensions out of the box.  
It does **not** contain any Laravel code — mount your project at `/var/www/html`.

## Supported PHP Versions

| Tag | PHP | Laravel |
|-----|-----|---------|
| `php7.4` | 7.4 | Legacy (< 9) |
| `php8.0` | 8.0 | 9 |
| `php8.1` | 8.1 | 9, 10 |
| `php8.2` | 8.2 | 9, 10, 11, 12 |
| `php8.3` | 8.3 | 10, 11, 12, 13 |
| `php8.4` | 8.4 | 11, 12, 13 |
| `php8.5` | 8.5 | 12, 13 |
| `latest` | 8.4 | (alias) |

## Quick Start

```bash
# Build a single version
docker build --build-arg PHP_VERSION=8.4 -t docker-laravel:php8.4 .

# Build all versions
./scripts/build.sh

# Build only specific PHP versions
./scripts/build.sh 8.4 8.5

# Build all versions with buildx bake
docker buildx bake

# Build only actively-supported PHP versions
docker buildx bake active
```

## plug-n-pray 🙏

Generate a full Docker Compose boilerplate for any Laravel project:

```bash
# From your Laravel project root — one-liner:
curl -fsSL https://raw.githubusercontent.com/blax-software/docker-laravel/main/scripts/plug-n-pray.sh | bash

# With options:
./plug-n-pray.sh --php=8.4 --name=my-app --host=my-app.localhost --horizon

# Or via artisan (requires blax-software/laravel-workkit):
php artisan workkit:plug-n-pray
php artisan workkit:plug-n-pray --php=8.5 --horizon --no-mysql
```

See [docs/examples.md](docs/examples.md) for full usage examples.

## Usage in docker-compose.yml

```yaml
services:
  app:
    image: docker-laravel:php8.4
    volumes:
      - ./:/var/www/html
    ports:
      - "80:80"
    environment:
      ENABLE_QUEUE: "true"
      ENABLE_SCHEDULER: "true"
      ENABLE_HORIZON: "false"
      ENABLE_LARAVEL_PERMS: "1"
```

## Build Args

| Arg | Default | Description |
|-----|---------|-------------|
| `PHP_VERSION` | `8.4` | PHP version (7.4, 8.0 – 8.5) |
| `NODE_MAJOR` | `22` | Node.js major version |

## Runtime Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ENABLE_QUEUE` | `false` | Start `artisan queue:work` via supervisor |
| `ENABLE_SCHEDULER` | `false` | Start `artisan schedule:work` via supervisor |
| `ENABLE_HORIZON` | `false` | Start `artisan horizon` via supervisor |
| `ENABLE_LARAVEL_PERMS` | `0` | Fix `storage/` and `bootstrap/cache/` permissions on boot |

## What's Included

- **PHP-FPM** with extensions: pdo_mysql, pdo_pgsql, mysqli, mbstring, exif, pcntl, bcmath, gd (freetype + jpeg + webp), sockets, zip, xml, soap, intl, opcache
- **PECL**: redis, ev, igbinary, imagick (graceful fallback if unavailable for a PHP version)
- **OPcache** with JIT auto-enabled on PHP 8.0+
- **Nginx** with headers-more module, optimized for Laravel
- **Composer** (latest)
- **Node.js** + npm
- **Image optimizers**: optipng, pngquant, gifsicle, webp, avif, svgo
- **ffmpeg**, **ghostscript**, **MySQL client**

## Architecture

```
start-container (entrypoint)
  └─ supervisord
       ├─ php-fpm          (always)
       ├─ nginx            (always)
       ├─ queue.conf       (if ENABLE_QUEUE=true)
       ├─ scheduler.conf   (if ENABLE_SCHEDULER=true)
       └─ horizon.conf     (if ENABLE_HORIZON=true)
```

Optional supervisor configs are generated at runtime in `/etc/supervisor/laravel.d/`.

## Customizing Supervisor Programs

Every supervisor program lives in its own `.conf` file across three include directories:

| Directory | Purpose | How to customize |
|-----------|---------|------------------|
| `/etc/supervisor/conf.d/` | Core services (php-fpm, nginx) | Mount a replacement file to override |
| `/etc/supervisor/laravel.d/` | Queue, scheduler, horizon (auto-generated from `ENABLE_*` env vars) | Use env vars, or disable them and mount your own |
| `/etc/supervisor/custom.d/` | Empty — for your own programs | Mount a directory or individual files |

**Examples:**

```yaml
services:
  app:
    image: blaxsoftware/laravel:php8.4
    volumes:
      - ./:/var/www/html
      # Override php-fpm config (e.g. change pool settings)
      - ./docker/php-fpm.conf:/etc/supervisor/conf.d/php-fpm.conf
      # Add custom programs (e.g. reverb, octane, custom workers)
      - ./docker/supervisor/:/etc/supervisor/custom.d/
    environment:
      ENABLE_QUEUE: "true"
```

To **disable a core service** (e.g. nginx), mount an override with `autostart=false`:

```ini
; my-nginx-override.conf
[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autostart=false
```
