# RustMailStack

One installable package for a complete mail stack: **[Stalwart](https://stalw.art)** (SMTP/IMAP/JMAP
server) plus **[IRIS](https://github.com/fvaha/irisproject)** (webmail UI, white-label fork).
No Docker, no compiler on the target host, ~90 MB RSS in total.

```
Caddy (HTTPS) ──┬─→ 127.0.0.1:8080  Stalwart  (admin UI + JMAP + mail ports)
                └─→ 127.0.0.1:8000  IRIS      (webmail API; static dist served by Caddy)
```

## What the package contains

| Path | Content |
|---|---|
| `/usr/local/bin/stalwart` | official static **musl** build of the pinned tag (works on Debian/Ubuntu/Arch/Fedora alike) |
| `/opt/iris/iris-api` + `/srv/iris/dist` | webmail API and web bundle from the `fvaha/irisproject` fork |
| `/lib/systemd/system/{stalwart,iris}.service` | units with `MemoryMax` and hardening |
| `/etc/caddy/mailstack.caddy` | two vhosts: mail host → Stalwart, webmail host → IRIS + static |
| `/usr/local/sbin/mailstack-cert-sync` | daily: copies Caddy's renewed cert into Stalwart, restarts only on change |
| `/usr/local/sbin/mailstack-health` | checks JMAP session, IRIS `/health`, TLS on 993/465 |
| `/etc/mailstack/mailstack.env` | `MAIL_HOST`, `WEBMAIL_HOST`, `MAIL_DOMAIN`, optional `CF_API_TOKEN` |
| `/etc/iris/branding.json` | white-label name, logo, colours, contact, footer links (served at `/branding.json`) |

## Install

```bash
# Debian / Ubuntu
sudo apt install ./rustmailstack_1.0.0_amd64.deb

# any other systemd distro
tar -xzf rustmailstack-1.0.0-amd64.tar.gz -C /tmp/rms && sudo /tmp/rms/install.sh
```

Then: set `/etc/mailstack/mailstack.env`, finish the Stalwart wizard on `http://127.0.0.1:8080/admin`
(over an SSH tunnel), `import /etc/caddy/mailstack.caddy` into your Caddyfile, run `mailstack-health`.

**Manual steps no package can do:** the reverse DNS (PTR) record and, at some providers (netcup),
unblocking incoming port 25 — both are provider-side.

## Branding (white-label)

The webmail ships with no customer identity of its own. `/etc/iris/branding.json` is created on first
install from `branding.json.example`; edit it and reload the page — no rebuild, no restart:

```json
{
  "name": "Acme Mail",
  "tagline": "Mail that stays yours.",
  "product": "webmail",
  "url": "https://mail.acme.com",
  "contactEmail": "postmaster@acme.com",
  "contactAddress": "Acme d.o.o., Ulica 1, 11000 Beograd",
  "themeColor": "#0F62FE",
  "logoUrl": "/acme-logo.svg",
  "faviconUrl": "/acme-favicon.svg",
  "links": [
    { "label": "Privacy", "href": "/privacy/" },
    { "label": "Terms", "href": "/terms/" },
    { "label": "Status", "href": "https://status.acme.com" }
  ]
}
```

Every field is optional; missing values fall back to the shipped defaults. `logoUrl` / `faviconUrl` /
`ogImageUrl` are URLs the browser can load: put the files in `/etc/iris/branding/` (served at
`/branding/*`, survives upgrades) and reference them as `/branding/logo.svg`.
Full schema: `docs/branding.md` in the [irisproject fork](https://github.com/fvaha/irisproject).

A worked example — the vahid.im identity, Serbian copy, hidden temporary inboxes — lives in
[`deploy/vahid.im/`](deploy/vahid.im): `sudo ./deploy/vahid.im/apply.sh`.

## Repo layout (payload-first)

```
versions.env              pinned STALWART_TAG / IRIS_REF — bump + tag to ship an update
payload/                  units, Caddy snippet, scripts, env example (arch-independent)
build/build-payload.sh    fetches the pinned binaries, assembles build/root/
debian/                   control + postinst + prerm  →  .deb
install.sh                same tree, no dpkg  →  portable tarball
deploy/vahid.im/          example identity: branding.json + assets + apply.sh
.github/workflows/        tag v* → amd64 + arm64: .deb and .tar.gz attached to the release
```

`build/build-payload.sh` produces one filesystem tree; `dpkg-deb` and `tar` are just two wrappers
around it. Adding an `.rpm` later is one `fpm -s dir -t rpm` line on the same tree.

## Releases

`versions.env` pins both halves of the stack: `STALWART_TAG` and `IRIS_REF` (a tag of the webmail
fork). Bumping either is the whole update procedure — CI checks out exactly that ref, so what is
tested is what ships.

Push a tag: `git tag v1.2.0 && git push --tags` → CI builds IRIS from the pinned fork tag, downloads
the pinned Stalwart release, and attaches:

- `rustmailstack_1.2.0_amd64.deb`, `rustmailstack_1.2.0_arm64.deb`
- `rustmailstack-1.2.0-amd64.tar.gz`, `rustmailstack-1.2.0-arm64.tar.gz`

## Status

- [x] packaging skeleton, units, Caddy snippet, cert sync, health check
- [x] CI matrix (amd64 + arm64), `.deb` + tarball
- [x] white-label branding via `/etc/iris/branding.json` (webmail 0.3.0)
- [ ] unattended Stalwart configuration (today: the setup wizard, one screen)
- [ ] automatic DNS records for the first domain (needs `CF_API_TOKEN`)
- [ ] `.rpm` (payload-first, ~30 min when needed)

## Licence

Packaging: MIT. Bundled components keep their own licences — Stalwart (AGPL-3.0),
IRIS (MIT/Apache-2.0). Upstream sources are linked above; nothing is re-licensed here.
