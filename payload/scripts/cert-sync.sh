#!/bin/sh
# Copy Caddy's certificate for the mail host into Stalwart's TLS dir and restart
# Stalwart only when the material changed. Caddy renews in place, this follows it.
set -eu
[ -f /etc/mailstack/mailstack.env ] || exit 0
. /etc/mailstack/mailstack.env
: "${MAIL_HOST:?MAIL_HOST unset}"

SRC="/var/lib/caddy/.local/share/caddy/certificates/acme-v02.api.letsencrypt.org-directory/$MAIL_HOST"
DST=/etc/stalwart/tls
changed=0

for f in "$MAIL_HOST.crt" "$MAIL_HOST.key"; do
    [ -f "$SRC/$f" ] || exit 0
    if ! cmp -s "$SRC/$f" "$DST/$f"; then
        install -d -o root -g stalwart -m 750 "$DST"
        install -o root -g stalwart -m 640 "$SRC/$f" "$DST/$f"
        changed=1
    fi
done

if [ "$changed" -eq 1 ]; then
    logger -t mailstack-cert "certificate updated, restarting stalwart"
    systemctl restart stalwart
fi
