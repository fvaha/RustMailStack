# RustMailStack

One installable package for a complete mail stack: [Stalwart](https://stalw.art) (SMTP/IMAP/JMAP
server) plus [IRIS](https://github.com/fvaha/irisproject) (webmail UI, white-label fork).
No Docker, no compiler on the target host, about 90 MB RSS in total.

```
Caddy (HTTPS) ──┬─→ 127.0.0.1:8080  Stalwart  (admin UI + JMAP + mail ports)
                └─→ 127.0.0.1:8000  IRIS      (webmail API; static dist served by Caddy)
```

## What the package contains

| Path | Content |
|---|---|
| `/usr/local/bin/stalwart` | official static musl build of the pinned tag (Debian, Ubuntu, Arch, Fedora) |
| `/opt/iris/iris-api` + `/srv/iris/dist` | webmail API and web bundle from the `fvaha/irisproject` fork |
| `/lib/systemd/system/{stalwart,iris}.service` | units with `MemoryMax` and hardening |
| `/etc/caddy/mailstack.caddy` | two vhosts: mail host to Stalwart, webmail host to IRIS and static files |
| `/usr/local/sbin/mailstack-cert-sync` | daily: copies Caddy's renewed cert into Stalwart, restarts only on change |
| `/usr/local/sbin/mailstack-health` | checks JMAP session, IRIS `/health`, TLS on 993/465 |
| `/etc/mailstack/mailstack.env` | `MAIL_HOST`, `WEBMAIL_HOST`, `MAIL_DOMAIN`, optional `CF_API_TOKEN` |
| `/etc/iris/branding.json` | white-label name, logo, colours, contact, footer links (served at `/branding.json`) |

## Install

```bash
# Debian / Ubuntu
sudo apt install ./rustmailstack_1.3.0_amd64.deb

# any other systemd distro
tar -xzf rustmailstack-1.3.0-amd64.tar.gz -C /tmp/rms && sudo /tmp/rms/install.sh
```

Then set `/etc/mailstack/mailstack.env`, finish the Stalwart wizard on `http://127.0.0.1:8080/admin`
(over an SSH tunnel), `import /etc/caddy/mailstack.caddy` into your Caddyfile, and run
`mailstack-health`.

Two steps stay manual because the provider owns them: the reverse DNS (PTR) record, and at some
providers (netcup, for example) unblocking inbound port 25.

## Branding (white-label)

The webmail ships without any customer identity. The package creates `/etc/iris/branding.json` on
first install from `branding.json.example`. Edit it and reload the page; there is no rebuild and no
restart:

```json
{
  "name": "Acme Mail",
  "tagline": "Mail that stays yours.",
  "product": "webmail",
  "url": "https://mail.acme.com",
  "contactEmail": "postmaster@acme.com",
  "contactAddress": "Acme d.o.o., Ulica 1, 11000 Beograd",
  "themeColor": "#0F62FE",
  "logoUrl": "/branding/logo.svg",
  "faviconUrl": "/branding/favicon.svg",
  "ogImageUrl": "/branding/og-image.png",
  "hideTempInbox": false,
  "links": [
    { "label": "Privacy", "href": "/privacy/" },
    { "label": "Terms", "href": "/terms/" }
  ]
}
```

Every field is optional, and missing values fall back to the shipped defaults. The three image
fields take any URL the browser can load. Put the files in `/etc/iris/branding/` (served at
`/branding/*`, and kept outside `/srv/iris/dist` so upgrades do not touch them) and reference them
as `/branding/logo.svg`. The full schema is in `docs/branding.md` in the
[irisproject fork](https://github.com/fvaha/irisproject).

`deploy/example/` has a template you can copy and edit. Identities for real deployments live in
private repos, not in this one.

## Repo layout (payload-first)

```
versions.env              pinned STALWART_TAG / IRIS_REF; bump and tag to ship an update
payload/                  units, Caddy snippet, scripts, env example (arch independent)
build/build-payload.sh    fetches the pinned binaries, assembles build/root/
debian/                   control, postinst, prerm  ->  .deb
install.sh                same tree, no dpkg  ->  portable tarball
deploy/example/           branding.json template for a deployment's own identity
.github/workflows/        tag v* -> amd64 + arm64: .deb and .tar.gz on the release
```

`build/build-payload.sh` produces one filesystem tree. `dpkg-deb` and `tar` are two wrappers around
it, so adding an `.rpm` later is one `fpm -s dir -t rpm` line on the same tree.

## Releases

`versions.env` pins both halves of the stack: `STALWART_TAG` and `IRIS_REF`, the latter a tag of the
webmail fork. Bumping either one is the whole update procedure, because CI checks out exactly that
ref, so what is tested is what ships.

Push a tag: `git tag v1.3.0 && git push --tags`. CI builds IRIS from the pinned fork tag, downloads
the pinned Stalwart release, and attaches:

- `rustmailstack_1.3.0_amd64.deb`, `rustmailstack_1.3.0_arm64.deb`
- `rustmailstack-1.3.0-amd64.tar.gz`, `rustmailstack-1.3.0-arm64.tar.gz`

## Status

- [x] packaging skeleton, units, Caddy snippet, cert sync, health check
- [x] CI matrix (amd64 + arm64), `.deb` and tarball
- [x] white-label branding via `/etc/iris/branding.json` (webmail 0.4.0)
- [ ] unattended Stalwart configuration (today: the setup wizard, one screen)
- [ ] automatic DNS records for the first domain (needs `CF_API_TOKEN`)
- [ ] `.rpm` (payload-first, about 30 minutes when needed)

## Licence

Packaging is MIT. Bundled components keep their own licences: Stalwart (AGPL-3.0), IRIS
(MIT/Apache-2.0). Upstream sources are linked above and nothing is re-licensed here.
