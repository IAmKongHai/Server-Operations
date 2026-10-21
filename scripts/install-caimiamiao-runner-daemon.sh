#!/bin/bash
# 把 org `caimiamiao` 的 runner caimiamiao-1 装成 LaunchDaemon。
# 注销图形用户、重启后仍在线。必须在 mac-mini 上以 root 运行：
#   sudo /Users/konghai/gha/scripts/install-caimiamiao-runner-daemon.sh
#
# 不要运行 ./svc.sh install / start，那会把 LaunchAgent 装回
# ~/Library/LaunchAgents，登录后和 Daemon 双开。
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "must run as root: sudo $0" >&2
  exit 1
fi

if pgrep -f '/Users/konghai/actions-runner/caimiamiao-1/.*/Runner.Worker' >/dev/null; then
  echo "ERROR: Runner.Worker is running; wait for the job to finish." >&2
  pgrep -lf 'caimiamiao-1.*Runner.Worker' || true
  exit 1
fi

USER_NAME="konghai"
GROUP_NAME="staff"
USER_HOME="/Users/${USER_NAME}"
ROOT="${USER_HOME}/actions-runner/caimiamiao-1"
LABEL="actions.runner.caimiamiao.caimiamiao-1"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
SRC_PLIST="${ROOT}/${LABEL}.plist"
LOG_DIR="${USER_HOME}/Library/Logs/${LABEL}"

if [[ ! -x "${ROOT}/runsvc.sh" ]]; then
  echo "missing ${ROOT}/runsvc.sh" >&2
  exit 1
fi
if [[ ! -f "$SRC_PLIST" ]]; then
  echo "missing ${SRC_PLIST}" >&2
  exit 1
fi

# 先停掉临时 nohup，避免和 Daemon 双开 Listener
while read -r pid; do
  [[ -n "$pid" ]] || continue
  kill -TERM "$pid" 2>/dev/null || true
done < <(pgrep -f '/Users/konghai/actions-runner/caimiamiao-1/bin/Runner.Listener' || true)
while read -r pid; do
  [[ -n "$pid" ]] || continue
  kill -TERM "$pid" 2>/dev/null || true
done < <(pgrep -f '/Users/konghai/actions-runner/caimiamiao-1/runsvc.sh' || true)
sleep 1

mkdir -p "$LOG_DIR"
chown "${USER_NAME}:${GROUP_NAME}" "$LOG_DIR"

cp "$SRC_PLIST" "$PLIST"
chown root:wheel "$PLIST"
chmod 644 "$PLIST"
plutil -lint "$PLIST" >/dev/null

if launchctl print "system/${LABEL}" >/dev/null 2>&1; then
  launchctl bootout "system/${LABEL}" || true
fi
launchctl bootstrap system "$PLIST"
launchctl enable "system/${LABEL}"
launchctl kickstart -k "system/${LABEL}"

printf '%s\n' "$PLIST" >"${ROOT}/.service"
chown "${USER_NAME}:${GROUP_NAME}" "${ROOT}/.service"

sleep 2
echo "=== launchd ==="
launchctl print "system/${LABEL}" | grep -E 'state =|pid =|path =' || true
echo "=== processes ==="
ps aux | grep -E "caimiamiao-1.*(runsvc|Runner.Listener)" | grep -v grep || true
echo "done: system/${LABEL}"
