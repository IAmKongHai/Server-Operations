#!/bin/bash
# lemon-imac: 重启 Homebrew tailscaled LaunchDaemon。
# 不装 GUI、不改 hostname、尽量保住节点 IPv4 100.81.246.93。
#
# 会短暂掐断经 Tailscale 的 SSH。脚本忽略 SIGHUP，sudo 应能跑完。
# 重连后看：
#   cat /tmp/restart-lemon-imac-tailscaled.log
#
# 用法（在 lemon-imac 本机 SSH 里）：
#   sudo /Users/for-konghai/gha/scripts/restart-lemon-imac-tailscaled.sh
set -euo pipefail
trap '' HUP

LABEL=system/homebrew.mxcl.tailscale
PLIST=/Library/LaunchDaemons/homebrew.mxcl.tailscale.plist
TS=/opt/homebrew/bin/tailscale
TSD=/opt/homebrew/opt/tailscale/bin/tailscaled
EXPECT_IPV4=100.81.246.93
HOSTNAME_FLAG=lemon-imac
OPERATOR=for-konghai
SONAR_URL=http://mac-mini:9000/api/system/status
SONAR_IP_URL=http://100.108.64.126:9000/api/system/status
LOG=/tmp/restart-lemon-imac-tailscaled.log

if [[ $(id -u) -ne 0 ]]; then
  echo "must run as root: sudo $0" >&2
  exit 1
fi

if [[ -d /Applications/Tailscale.app ]]; then
  echo "ERROR: /Applications/Tailscale.app still present. Uninstall the GUI first." >&2
  exit 1
fi

if pgrep -lf 'io.tailscale.ipn.macsys' >/dev/null; then
  echo "ERROR: Standalone system extension still running." >&2
  pgrep -lf 'io.tailscale.ipn.macsys' || true
  exit 1
fi

if [[ ! -x $TSD || ! -x $TS ]]; then
  echo "ERROR: brew tailscale missing. Expected $TSD and $TS" >&2
  exit 1
fi

if [[ ! -f $PLIST ]]; then
  echo "ERROR: $PLIST missing" >&2
  exit 1
fi

exec > >(tee -a "$LOG") 2>&1

echo "=== restart lemon-imac tailscaled $(date) ==="
echo "log: $LOG"
echo "old pid=$(pgrep -x tailscaled || echo none)"
echo "old ipv4=$($TS ip -4 2>/dev/null || echo unknown)"
echo
echo "SSH over Tailscale will drop in 3s. Abort with Ctrl-C now if needed."
sleep 3

echo "=== kickstart $LABEL ==="
if ! launchctl print "$LABEL" >/dev/null 2>&1; then
  echo "service not loaded; bootstrap $PLIST"
  launchctl bootstrap system "$PLIST"
fi
launchctl kickstart -k "$LABEL"

echo "=== wait for daemon ==="
ok=0
for i in $(seq 1 20); do
  if pgrep -x tailscaled >/dev/null; then
    ok=1
    break
  fi
  sleep 1
done
if [[ $ok -ne 1 ]]; then
  echo "ERROR: tailscaled did not come back" >&2
  exit 1
fi
echo "new pid=$(pgrep -x tailscaled)"

echo "=== tailscale up ==="
"$TS" up \
  --hostname="$HOSTNAME_FLAG" \
  --operator="$OPERATOR" \
  --accept-dns=true \
  --accept-routes=false

echo "=== wait for ipv4 ==="
ipv4=
for i in $(seq 1 20); do
  ipv4=$("$TS" ip -4 2>/dev/null || true)
  if [[ -n ${ipv4:-} ]]; then
    break
  fi
  sleep 1
done
echo "ipv4=${ipv4:-unknown}"
if [[ ${ipv4:-} != "$EXPECT_IPV4" ]]; then
  echo "WARNING: expected $EXPECT_IPV4, got ${ipv4:-unknown}. Restore in admin console if MagicDNS/ssh config break."
fi

echo
echo "=== status ==="
"$TS" status --self | head -5 || true
launchctl print "$LABEL" 2>/dev/null | awk '/path =|state =|pid =|program =/' | head -10 || true

echo
echo "=== verify Sonar TCP / MagicDNS ==="
curl -sS -m 8 -w "name http=%{http_code} time=%{time_total} err=%{errormsg}\n" -o /tmp/sonar-status.json "$SONAR_URL" || true
echo -n "body: "; cat /tmp/sonar-status.json 2>/dev/null || true
echo
curl -sS -m 8 -w "ip   http=%{http_code} time=%{time_total} err=%{errormsg}\n" -o /dev/null "$SONAR_IP_URL" || true
python3 - <<'PY'
import socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.settimeout(5)
try:
    s.connect(("100.108.64.126", 9000))
    print("tcp  OK", s.getsockname(), "->", s.getpeername())
except OSError as e:
    print("tcp  FAIL", e)
finally:
    s.close()
PY

echo
echo "done $(date). If this SSH session died, reconnect: ssh lemon-imac"
echo "then: cat $LOG"
