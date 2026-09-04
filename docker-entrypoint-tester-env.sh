#!/bin/bash
# Tester-env entrypoint: auto-install ownCloud with SQLite on first boot,
# then run Apache. Reboots reuse the existing install on the data volume.
set -e

DATA_DIR="${OWNCLOUD_DATA_DIR:-/var/www/data}"
APP_PORT="${APP_PORT:-8088}"
ADMIN_USER="${OWNCLOUD_ADMIN_USERNAME:-admin}"
ADMIN_PASS="${OWNCLOUD_ADMIN_PASSWORD:-admin12345}"

mkdir -p "${DATA_DIR}"
chown www-data:www-data "${DATA_DIR}"

occ() {
    su -s /bin/bash www-data -c "php /var/www/html/occ $*"
}

if ! occ status 2>/dev/null | grep -q 'installed: *true'; then
    echo "==> Installing ownCloud (SQLite, admin: ${ADMIN_USER})..."
    occ maintenance:install \
        --database=sqlite \
        --database-name=owncloud \
        --admin-user="${ADMIN_USER}" \
        --admin-pass="${ADMIN_PASS}" \
        --data-dir="${DATA_DIR}"
    occ config:system:set trusted_domains 1 --value=localhost
    occ config:system:set trusted_domains 2 --value=host.docker.internal
    occ config:system:set overwrite.cli.url --value="http://localhost:${APP_PORT}"
    echo "==> Install complete."
else
    echo "==> ownCloud already installed, skipping setup."
fi

exec "$@"
