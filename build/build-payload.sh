#!/usr/bin/env bash
# Assemble the install tree from pinned upstream artefacts. No compilation happens
# on the target host; everything is fetched here (CI) and packaged.
#
#   ARCH=amd64 ./build/build-payload.sh
#
# Inputs:  versions.env, artefacts/iris-api-<arch>, artefacts/iris-dist.tgz
# Output:  build/root/  (full filesystem tree, ready for dpkg-deb / tar)
set -euo pipefail
cd "$(dirname "$0")/.."
. ./versions.env
ARCH="${ARCH:-amd64}"
case "$ARCH" in
  amd64) TRIPLE=x86_64-unknown-linux-musl ;;
  arm64) TRIPLE=aarch64-unknown-linux-musl ;;
  *) echo "unsupported ARCH=$ARCH" >&2; exit 1 ;;
esac

ROOT=build/root
rm -rf "$ROOT"; mkdir -p "$ROOT"/{usr/local/bin,etc/iris,etc/mailstack,etc/caddy,opt/iris,srv/iris,lib/systemd/system,usr/local/sbin,var/lib/iris,var/lib/stalwart,var/log/stalwart,etc/stalwart}

# ---- Stalwart: official static musl build of the pinned tag -------------------
TARBALL="stalwart-${TRIPLE}.tar.gz"
URL="https://github.com/stalwartlabs/stalwart/releases/download/${STALWART_TAG}/${TARBALL}"
echo "==> $URL"
curl -fsSL "$URL" -o "/tmp/$TARBALL"
mkdir -p /tmp/stalwart-extract && tar -xzf "/tmp/$TARBALL" -C /tmp/stalwart-extract
BIN="$(find /tmp/stalwart-extract -type f -name stalwart | head -1)"
[ -n "$BIN" ] || { echo "stalwart binary not found in tarball" >&2; exit 1; }
install -m 0755 "$BIN" "$ROOT/usr/local/bin/stalwart"

# ---- IRIS: our fork's artefact ----------------------------------------------
[ -f "artefacts/iris-api-$ARCH" ] || { echo "missing artefacts/iris-api-$ARCH (build the fork first)" >&2; exit 1; }
install -m 0755 "artefacts/iris-api-$ARCH" "$ROOT/opt/iris/iris-api"
[ -f artefacts/iris-dist.tgz ] || { echo "missing artefacts/iris-dist.tgz" >&2; exit 1; }
tar -xzf artefacts/iris-dist.tgz -C "$ROOT/srv/iris"
mv "$ROOT/srv/iris/dist" "$ROOT/srv/iris/dist.tmp" 2>/dev/null || true
mv "$ROOT/srv/iris/dist.tmp" "$ROOT/srv/iris/dist" 2>/dev/null || true

# ---- units, scripts, config templates ---------------------------------------
install -m 0644 payload/systemd/stalwart.service "$ROOT/lib/systemd/system/stalwart.service"
install -m 0644 payload/systemd/iris.service     "$ROOT/lib/systemd/system/iris.service"
install -m 0644 payload/etc/mailstack.env.example "$ROOT/etc/mailstack/mailstack.env.example"
install -m 0644 payload/etc/caddy-mailstack.caddy "$ROOT/etc/caddy/mailstack.caddy"
install -m 0755 payload/scripts/cert-sync.sh  "$ROOT/usr/local/sbin/mailstack-cert-sync"
install -m 0755 payload/scripts/healthcheck.sh "$ROOT/usr/local/sbin/mailstack-health"

echo "==> payload ready: $(du -sh "$ROOT" | cut -f1)  ($ARCH)"
