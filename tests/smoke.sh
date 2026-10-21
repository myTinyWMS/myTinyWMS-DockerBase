#!/bin/sh
# Run inside an ephemeral container: docker run --rm -i IMAGE sh < tests/smoke.sh
set -eu
. /etc/os-release
[ "$ID" = debian ]
[ "$VERSION_ID" = 13 ]
for package in php7.4-cli php7.4-fpm php7.4-common; do
    version=$(dpkg-query -W -f='${Version}' "$package")
    dpkg --compare-versions "$version" ge '1:7.4.33-31'
    echo "$package $version"
done
zcat /usr/share/doc/php7.4-common/changelog.Debian.gz > /tmp/php-changelog.txt
grep -q CVE-2026-109618 /tmp/php-changelog.txt
grep -q CVE-2026-109619 /tmp/php-changelog.txt
rm /tmp/php-changelog.txt
# Verify compatibility with downstream ini files at the former image path.
echo 'precision=13' > /usr/local/etc/php/conf.d/99-smoke.ini
php -r 'exit(ini_get("precision") === "13" ? 0 : 1);'
php -r '
if (PHP_VERSION_ID !== 70433) { exit(1); }
foreach (["zip", "intl", "bcmath", "imap", "iconv", "PDO", "pdo_mysql", "ldap", "gd", "pcntl", "mbstring", "Zend OPcache", "redis", "curl", "openssl", "sqlite3", "pdo_sqlite", "sodium", "session"] as $extension) {
    if (!extension_loaded($extension)) { fwrite(STDERR, "Missing: $extension\n"); exit(1); }
}
if (!gd_info()["JPEG Support"] || !gd_info()["FreeType Support"]) { exit(1); }
echo "PHP version and extensions OK\n";
'
php-fpm -t
node --version
npm --version
composer --version
wkhtmltopdf --version
work=$(mktemp -d)
cleanup() {
    result=$?
    if [ "$result" -ne 0 ]; then
        for log in "$work/fpm.log" "$work/nginx.log" "$work/response" "$work/oom.log"; do
            [ ! -f "$log" ] || cat "$log" >&2
        done
    fi
    [ -z "${nginx_pid:-}" ] || kill "$nginx_pid" 2>/dev/null || true
    [ -z "${fpm_pid:-}" ] || kill "$fpm_pid" 2>/dev/null || true
    rm -f /usr/local/etc/php/conf.d/99-smoke.ini
    rm -rf "$work"
}
trap cleanup EXIT
# The official backport terminates immediately on OOM (exit 1), without
# executing PHP shutdown handlers against potentially inconsistent state.
status=0
php -d memory_limit=16M -r 'register_shutdown_function(function () { echo "UNSAFE_SHUTDOWN"; }); str_repeat("x", 32 * 1024 * 1024);' > "$work/oom.log" 2>&1 || status=$?
[ "$status" -eq 1 ]
grep -q 'Allowed memory size' "$work/oom.log"
if grep -q UNSAFE_SHUTDOWN "$work/oom.log"; then
    echo 'Backport OOM behavior missing' >&2
    exit 1
fi
printf '<html><body>PDF smoke test</body></html>' > "$work/input.html"
wkhtmltopdf --quiet "$work/input.html" "$work/output.pdf"
[ -s "$work/output.pdf" ]
echo 'Backport OOM regression and PDF smoke tests OK'

# Exercise Sury FPM over FastCGI, including worker replacement.
# Sury provides PCNTL in CLI only; it is asserted in the CLI check above.
chmod 755 "$work"
cat > "$work/index.php" <<'PHP'
<?php
foreach (["zip", "intl", "bcmath", "imap", "iconv", "PDO", "pdo_mysql", "ldap", "gd", "mbstring", "Zend OPcache", "redis", "curl", "openssl", "sqlite3", "pdo_sqlite", "sodium", "session"] as $extension) {
    if (!extension_loaded($extension)) { http_response_code(500); exit("Missing FPM extension: " . $extension); }
}
if (ini_get('precision') !== '13') { http_response_code(500); exit('FPM ini path mismatch'); }
if (isset($_GET['oom'])) {
    ini_set('memory_limit', '16M');
    register_shutdown_function(function () { error_log('UNSAFE_SHUTDOWN'); });
    str_repeat('x', 32 * 1024 * 1024);
}
echo PHP_VERSION . ':' . PHP_SAPI;
PHP
cat > "$work/nginx.conf" <<NGINX
pid $work/nginx.pid;
error_log $work/nginx.log;
events {}
http {
    access_log off;
    server {
        listen 127.0.0.1:8080;
        location / {
            fastcgi_pass 127.0.0.1:9000;
            include /etc/nginx/fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $work/index.php;
        }
    }
}
NGINX
php-fpm -F > "$work/fpm.log" 2>&1 &
fpm_pid=$!
nginx -c "$work/nginx.conf" -g 'daemon off;' &
nginx_pid=$!
ready=0
for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if curl --fail-with-body -sS http://127.0.0.1:8080/ > "$work/response" 2>/dev/null; then
        ready=1
        break
    fi
    sleep 1
done
[ "$ready" -eq 1 ]
grep -qx '7.4.33:fpm-fcgi' "$work/response"
code=$(curl -sS -o /dev/null -w '%{http_code}' 'http://127.0.0.1:8080/?oom=1')
[ "$code" = 502 ]
curl -fsS http://127.0.0.1:8080/ | grep -qx '7.4.33:fpm-fcgi'
if grep -q UNSAFE_SHUTDOWN "$work/fpm.log"; then
    echo 'Unsafe shutdown handler ran under FPM' >&2
    exit 1
fi
echo 'FPM HTTP request, OOM exit and subsequent request OK'
