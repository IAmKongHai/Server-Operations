# nyh-prod-2026 的 PHP 运行镜像（7.4 / 8.2 共用一个 Dockerfile，用 PHP_VER 区分）
#
# 为什么不用官方 php:7.4-fpm：官方 7.4 镜像 2022 年就停更了，底层是没打补丁的 Debian 11。
# 这里用 debian:trixie + Sury 源，版本、补丁与旧机 nyh-prod（宝塔自编译 7.4.33 / 8.2.35）一致。
#
# 构建：docker compose build（见 compose.yaml）
FROM debian:trixie-slim

ARG PHP_VER
ARG PHP_EXTS
ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Asia/Shanghai

# Sury 源 + PHP 及扩展；supervisor 只有 php74-worker 用，装进同一镜像省得再维护一个
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg tzdata tzdata-legacy; \
    curl -fsSL https://packages.sury.org/php/apt.gpg -o /usr/share/keyrings/sury-php.gpg; \
    echo "deb [signed-by=/usr/share/keyrings/sury-php.gpg] https://packages.sury.org/php/ trixie main" > /etc/apt/sources.list.d/sury-php.list; \
    apt-get update; \
    pkgs="php${PHP_VER}-fpm php${PHP_VER}-cli"; \
    for e in ${PHP_EXTS}; do pkgs="$pkgs php${PHP_VER}-$e"; done; \
    apt-get install -y --no-install-recommends $pkgs supervisor; \
    rm -rf /var/lib/apt/lists/*; \
    ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime; \
    groupadd -g 1000 www; useradd -u 1000 -g 1000 -M -d /nonexistent -s /usr/sbin/nologin www; \
    mkdir -p /run/php /www/php_session; \
    # supervisor 和 cron 里写的是宝塔风格的 php74 / php82 命令名，保持兼容
    ln -sf /usr/bin/php${PHP_VER} /usr/local/bin/php$(echo ${PHP_VER} | tr -d .); \
    rm -f /etc/php/${PHP_VER}/fpm/pool.d/www.conf

# 从旧机导出的 php.ini 差异（CLI 和 FPM 共用部分 / 仅 FPM 部分）与 FPM 池
COPY php${PHP_VER}/cli-fpm.ini /etc/php/${PHP_VER}/cli/conf.d/99-nyh.ini
COPY php${PHP_VER}/cli-fpm.ini /etc/php/${PHP_VER}/fpm/conf.d/99-nyh.ini
COPY php${PHP_VER}/fpm-only.ini /etc/php/${PHP_VER}/fpm/conf.d/99-nyh-fpm.ini
COPY php${PHP_VER}/pool.conf /etc/php/${PHP_VER}/fpm/pool.d/nyh.conf

ENV PHP_VER=${PHP_VER}
CMD ["sh", "-c", "exec php-fpm${PHP_VER} -F"]
