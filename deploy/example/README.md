# Example identity

A template for a deployment's own branding. Copy it, edit the values, drop it in:

```bash
sudo install -d -m 755 /etc/iris/branding
sudo install -m 644 branding.json /etc/iris/branding.json
# logo/favicon/OG image, if you have them:
sudo install -m 644 logo.svg favicon.svg og-image.png /etc/iris/branding/
```

Then reload the webmail. No rebuild, no restart. `/etc/iris/` is outside
`/srv/iris/dist`, so package upgrades leave the identity alone.

## What the fields do

| Field | Effect |
|---|---|
| `name` | wordmark, page titles, footer, cookie notice, 404/legal pages |
| `tagline` | sign-in tagline (animated, one word per span) |
| `product` | small label next to the wordmark (`webmail`), PWA name |
| `url` | canonical URL, social card URL, footer home link |
| `contactEmail` / `contactAddress` | footer contact link, Privacy/Terms contact card |
| `themeColor` | `theme-color` meta + PWA manifest |
| `logoUrl` / `faviconUrl` / `ogImageUrl` | images; put the files in `/etc/iris/branding/` and reference them as `/branding/<file>` |
| `hideTempInbox` | `true` hides temporary inboxes from the UI entirely (`#/temp` → 404) |
| `strings.cookieEssential` / `.cookieAnalytics` / `.cookieDetails` / `.loginNote` | optional copy overrides for a localised deployment |
| `links` | footer legal links |

Full schema: `docs/branding.md` in the [irisproject fork](https://github.com/fvaha/irisproject).

## How it is served

`/etc/caddy/mailstack.caddy` (shipped by the package) maps:

- `/branding.json` → `/etc/iris/branding.json` (`Cache-Control: no-store`)
- `/branding/*` → `/etc/iris/branding/*` (cached for an hour)

## Undo

```bash
sudo rm -rf /etc/iris/branding /etc/iris/branding.json
sudo cp /etc/iris/branding.json.example /etc/iris/branding.json
```
