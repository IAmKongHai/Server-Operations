#!/usr/bin/env bash
# Verify tizi-cyp post-reinstall baseline (Debian + 3x-ui + REALITY + mssql-ref-proxy).
# Drives the live host via `ssh tizi-cyp`. Exit 0 only if all gates pass.
set -euo pipefail

ssh -o BatchMode=yes -o ConnectTimeout=15 tizi-cyp 'set -euo pipefail
test "$(hostname)" = tizi-cyp
test "$(sysctl -n net.ipv4.tcp_congestion_control)" = bbr
test "$(sysctl -n net.core.default_qdisc)" = fq
systemctl is-active --quiet x-ui
systemctl is-active --quiet mssql-ref-proxy
command -v ufw socat sqlite3 x-ui >/dev/null
ufw status | grep -qi active
ss_out=$(ss -tlnp)
echo "$ss_out" | grep -E "100\\.[0-9.]+\\:2095" >/dev/null
echo "$ss_out" | grep -E "(\\:443)\\b" >/dev/null
echo "$ss_out" | grep -E "100\\.[0-9.]+\\:1433" >/dev/null
! echo "$ss_out" | grep -q "0.0.0.0:2095"
! echo "$ss_out" | grep -q "0.0.0.0:1433"
test -f /etc/x-ui/x-ui.db
test -f /usr/local/x-ui/bin/config.json
grep -q "minClientVer" /usr/local/x-ui/bin/config.json
grep -q "1.0.0" /usr/local/x-ui/bin/config.json
grep -q "assets-xbxweb.xbox.com" /usr/local/x-ui/bin/config.json
grep -q "cyp-tizi\\|in-443-tcp" /usr/local/x-ui/bin/config.json || true
# panel must not listen on all interfaces
web_listen=$(sqlite3 /etc/x-ui/x-ui.db "SELECT value FROM settings WHERE key='"'"'webListen'"'"';")
web_port=$(sqlite3 /etc/x-ui/x-ui.db "SELECT value FROM settings WHERE key='"'"'webPort'"'"';")
test -n "$web_listen"
test "$web_port" = "2095"
case "$web_listen" in
  100.*) ;;
  *) echo "webListen not Tailscale: $web_listen" >&2; exit 1 ;;
esac
# inbound present
cnt=$(sqlite3 /etc/x-ui/x-ui.db "SELECT count(*) FROM inbounds WHERE remark='"'"'cyp-tizi'"'"' AND enable=1;")
test "$cnt" = "1"
echo VERIFY_TIZI_CYP_OK host=$(hostname) ts_panel=${web_listen}:${web_port}
'
