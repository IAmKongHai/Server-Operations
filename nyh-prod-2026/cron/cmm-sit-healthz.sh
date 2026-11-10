#!/bin/bash
# Keep nyh-prod -> mas-go-dev Tailscale direct and detect a hung SIT API.
exec 9>/var/lock/cmm-sit-healthz.lock
flock -n 9 || exit 0
for i in 1 2; do
  tailscale ping --c 1 --timeout 2s 100.109.223.53 >/dev/null 2>&1 || true
  curl -fsS --max-time 3 http://100.109.223.53:25880/healthz >/dev/null 2>&1 || true
  if [ "$i" = 1 ]; then
    sleep 30
  fi
done
