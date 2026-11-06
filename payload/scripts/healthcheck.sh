#!/bin/sh
# Exit non-zero if the stack is not serving. Used by postinst and by ops.
set -u
fail=0
check() { printf '%-34s ' "$1"; shift; if "$@" >/dev/null 2>&1; then echo OK; else echo FAIL; fail=1; fi; }

check "stalwart: jmap session"  curl -fsS -m 5 -o /dev/null http://127.0.0.1:8080/jmap/session
check "iris: /health"           curl -fsS -m 5 -o /dev/null http://127.0.0.1:8000/health
check "imaps 993 tls"           sh -c 'echo | timeout 5 openssl s_client -connect 127.0.0.1:993 -servername "$(grep ^MAIL_HOST= /etc/mailstack/mailstack.env | cut -d= -f2)" 2>/dev/null | grep -q "BEGIN CERTIFICATE"'
check "smtps 465 tls"           sh -c 'echo | timeout 5 openssl s_client -connect 127.0.0.1:465 -servername "$(grep ^MAIL_HOST= /etc/mailstack/mailstack.env | cut -d= -f2)" 2>/dev/null | grep -q "BEGIN CERTIFICATE"'
exit $fail
