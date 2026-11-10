#!/bin/bash
# 1) Prefer public DNS — Aliyun VPC DNS 100.100.2.x sits in Tailscale CGNAT 100.64/10;
#    ts-input drops replies from that range unless on tailscale0.
# 2) Keep host routes as belt-and-suspenders if something still uses 100.100.2.x.
set -e
resolvectl dns eth0 223.5.5.5 223.6.6.6 8.8.8.8 2>/dev/null || true
resolvectl domain eth0 "~." 2>/dev/null || true
GW=$(ip route | awk "/default/ {print \$3; exit}")
ETH=$(ip route | awk "/default/ {print \$5; exit}")
if [ -n "$GW" ] && [ -n "$ETH" ]; then
  ip route replace 100.100.2.136/32 via "$GW" dev "$ETH" 2>/dev/null || true
  ip route replace 100.100.2.138/32 via "$GW" dev "$ETH" 2>/dev/null || true
fi
