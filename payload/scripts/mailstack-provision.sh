#!/bin/sh
# Provision Stalwart for a fresh RustMailStack install: one domain, one admin
# account, optional temp-inbox catch-all, TLS certificate object and the DNS
# zone file the operator has to publish. Idempotent: a marker stops it from
# running twice.
#
#   MAIL_DOMAIN=example.com MAIL_ADMIN_EMAIL=admin@example.com mailstack-provision
#
# Reads MAIL_DOMAIN / MAIL_HOST / TEMP_INBOX_DOMAIN from
# /etc/mailstack/mailstack.env. Prints the admin password to stdout once.
set -eu

ENV_FILE=/etc/mailstack/mailstack.env
MARKER=/var/lib/stalwart/.mailstack-provisioned
CREDS=/etc/mailstack/admin.credentials
TLS_DIR=/etc/stalwart/tls
LOG=/var/log/stalwart/setup.log

# Values passed on the command line win over the env file.
_explicit_domain="${MAIL_DOMAIN:-}"
_explicit_host="${MAIL_HOST:-}"
_explicit_admin="${MAIL_ADMIN_EMAIL:-}"

log() { echo "mailstack-provision: $*" >&2; }
die() { echo "mailstack-provision: error: $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root"
[ -f "$ENV_FILE" ] && . "$ENV_FILE"

DOMAIN="${_explicit_domain:-${MAIL_DOMAIN:-${IRIS_DOMAIN:-}}}"
DOMAIN=$(printf '%s' "$DOMAIN" | tr 'A-Z' 'a-z')
case "$DOMAIN" in
  ""|example.com)
    die "MAIL_DOMAIN is not set (edit $ENV_FILE or pass MAIL_DOMAIN=...)" ;;
  *://*|*/*|*_*|*..*|.*|*.)
    die "MAIL_DOMAIN '$DOMAIN' is not a plain domain name" ;;
  *.*) ;;
  *) die "MAIL_DOMAIN '$DOMAIN' needs at least one dot" ;;
esac

MAIL_HOST="${_explicit_host:-${MAIL_HOST:-mail.$DOMAIN}}"
ADMIN_EMAIL="${_explicit_admin:-${MAIL_ADMIN_EMAIL:-admin@$DOMAIN}}"
ADMIN_EMAIL=$(printf '%s' "$ADMIN_EMAIL" | tr 'A-Z' 'a-z')
case "$ADMIN_EMAIL" in
  *"@$DOMAIN") ;;
  *) die "MAIL_ADMIN_EMAIL must be an address on $DOMAIN" ;;
esac
TEMP_INBOX_DOMAIN="${TEMP_INBOX_DOMAIN:-}"

if [ -f "$MARKER" ]; then
  log "already provisioned ($MARKER); nothing to do"
  exit 0
fi

# --- Stalwart store config -------------------------------------------------
# Written once; an existing config (manual wizard or older install) is left
# alone. The service unit passes this path explicitly.
if [ ! -f /etc/stalwart/config.json ]; then
  printf '{"@type":"RocksDb","path":"/var/lib/stalwart/data"}\n' > /etc/stalwart/config.json
  log "wrote /etc/stalwart/config.json"
fi
chown root:stalwart /etc/stalwart/config.json
chmod 640 /etc/stalwart/config.json
install -d -o stalwart -g stalwart -m 750 /var/lib/stalwart/data

# --- TLS material ----------------------------------------------------------
# Self-signed for the first boot; mailstack-cert-sync replaces these files
# with the Caddy certificate once the host resolves and ACME has run.
install -d -o root -g stalwart -m 750 "$TLS_DIR"
if [ ! -f "$TLS_DIR/$MAIL_HOST.crt" ] || [ ! -f "$TLS_DIR/$MAIL_HOST.key" ]; then
  openssl req -x509 -newkey rsa:2048 -days 30 -nodes \
    -keyout "$TLS_DIR/$MAIL_HOST.key" -out "$TLS_DIR/$MAIL_HOST.crt" \
    -subj "/CN=$MAIL_HOST" 2>/dev/null
  log "generated a 30-day self-signed certificate for $MAIL_HOST"
fi
chown root:stalwart "$TLS_DIR/$MAIL_HOST.crt" "$TLS_DIR/$MAIL_HOST.key"
chmod 640 "$TLS_DIR/$MAIL_HOST.crt" "$TLS_DIR/$MAIL_HOST.key"

# --- admin password --------------------------------------------------------
if [ -f "$CREDS" ]; then
  ADMIN_PW=$(cat "$CREDS")
else
  if [ -n "${MAIL_ADMIN_PASSWORD:-}" ]; then
    ADMIN_PW="$MAIL_ADMIN_PASSWORD"
  else
    ADMIN_PW=$(openssl rand -hex 12)
  fi
  umask 077
  printf '%s\n' "$ADMIN_PW" > "$CREDS"
  chmod 600 "$CREDS"
fi

TEMP_PW=""
if [ -n "$TEMP_INBOX_DOMAIN" ]; then
  if grep -q '^TEMP_INBOX_MAIL_PASSWORD=' /etc/iris/iris.env 2>/dev/null; then
    TEMP_PW=$(sed -n 's/^TEMP_INBOX_MAIL_PASSWORD=//p' /etc/iris/iris.env)
  fi
  [ -n "$TEMP_PW" ] || TEMP_PW=$(openssl rand -hex 16)
fi

# --- provision through the one-time recovery admin ------------------------
RECOVERY_PW=$(openssl rand -hex 16)
install -d -m 755 /var/log/stalwart
: > "$LOG"

runuser -u stalwart -- env "STALWART_RECOVERY_ADMIN=admin:$RECOVERY_PW" \
  "SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt" \
  /usr/local/bin/stalwart --config /etc/stalwart/config.json >>"$LOG" 2>&1 &
SETUP_PID=$!
# shellcheck disable=SC2064
trap "kill $SETUP_PID 2>/dev/null || true" EXIT INT TERM

if ! MAIL_DOMAIN="$DOMAIN" MAIL_HOST="$MAIL_HOST" ADMIN_EMAIL="$ADMIN_EMAIL" \
     ADMIN_PW="$ADMIN_PW" RECOVERY_PW="$RECOVERY_PW" \
     TEMP_INBOX_DOMAIN="$TEMP_INBOX_DOMAIN" TEMP_PW="$TEMP_PW" TLS_DIR="$TLS_DIR" \
     /usr/local/sbin/mailstack-setup; then
  die "provisioning failed; see $LOG"
fi

kill "$SETUP_PID" 2>/dev/null || true
wait "$SETUP_PID" 2>/dev/null || true
trap - EXIT INT TERM

touch "$MARKER"
chown stalwart:stalwart "$MARKER"
log "Stalwart provisioned for $DOMAIN"
echo
echo "Admin account: $ADMIN_EMAIL"
echo "Admin password (also stored in $CREDS, mode 600):"
echo "  $ADMIN_PW"
echo "DNS records to publish: /etc/mailstack/dns-zone.txt"
