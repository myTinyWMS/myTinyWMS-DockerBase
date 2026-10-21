FROM node:14.21.3-bullseye-slim AS node
FROM debian:trixie-slim

LABEL org.mytinywms.php-provider="packages.sury.org" \
      org.mytinywms.php2shell-minimum-package-version="1:7.4.33-31"
ENV PHP_INI_DIR=/usr/local/etc/php \
    PHPRC=/usr/local/etc/php \
    PHP_INI_SCAN_DIR=/usr/local/etc/php/conf.d

# Sury's documented keyring setup; APT verifies signed repository metadata.
RUN set -eux; \
    export DEBIAN_FRONTEND=noninteractive; \
    echo 'path-include /usr/share/doc/php7.4-common/changelog.Debian.gz' > /etc/dpkg/dpkg.cfg.d/zz-php-changelog; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl; \
    curl -fsSLo /tmp/sury-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb; \
    dpkg -i /tmp/sury-keyring.deb; \
    rm /tmp/sury-keyring.deb; \
    echo 'deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ trixie main' > /etc/apt/sources.list.d/php.list; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        php7.4-cli php7.4-fpm php7.4-common php7.4-opcache \
        php7.4-bcmath php7.4-curl php7.4-gd php7.4-imap php7.4-intl \
        php7.4-ldap php7.4-mbstring php7.4-mysql php7.4-redis \
        php7.4-sqlite3 php7.4-xml php7.4-zip \
        nginx wget nano unzip supervisor mariadb-client locales git gnupg; \
    for package in php7.4-cli php7.4-fpm php7.4-common; do \
        version="$(dpkg-query -W -f='${Version}' "$package")"; \
        dpkg --compare-versions "$version" ge '1:7.4.33-31'; \
    done; \
    mkdir -p /usr/local/share/mytinywms; \
    dpkg-query -W 'php7.4*' > /usr/local/share/mytinywms/php-packages.txt; \
    sed -i '/^#.* de_DE.* /s/^#//' /etc/locale.gen; \
    locale-gen; \
    rm -rf /var/lib/apt/lists/*

# Preserve the previous image's common executable/configuration paths.
# Both SAPIs read the same ini and conf.d, as in the official PHP image.
RUN set -eux; \
    mkdir -p /usr/local/etc /usr/local/sbin /var/www/html /run/php; \
    ln -s /etc/php/7.4/fpm /usr/local/etc/php; \
    ln -s /etc/php/7.4/fpm/php-fpm.conf /usr/local/etc/php-fpm.conf; \
    ln -s /etc/php/7.4/fpm/pool.d /usr/local/etc/php-fpm.d; \
    ln -s /usr/bin/php7.4 /usr/local/bin/php; \
    ln -s /usr/sbin/php-fpm7.4 /usr/local/sbin/php-fpm; \
    chown www-data:www-data /var/www/html
COPY docker/zz-docker.conf /etc/php/7.4/fpm/pool.d/zz-docker.conf
COPY --chmod=755 docker/entrypoint.sh /usr/local/bin/docker-php-entrypoint

# The upstream Bookworm build uses OpenSSL 3, available on Trixie too.
# Verify actual runtime compatibility in tests/smoke.sh.
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in amd64|arm64) ;; *) exit 1 ;; esac; \
    curl -fsSL "https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-3/wkhtmltox_0.12.6.1-3.bookworm_${arch}.deb" -o /tmp/wkhtmltox.deb; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/wkhtmltox.deb; \
    rm /tmp/wkhtmltox.deb; \
    rm -rf /var/lib/apt/lists/*

# Retain the existing application's Node major version for compatibility.
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx
COPY --from=composer:2.10.3 /usr/bin/composer /usr/bin/composer

WORKDIR /var/www/html
EXPOSE 9000
STOPSIGNAL SIGQUIT
ENTRYPOINT ["docker-php-entrypoint"]
CMD ["php-fpm"]
