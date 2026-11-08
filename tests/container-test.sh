#!/usr/bin/env bash
# Install the .deb in a throwaway Debian 12 container with systemd and check
# that it really comes up: services, unattended provisioning, DNS zone file,
# admin login, API health, cleanup timer.
#
#   tests/container-test.sh rustmailstack_1.4.0_amd64.deb
#
# Needs docker on the host. The container is removed on exit.
set -euo pipefail

DEB=${1:?usage: tests/container-test.sh <path-to.deb>}
DEB=$(cd "$(dirname "$DEB")" && pwd)/$(basename "$DEB")
DOMAIN=${TEST_DOMAIN:-rms-test.local}
IMAGE=${TEST_IMAGE:-debian:12}
NAME=${TEST_NAME:-rustmailstack-test}
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
need() { # need <desc> <cmd...>
  local desc=$1
  shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

[ -f "$DEB" ] || { echo "no such .deb: $DEB" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }

echo "== booting $IMAGE with systemd"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --privileged --cgroupns=private \
  -v "$DEB:/tmp/rms.deb:ro" "$IMAGE" \
  bash -lc 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq systemd-sysv dbus curl openssl ca-certificates python3 >/dev/null 2>&1; exec /sbin/init' >/dev/null

in_c() { docker exec "$NAME" bash -lc "$1"; }

state=''
for _ in $(seq 1 90); do
  state=$(in_c 'systemctl is-system-running' 2>/dev/null || true)
  case "$state" in running|degraded) break ;; esac
  sleep 2
done
case "$state" in
  running|degraded) ok "systemd is up ($state)" ;;
  *) bad "systemd did not come up (state: ${state:-none})"; exit 1 ;;
esac

echo "== installing $(basename "$DEB") for $DOMAIN"
if in_c "DEBIAN_FRONTEND=noninteractive MAILSTACK_DOMAIN=$DOMAIN dpkg -i /tmp/rms.deb" >/tmp/rms-install.log 2>&1; then
  ok "dpkg install"
else
  bad "dpkg install"
  tail -30 /tmp/rms-install.log
  exit 1
fi

echo "== checks"
check_active() { in_c "systemctl is-active --quiet $1"; }
need "stalwart.service active" check_active stalwart.service
need "iris.service active" check_active iris.service
need "cleanup timer enabled" in_c 'systemctl is-enabled --quiet mailstack-cleanup.timer'
need "cleanup run succeeds" in_c 'systemctl start mailstack-cleanup.service && [ "$(systemctl show -p Result --value mailstack-cleanup.service)" = success ]'
need "provisioning marker" in_c "test -f /var/lib/stalwart/.mailstack-provisioned"
need "DNS zone file has DKIM" in_c "grep -q 'v=DKIM1' /etc/mailstack/dns-zone.txt"
need "DNS zone file has MX and SPF" in_c "grep -q 'IN MX' /etc/mailstack/dns-zone.txt && grep -q 'v=spf1' /etc/mailstack/dns-zone.txt"
need "admin credentials file is 600" in_c "[ \"\$(stat -c %a /etc/mailstack/admin.credentials)\" = 600 ]"
need "admin JMAP login" in_c 'curl -fsS -m 5 -u "admin@'"$DOMAIN"':$(cat /etc/mailstack/admin.credentials)" http://127.0.0.1:8080/jmap/session'
need "iris /health" in_c 'curl -fsS -m 5 http://127.0.0.1:8000/health'
need "branding.json seeded" in_c "test -f /etc/iris/branding.json"
need "TLS key pair present" in_c "test -f /etc/stalwart/tls/mail.$DOMAIN.crt && test -f /etc/stalwart/tls/mail.$DOMAIN.key"
need "stalwart runs without the recovery admin" in_c 'pid=$(systemctl show stalwart.service -p MainPID --value); ! tr "\0" "\n" < /proc/$pid/environ | grep -q STALWART_RECOVERY_ADMIN'
need "mailstack.env points at the provisioned domain" in_c "grep -qx 'MAIL_DOMAIN=$DOMAIN' /etc/mailstack/mailstack.env"
need "shipped units keep their hardening" in_c "grep -q '^ProtectSystem=strict' /lib/systemd/system/iris.service"

echo
echo "passed: $PASS, failed: $FAIL"
[ "$FAIL" -eq 0 ]
