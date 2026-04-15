# ===========================================================================
# docker-laravel — Multi-version PHP + Nginx image for Laravel
#
# Build args:
#   PHP_VERSION   — 7.4 | 8.0 | 8.1 | 8.2 | 8.3 | 8.4 | 8.5  (default: 8.4)
#   NODE_MAJOR    — Node.js major version                        (default: 22)
# ===========================================================================
ARG PHP_VERSION=8.4
FROM php:${PHP_VERSION}-fpm

ARG PHP_VERSION

LABEL maintainer="docker-laravel"
LABEL description="Laravel-optimized PHP-FPM + Nginx image"
LABEL php.version="${PHP_VERSION}"

WORKDIR /var/www/html

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ---------------------------------------------------------------------------
# System dependencies (single layer)
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg gosu curl wget ca-certificates zip unzip git \
    supervisor sqlite3 libcap2-bin python3 pkg-config \
    # GD
    libfreetype6-dev libjpeg62-turbo-dev libpng-dev libwebp-dev \
    # PHP extension libs
    libonig-dev libxml2-dev libzip-dev libicu-dev libcurl4-openssl-dev \
    # PostgreSQL
    libpq-dev \
    # ImageMagick
    libmagickwand-dev \
    # Nginx + headers-more module
    nginx libnginx-mod-http-headers-more-filter \
    # Database clients
    default-mysql-client \
    # Ghostscript (PDF rendering)
    ghostscript \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# PHP extensions
# ---------------------------------------------------------------------------
# GD configure flags changed between PHP 7.x and 8.0
RUN PHP_MAJOR=$(php -r "echo PHP_MAJOR_VERSION;") && \
    if [ "$PHP_MAJOR" -ge 8 ]; then \
        docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp; \
    else \
        docker-php-ext-configure gd --with-freetype-dir=/usr --with-jpeg-dir=/usr --with-webp-dir=/usr; \
    fi && \
    docker-php-ext-install -j$(nproc) \
        pdo_mysql \
        pdo_pgsql \
        mysqli \
        mbstring \
        exif \
        pcntl \
        bcmath \
        gd \
        sockets \
        zip \
        xml \
        soap \
        intl \
        opcache

# PECL extensions (fail gracefully for bleeding-edge PHP)
RUN pecl install redis   && docker-php-ext-enable redis   || echo "NOTICE: redis unavailable for PHP ${PHP_VERSION}"
RUN pecl install ev      && docker-php-ext-enable ev      || echo "NOTICE: ev unavailable for PHP ${PHP_VERSION}"
RUN pecl install igbinary && docker-php-ext-enable igbinary || echo "NOTICE: igbinary unavailable for PHP ${PHP_VERSION}"
RUN pecl install imagick && docker-php-ext-enable imagick || echo "NOTICE: imagick unavailable for PHP ${PHP_VERSION}"

# ---------------------------------------------------------------------------
# OPcache configuration (JIT enabled automatically for PHP 8.0+)
# ---------------------------------------------------------------------------
COPY config/opcache.ini /usr/local/etc/php/conf.d/opcache.ini
RUN PHP_MAJOR=$(php -r "echo PHP_MAJOR_VERSION;") && \
    if [ "$PHP_MAJOR" -ge 8 ]; then \
        { echo ""; echo "; JIT (PHP 8.0+)"; echo "opcache.jit=1255"; echo "opcache.jit_buffer_size=128M"; } \
            >> /usr/local/etc/php/conf.d/opcache.ini; \
        echo "JIT enabled for PHP $(php -r 'echo PHP_VERSION;')"; \
    else \
        echo "JIT skipped (PHP $(php -r 'echo PHP_VERSION;') < 8.0)"; \
    fi

# ImageMagick PDF policy (for spatie/pdf-to-image etc.)
RUN IMGK_CONF=$(find /etc/ImageMagick* -name policy.xml 2>/dev/null | head -1) && \
    if [ -n "$IMGK_CONF" ]; then \
        sed -i 's/<policy domain="coder" rights="none" pattern="PDF" \/>/<policy domain="coder" rights="read|write" pattern="PDF" \/>/g' "$IMGK_CONF" && \
        sed -i '/<\/policymap>/i\  <policy domain="coder" rights="read|write" pattern="LABEL" />' "$IMGK_CONF"; \
    fi

# Custom PHP configuration
COPY config/php.ini /usr/local/etc/php/conf.d/99-custom.ini

# ---------------------------------------------------------------------------
# Composer
# ---------------------------------------------------------------------------
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer

# ---------------------------------------------------------------------------
# Node.js + npm
# ---------------------------------------------------------------------------
ARG NODE_MAJOR=22
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
        > /etc/apt/sources.list.d/nodesource.list && \
    apt-get update && apt-get install -y --no-install-recommends nodejs && \
    npm install -g npm@latest && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Image optimization tools (spatie/image-optimizer) + ffmpeg
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    optipng pngquant gifsicle webp libavif-bin ffmpeg \
    nano procps net-tools \
    && npm install -g svgo \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Users & directories
# ---------------------------------------------------------------------------
RUN usermod -u 1000 www-data && groupmod -g 1000 www-data

# PsySH config for artisan tinker
RUN mkdir -p /var/www/.config/psysh && chown -R www-data:www-data /var/www/.config

# ---------------------------------------------------------------------------
# Nginx configuration
# ---------------------------------------------------------------------------
COPY config/nginx.conf /etc/nginx/nginx.conf
COPY config/default.conf /etc/nginx/sites-available/default
RUN rm -f /etc/nginx/sites-enabled/default && \
    ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default && \
    rm -f /etc/nginx/conf.d/default.conf

# ---------------------------------------------------------------------------
# Supervisor configuration
#   conf.d/    — core programs (php-fpm, nginx), override via volume mount
#   laravel.d/ — generated at boot from ENABLE_* env vars
#   custom.d/  — mount your own .conf files here
# ---------------------------------------------------------------------------
COPY config/supervisord.conf /etc/supervisor/supervisord.conf
COPY config/supervisor/php-fpm.conf /etc/supervisor/conf.d/php-fpm.conf
COPY config/supervisor/nginx.conf   /etc/supervisor/conf.d/nginx.conf
RUN mkdir -p /etc/supervisor/conf.d /etc/supervisor/laravel.d /etc/supervisor/custom.d \
             /var/log/supervisor /var/log/nginx /var/log/php

# ---------------------------------------------------------------------------
# Startup script
# ---------------------------------------------------------------------------
COPY scripts/start-container /usr/local/bin/start-container
RUN chmod +x /usr/local/bin/start-container

# Composer cache
RUN mkdir -p /.composer && chmod 0777 /.composer

# ---------------------------------------------------------------------------
# Environment variables for optional Laravel services
# Set to "true" to enable at container start
# ---------------------------------------------------------------------------
ENV ENABLE_QUEUE=false
ENV ENABLE_SCHEDULER=false
ENV ENABLE_HORIZON=false
ENV ENABLE_LARAVEL_PERMS=0

EXPOSE 80

ENTRYPOINT ["start-container"]

