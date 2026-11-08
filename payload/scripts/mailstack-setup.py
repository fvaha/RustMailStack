#!/usr/bin/env python3
"""Provision a fresh Stalwart for this mail stack through the JMAP management API.

Run by mailstack-provision.sh while Stalwart runs directly (not through
systemd) with a one-time recovery admin. Standard library only.

Environment:
  MAIL_DOMAIN       primary mail domain (example.com)
  MAIL_HOST         server hostname (mail.example.com)
  ADMIN_EMAIL       admin address on MAIL_DOMAIN
  ADMIN_PW          admin password
  RECOVERY_PW       one-time recovery admin password
  TEMP_INBOX_DOMAIN optional: temp inbox domain (inbox.example.com)
  TEMP_PW           optional: password for the temp catch-all account

Writes /etc/mailstack/dns-zone.txt for the operator to publish.
Exits 0 on success, 1 with a message on failure.
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

JMAP = "http://127.0.0.1:8080/jmap"
USING = ["urn:ietf:params:jmap:core", "urn:stalwart:jmap"]

DOMAIN = os.environ["MAIL_DOMAIN"].strip().lower()
MAIL_HOST = os.environ["MAIL_HOST"].strip().lower()
ADMIN_EMAIL = os.environ["ADMIN_EMAIL"].strip().lower()
ADMIN_LOCAL = ADMIN_EMAIL.split("@", 1)[0]
ADMIN_PW = os.environ["ADMIN_PW"]
RECOVERY_PW = os.environ["RECOVERY_PW"]
INBOX_DOMAIN = os.environ.get("TEMP_INBOX_DOMAIN", "").strip().lower()
TEMP_PW = os.environ.get("TEMP_PW", "")
TLS_DIR = os.environ.get("TLS_DIR", "/etc/stalwart/tls")


def jmap(body, auth):
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        JMAP + "/", data=data, method="POST",
        headers={"Authorization": auth, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.load(resp)
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def fail(msg):
    print(f"mailstack-setup: error: {msg}", file=sys.stderr)
    sys.exit(1)


def main():
    rec = "Basic " + base64.b64encode(f"admin:{RECOVERY_PW}".encode()).decode()

    # 1. Wait for the management API.
    for _ in range(30):
        try:
            req = urllib.request.Request(JMAP + "/session", headers={"Authorization": rec})
            with urllib.request.urlopen(req, timeout=5) as resp:
                if resp.status == 200:
                    break
        except Exception:
            pass
        time.sleep(2)
    else:
        fail("Stalwart management API did not answer on 127.0.0.1:8080")

    def call(method, args):
        status, res = jmap({"using": USING, "methodCalls": [[method, args, "0"]]}, rec)
        if status != 200:
            fail(f"{method} returned HTTP {status}: {json.dumps(res)[:300]}")
        resp = res["methodResponses"][0][1]
        for key in ("notCreated", "notUpdated", "notDestroyed"):
            if resp.get(key):
                fail(f"{method} refused: {json.dumps(resp[key])[:400]}")
        return resp

    # 2. Domains. Stalwart generates DKIM keys per domain.
    create = {"d-main": {"name": DOMAIN}}
    if INBOX_DOMAIN:
        create["d-inbox"] = {"name": INBOX_DOMAIN}
    res = call("x:Domain/set", {"create": create})
    domain_ids = {DOMAIN: res["created"]["d-main"]["id"]}
    print(f"mailstack-setup: domain {DOMAIN}={domain_ids[DOMAIN]}")
    if INBOX_DOMAIN:
        domain_ids[INBOX_DOMAIN] = res["created"]["d-inbox"]["id"]
        print(f"mailstack-setup: domain {INBOX_DOMAIN}={domain_ids[INBOX_DOMAIN]}")

    # 3. Accounts.
    def account(name, domain, pw, desc):
        res = call("x:Account/set", {"create": {"u1": {
            "@type": "User", "name": name, "domainId": domain_ids[domain],
            "description": desc,
            "credentials": {"0": {"@type": "Password", "secret": pw}},
            "roles": {"@type": "User"}, "permissions": {"@type": "Inherit"},
            "encryptionAtRest": {"@type": "Disabled"},
        }}})
        return res["created"]["u1"]["id"]

    admin_id = account(ADMIN_LOCAL, DOMAIN, ADMIN_PW, "Mail stack admin account")
    print(f"mailstack-setup: account {ADMIN_EMAIL}={admin_id}")

    if INBOX_DOMAIN and TEMP_PW:
        temp_id = account("temp", INBOX_DOMAIN, TEMP_PW, "Temporary inbox catch-all")
        call("x:Domain/set", {"update": {
            domain_ids[INBOX_DOMAIN]: {"catchAllAddress": f"temp@{INBOX_DOMAIN}"}}})
        print(f"mailstack-setup: account temp@{INBOX_DOMAIN}={temp_id}, catch-all set")

    # 4. Server identity.
    call("x:SystemSettings/set", {"create": {"singleton": {
        "defaultHostname": MAIL_HOST,
        "defaultDomainId": domain_ids[DOMAIN],
    }}})
    print(f"mailstack-setup: default hostname {MAIL_HOST}")

    # 5. TLS: the certificate object reads the files mailstack-cert-sync keeps
    # up to date, so a later cert change only needs a reload.
    fullchain = os.path.join(TLS_DIR, f"{MAIL_HOST}.crt")
    privkey = os.path.join(TLS_DIR, f"{MAIL_HOST}.key")
    res = call("x:Certificate/set", {"create": {"le": {
        "certificate": {"@type": "File", "filePath": fullchain},
        "privateKey": {"@type": "File", "filePath": privkey},
    }}})
    cert_id = res["created"]["le"]["id"]
    call("x:SystemSettings/set", {"update": {"singleton": {"defaultCertificateId": cert_id}}})
    call("x:Action/set", {"create": {"a1": {"@type": "ReloadTlsCertificates"}}})
    print(f"mailstack-setup: TLS certificate {cert_id} ({fullchain})")

    # 6. DNS zone file for the operator.
    res = call("x:Domain/get", {"properties": ["name", "dnsZoneFile"]})
    zones = []
    for d in res.get("list", []):
        zones.append(f"# DNS records for {d['name']}\n{d.get('dnsZoneFile') or ''}".rstrip())
    out = "/etc/mailstack/dns-zone.txt"
    with open(out, "w") as f:
        f.write("\n\n".join(zones) + "\n")
    os.chmod(out, 0o640)
    print(f"mailstack-setup: DNS zone file written to {out}")

    # 7. Verify the admin account really can authenticate.
    basic = "Basic " + base64.b64encode(f"{ADMIN_EMAIL}:{ADMIN_PW}".encode()).decode()
    acct = ""
    try:
        req = urllib.request.Request(JMAP + "/session", headers={"Authorization": basic})
        with urllib.request.urlopen(req, timeout=15) as resp:
            sess = json.load(resp)
        acct = sess["primaryAccounts"]["urn:ietf:params:jmap:mail"]
    except Exception as e:
        fail(f"admin JMAP login failed: {e}")
    print(f"mailstack-setup: admin JMAP login OK (account {acct})")


if __name__ == "__main__":
    main()
