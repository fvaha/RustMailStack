# vahid.im identity

Deployment config for the vahid.im mail host. No branch, no fork diff: the
webmail reads all of this at runtime.

```bash
sudo ./deploy/vahid.im/apply.sh          # copies config + assets to /etc/iris/
```

Then reload the page — nothing restarts.

## What it sets

| File | Effect |
|---|---|
| `branding.json` | name `vahid.im`, Serbian tagline/login note/cookie notice, red `#B83232`, footer links `Privatnost` / `Uslovi`, `hideTempInbox: true` |
| `assets/logo.svg` | envelope mark next to the wordmark (ink `#16130F`) |
| `assets/favicon.svg`, `favicon.ico`, `favicon-32.png`, `apple-touch-icon.png` | browser tab + home-screen icon |
| `assets/icon-192.png`, `icon-512.png`, `icon-maskable-512.png` | PWA icons (referenced by the generated manifest) |
| `assets/og-image.png` | 1200×630 social card |

## Why it survives upgrades

`/etc/iris/` is outside the package's `/srv/iris/dist` tree. `apt install
./rustmailstack_*.deb` replaces the app and the systemd units, and leaves the
identity alone — same as `mailstack.env`.

## How it is served

`/etc/caddy/mailstack.caddy` (shipped by the package) maps:

- `/branding.json` → `/etc/iris/branding.json` (`Cache-Control: no-store`)
- `/branding/*` → `/etc/iris/branding/*` (cached for an hour)

## Verify

```bash
curl -s https://webmail.vahid.im/branding.json | head -3
curl -sI https://webmail.vahid.im/branding/logo.svg | head -3
# then open the webmail: title should read "Prijava · vahid.im" (or "Sign in · vahid.im")
```

## Undo

```bash
sudo rm -rf /etc/iris/branding /etc/iris/branding.json
sudo cp /etc/iris/branding.json.example /etc/iris/branding.json   # back to defaults
```
