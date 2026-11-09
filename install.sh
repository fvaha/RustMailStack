#!/usr/bin/env bash
# Portable installer for distros without dpkg (Arch, Fedora, openSUSE, Alpine+openrc
# is NOT supported — this script assumes systemd). Run from the unpacked tarball:
#
#   tar -xzf rustmailstack-1.0.0-amd64.tar.gz -C /tmp/rms && sudo /tmp/rms/install.sh
set -euo pipefail
cd "$(dirname "$0")"

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }
command -v systemctl >/dev/null || { echo "systemd required" >&2; exit 1; }

echo "==> service accounts"
getent group stalwart >/dev/null || groupadd -r stalwart
id -u stalwart >/dev/null 2>&1 || useradd -r -g stalwart -d /var/lib/stalwart -s /usr/sbin/nologin stalwart
getent group iris >/dev/null || groupadd -r iris
id -u iris >/dev/null 2>&1 || useradd -r -g iris -d /var/lib/iris -s /usr/sbin/nologin iris

echo "==> files"
install -m 0755 usr/local/bin/stalwart /usr/local/bin/stalwart
install -m 0755 opt/iris/iris-api     /opt/iris/iris-api
rm -rf /srv/iris/dist && mkdir -p /srv/iris
cp -a srv/iris/dist /srv/iris/dist
install -m 0644 lib/systemd/system/stalwart.service /lib/systemd/system/
install -m 0644 lib/systemd/system/iris.service     /lib/systemd/system/
install -m 0755 usr/local/sbin/mailstack-cert-sync  /usr/local/sbin/
install -m 0755 usr/local/sbin/mailstack-health     /usr/local/sbin/
install -m 0755 usr/local/sbin/mailstack-provision /usr/local/sbin/
install -m 0755 usr/local/sbin/mailstack-setup     /usr/local/sbin/
install -m 0644 lib/systemd/system/mailstack-cleanup.service /lib/systemd/system/
install -m 0644 lib/systemd/system/mailstack-cleanup.timer   /lib/systemd/system/
install -d -m 755 /etc/caddy /etc/mailstack /etc/iris
[ -f /etc/caddy/mailstack.caddy ] || install -m 0644 etc/caddy/mailstack.caddy /etc/caddy/mailstack.caddy
[ -f /etc/mailstack/mailstack.env ] || { install -m 600 /dev/null /etc/mailstack/mailstack.env; cp etc/mailstack/mailstack.env.example /etc/mailstack/mailstack.env; }
install -m 0644 etc/iris/branding.json.example /etc/iris/branding.json.example
[ -f /etc/iris/branding.json ] || install -m 0644 etc/iris/branding.json.example /etc/iris/branding.json

install -d -o stalwart -g stalwart -m 750 /var/lib/stalwart /var/log/stalwart /etc/stalwart
install -d -o iris -g iris -m 750 /var/lib/iris

if [ ! -f /etc/iris/iris.env ]; then
  umask 077
  cat > /etc/iris/iris.env <<EOF
IRIS_ENV=production
IRIS_HOST=127.0.0.1
IRIS_PORT=8000
STALWART_API_URL=http://127.0.0.1:8080
DATABASE_URL=sqlite:/var/lib/iris/iris.db
SESSION_SECRET=$(openssl rand -hex 32)
SEND_EXTERNAL=true
IRIS_INTEGRATION_EMAIL_ENABLED=false
TEMP_INBOX_DOMAIN=
# Comma-separated allow-list for the admin dashboard (#/admin). Empty = nobody.
IRIS_ADMIN_EMAILS=
EOF
  chown root:iris /etc/iris/iris.env && chmod 640 /etc/iris/iris.env
fi

echo "==> services"
systemctl daemon-reload

echo "==> stalwart provisioning"
_pre_domain="${MAIL_DOMAIN:-}"
. /etc/mailstack/mailstack.env 2>/dev/null || true
DOMAIN="${MAILSTACK_DOMAIN:-${_pre_domain:-${MAIL_DOMAIN:-}}}"
if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "example.com" ]; then
  if [ -t 0 ]; then
    printf 'Mail domain for this server (empty = finish in the Stalwart wizard): '
    read -r DOMAIN
  fi
fi
PROVISIONED=0
# Upgrades keep whatever provisioning the server already has: only a fresh
# install (no Iris database yet) or an explicit MAILSTACK_DOMAIN provisions.
if [ -f /var/lib/iris/iris.db ] && [ -z "${MAILSTACK_DOMAIN:-}" ]; then
  echo "existing install found, leaving Stalwart provisioning alone"
  DOMAIN=""
fi
case "$DOMAIN" in
  ""|example.com) : ;;
  *)
    echo "provisioning Stalwart for $DOMAIN ..."
    if MAIL_DOMAIN="$DOMAIN" MAIL_HOST="mail.$DOMAIN" /usr/local/sbin/mailstack-provision; then
      PROVISIONED=1
      sed -i -e "s|^MAIL_DOMAIN=.*|MAIL_DOMAIN=$DOMAIN|" \
             -e "s|^MAIL_HOST=.*|MAIL_HOST=mail.$DOMAIN|" \
             -e "s|^WEBMAIL_HOST=.*|WEBMAIL_HOST=webmail.$DOMAIN|" \
             /etc/mailstack/mailstack.env
    else
      echo "provisioning failed; finish setup in the wizard: http://127.0.0.1:8080/admin"
    fi
    ;;
esac

systemctl enable --now stalwart.service
systemctl enable --now iris.service
systemctl enable --now mailstack-cleanup.timer
printf '17 4 * * *\troot\t/usr/local/sbin/mailstack-cert-sync\n' > /etc/cron.d/mailstack-cert

echo
echo "RustMailStack installed. Next:"
echo "  1. /etc/mailstack/mailstack.env — MAIL_HOST, WEBMAIL_HOST, MAIL_DOMAIN"
if [ "$PROVISIONED" = 1 ]; then
  echo "     Stalwart is provisioned for $DOMAIN"
  echo "     admin credentials: /etc/mailstack/admin.credentials (mode 600)"
  echo "     DNS records: /etc/mailstack/dns-zone.txt"
else
  echo "  2. Stalwart wizard: http://127.0.0.1:8080/admin (tunnel over ssh)"
fi
echo "  3. Caddyfile: import /etc/caddy/mailstack.caddy   (MAIL_HOST/WEBMAIL_HOST as env)"
echo "  4. /etc/iris/branding.json — name, logo, colours, links (optional)"
echo "  5. /usr/local/sbin/mailstack-health"
