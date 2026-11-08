#!/usr/bin/env bash
# Apply the vahid.im identity to a host running the RustMailStack package.
#
#   sudo ./deploy/vahid.im/apply.sh
#
# Everything lands in /etc/iris/ (never /srv/iris/dist), so a package upgrade
# does not wipe it. No service restart: the web app re-reads branding.json on
# every page load.
set -euo pipefail
cd "$(dirname "$0")"

[ "$(id -u)" -eq 0 ] || { echo "run as root" >&2; exit 1; }

install -d -m 755 /etc/iris/branding
install -m 644 assets/* /etc/iris/branding/
install -m 644 branding.json /etc/iris/branding.json

echo "vahid.im branding applied:"
echo "  /etc/iris/branding.json"
echo "  /etc/iris/branding/ ($(ls assets | wc -l | tr -d ' ') files)"
echo "reload the webmail in a browser — no restart needed."
