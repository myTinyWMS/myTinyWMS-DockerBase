#!/bin/sh
set -eu
case "${1:-}" in
    -*) set -- php-fpm "$@" ;;
esac
exec "$@"
