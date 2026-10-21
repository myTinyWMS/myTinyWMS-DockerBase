# myTinyWMS-DockerBase

Debian 13 (Trixie) with PHP 7.4 CLI/FPM and extensions from Sury's signed
APT repository. PHP is installed as binary packages; no local PHP source
build or vendored security patch is required.

## Build and test

```sh
docker build --pull --no-cache --platform linux/amd64 -t mytinywms-base:7.4-sury .
docker run --rm --platform linux/amd64 -i mytinywms-base:7.4-sury sh < tests/smoke.sh
```

Use `FROM mytinywms-base:7.4-sury` in the application image, rebuild it and
recreate its containers. Test myTinyWMS and its Composer dependencies before
production deployment; application source is not present in this repository.
Rebuild with `--pull --no-cache` to pick up Debian/Sury security updates:
existing images and containers do not update themselves.

## PHP2Shell and package provenance

- Sury repository setup: https://packages.sury.org/php/README.txt
- Package pool: https://packages.sury.org/php/pool/main/p/php7.4/
- PHP advisory: https://www.php.net/archive/2026.php#2026-10-21-1

Sury's `1:7.4.33-31` changelog explicitly includes CVE-2026-109618 and
CVE-2026-109619, together with other security backports. The build rejects
older CLI, FPM or common packages. It installs the repository's current
packages rather than pinning old security revisions. Installed PHP package
versions are recorded in `/usr/local/share/mytinywms/php-packages.txt`.
`php -v` alone does not show Debian package revisions.

The smoke test checks Debian 13, the minimum PHP package versions, CVE
changelog entries, CLI/FPM extensions, shared ini overrides, FPM configuration,
Node/npm/Composer, PDF generation, and actual Nginx/FPM requests. It verifies
that memory exhaustion immediately terminates the affected CLI/FPM process
without running shutdown handlers, and that FPM handles the next request.
This regression check is not a comprehensive security audit.

## Application-image migration

- Default command remains `php-fpm`, running in the foreground on TCP port
  9000. The work directory remains `/var/www/html`; `SIGQUIT` stops FPM
  gracefully. The entrypoint also accepts FPM options such as `-t`.
- `php` and `php-fpm` aliases retain their previous `/usr/local` executable
  locations. Native binaries are `/usr/bin/php7.4` and `/usr/sbin/php-fpm7.4`.
- `/usr/local/etc/php` links to `/etc/php/7.4/fpm`. `PHPRC` and
  `PHP_INI_SCAN_DIR` make CLI and FPM share this ini and its `conf.d` directory.
  Existing `COPY ... /usr/local/etc/php/conf.d/` instructions still work.
- `/usr/local/etc/php-fpm.conf` and `/usr/local/etc/php-fpm.d` link to Sury's
  FPM configuration and `pool.d`. Container overrides live in `zz-docker.conf`.
- PHP ini defaults now come from Sury/Debian. Review application-specific
  limits and settings when migrating. Pool overrides should sort after
  `zz-docker.conf` if they must replace its settings.
- `docker-php-ext-install`, `docker-php-ext-enable` and `docker-php-source`
  are no longer available. Install additional extensions with versioned
  packages, e.g. `apt-get install php7.4-soap`, and use `phpenmod`/`phpdismod`.
  Avoid unversioned `php-*` packages that could select a newer PHP major.
- Sury provides PCNTL in CLI only, suitable for CLI queue workers. It is
  not available in FPM, unlike the previous custom extension build.
- Extensions and Redis now receive package updates from Sury, rather than
  being compiled locally or pinned to the previous PECL Redis release.

## Other tools and limitations

Node 14.21.3/npm 6.14.18 are retained for application compatibility; Node 14
is EOL. Composer remains 2.10.3. PHP 7.4 is upstream EOL; security backports
now depend on Sury, without an upstream PHP support guarantee.

wkhtmltopdf uses the upstream 0.12.6.1-3 Bookworm package with patched Qt.
The image installs its dependencies through Trixie's APT and the smoke test
verifies PDF rendering on Trixie. wkhtmltopdf itself is a legacy component.

The Dockerfile allows amd64 and arm64 wkhtmltopdf packages. Local build and
runtime validation target **linux/amd64**, matching the original image.
