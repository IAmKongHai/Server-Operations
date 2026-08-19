#!/bin/bash
# umacbook-pro: 在 GUI Tailscale 卸掉之后，把 Homebrew tailscaled 拉成 LaunchDaemon。
# 必须已经卸掉 /Applications/Tailscale.app，否则两边会抢隧道。
#   sudo /Users/for-konghai/gha/scripts/start-umacbook-pro-tailscaled.sh
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "must run as root: sudo $0" >&2
  exit 1
fi

if [[ -d /Applications/Tailscale.app ]]; then
  echo "ERROR: /Applications/Tailscale.app still present. Uninstall the GUI first." >&2
  echo "Drag it to Trash, confirm the system extension removal, empty Trash, reboot if asked." >&2
  exit 1
fi

if pgrep -lf 'io.tailscale.ipn.macsys' >/dev/null; then
  echo "ERROR: Standalone system extension still running. Reboot after uninstalling the .app." >&2
  pgrep -lf 'io.tailscale.ipn.macsys' || true
  exit 1
fi

BREW=/opt/homebrew/bin/brew
if [[ ! -x $BREW ]]; then
  echo "ERROR: Homebrew missing at $BREW" >&2
  exit 1
fi

if [[ ! -x /opt/homebrew/opt/tailscale/bin/tailscaled ]]; then
  echo "ERROR: brew tailscale not installed. Run: $BREW install tailscale" >&2
  exit 1
fi

echo "=== start brew tailscaled ==="
"$BREW" services start tailscale

echo "=== wait for daemon ==="
for i in 1 2 3 4 5 6 7 8 9 10; do
  if /opt/homebrew/bin/tailscale status >/dev/null 2>&1 || pgrep -x tailscaled >/dev/null; then
    break
  fi
  sleep 1
done

echo "=== tailscale up ==="
/opt/homebrew/bin/tailscale up \
  --hostname=umacbook-pro \
  --operator=for-konghai \
  --accept-dns=true \
  --accept-routes=false

echo
echo "=== status ==="
/opt/homebrew/bin/tailscale status | head -5 || true
echo
echo "IPv4: $(/opt/homebrew/bin/tailscale ip -4 2>/dev/null || echo unknown)"
echo
echo "If you see a login URL above, open it in the browser on this Mac, then run:"
echo "  /opt/homebrew/bin/tailscale ip -4"
echo "and paste the new 100.x address back in chat. You can also set the admin IPv4 back to 100.113.23.49."
