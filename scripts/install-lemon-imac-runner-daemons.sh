#!/bin/bash
# 把 lemon-imac-1/2 从 LaunchAgent 改成 LaunchDaemon，注销图形用户后仍在线。
# 维护任务一并改成 Daemon（crontab 被 TCC 拒绝，Agent 在 for-konghai 未登录时不跑）。
#
# 必须在 lemon-imac 上以 root 运行：
#   sudo /Users/for-konghai/gha/scripts/install-lemon-imac-runner-daemons.sh
#
# 不要再运行 ./svc.sh install / start，那会把 LaunchAgent 装回去并和 Daemon 双开。
#
# runner 只在 CIWork 卷挂到 ~/gha 后启动：KeepAlive 用 PathState 盯 ~/gha/.ciwork-mounted
# （见 install-lemon-imac-ciwork-automount.sh）。
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "must run as root: sudo $0" >&2
  exit 1
fi

USER_NAME="for-konghai"
GROUP_NAME="staff"
USER_HOME="/Users/${USER_NAME}"
UID_NUM="$(id -u "$USER_NAME")"
STAMP="$(date +%Y%m%d)"
DISABLED_DIR="${USER_HOME}/Library/LaunchAgents.disabled-${STAMP}"
LOG_ROOT="${USER_HOME}/Library/Logs"
PATH_VALUE="/opt/homebrew/bin:/Users/${USER_NAME}/go/bin:/usr/bin:/bin:/usr/sbin:/sbin"

install_daemon() {
  local label="$1"
  local plist="/Library/LaunchDaemons/${label}.plist"
  cat >"$plist"
  chown root:wheel "$plist"
  chmod 644 "$plist"
  plutil -lint "$plist" >/dev/null
  if launchctl print "system/${label}" >/dev/null 2>&1; then
    launchctl bootout "system/${label}" || true
  fi
  launchctl bootstrap system "$plist"
  launchctl enable "system/${label}"
  echo "installed system/${label}"
}

echo "=== disable user LaunchAgents ==="
mkdir -p "$DISABLED_DIR"
chown "${USER_NAME}:${GROUP_NAME}" "$DISABLED_DIR"

for label in \
  actions.runner.cypressoai.lemon-imac-1 \
  actions.runner.cypressoai.lemon-imac-2 \
  com.cypressoai.gha-runner-maintenance \
  com.cypressoai.gha-runner-maintenance-weekly
do
  agent_plist="${USER_HOME}/Library/LaunchAgents/${label}.plist"
  launchctl bootout "gui/${UID_NUM}/${label}" 2>/dev/null || true
  launchctl bootout "user/${UID_NUM}/${label}" 2>/dev/null || true
  launchctl disable "gui/${UID_NUM}/${label}" 2>/dev/null || true
  launchctl disable "user/${UID_NUM}/${label}" 2>/dev/null || true
  if [[ -f "$agent_plist" ]]; then
    mv "$agent_plist" "${DISABLED_DIR}/"
    echo "moved ${agent_plist} -> ${DISABLED_DIR}/"
  fi
done

mkdir -p \
  "${LOG_ROOT}/actions.runner.cypressoai.lemon-imac-1" \
  "${LOG_ROOT}/actions.runner.cypressoai.lemon-imac-2"
chown -R "${USER_NAME}:${GROUP_NAME}" \
  "${LOG_ROOT}/actions.runner.cypressoai.lemon-imac-1" \
  "${LOG_ROOT}/actions.runner.cypressoai.lemon-imac-2"

write_runner_plist() {
  local slot="$1"
  local label="actions.runner.cypressoai.lemon-imac-${slot}"
  local root="${USER_HOME}/actions-runner/lemon-imac-${slot}"
  install_daemon "$label" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>UserName</key>
  <string>${USER_NAME}</string>
  <key>GroupName</key>
  <string>${GROUP_NAME}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${root}/runsvc.sh</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${root}</string>
  <key>RunAtLoad</key>
  <false/>
  <key>KeepAlive</key>
  <dict>
    <key>PathState</key>
    <dict>
      <key>${USER_HOME}/gha/.ciwork-mounted</key>
      <true/>
    </dict>
  </dict>
  <key>SessionCreate</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${LOG_ROOT}/${label}/stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_ROOT}/${label}/stderr.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>ACTIONS_RUNNER_SVC</key>
    <string>1</string>
    <key>HOME</key>
    <string>${USER_HOME}</string>
    <key>PATH</key>
    <string>${PATH_VALUE}</string>
    <key>LANG</key>
    <string>en_US.UTF-8</string>
    <key>LC_ALL</key>
    <string>en_US.UTF-8</string>
    <key>GOCACHE</key>
    <string>${USER_HOME}/gha/cache/go-build-li${slot}</string>
    <key>GOMODCACHE</key>
    <string>${USER_HOME}/go/pkg/mod</string>
    <key>PNPM_STORE_PATH</key>
    <string>${USER_HOME}/gha/cache/pnpm-store</string>
  </dict>
</dict>
</plist>
EOF
  printf '%s\n' "/Library/LaunchDaemons/${label}.plist" >"${root}/.service"
  chown "${USER_NAME}:${GROUP_NAME}" "${root}/.service"
}

echo "=== install runner LaunchDaemons ==="
write_runner_plist 1
write_runner_plist 2

write_maintenance_plist() {
  local label="$1"
  local mode="$2"
  local stdout="$3"
  local stderr="$4"
  local calendar_xml="$5"
  install_daemon "$label" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>UserName</key>
  <string>${USER_NAME}</string>
  <key>GroupName</key>
  <string>${GROUP_NAME}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${USER_HOME}/gha/scripts/gha-runner-maintenance.sh</string>
  </array>
  <key>WorkingDirectory</key>
  <string>${USER_HOME}/gha/scripts</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key>
    <string>${USER_HOME}</string>
    <key>PATH</key>
    <string>${PATH_VALUE}</string>
    <key>WORK_DIRS</key>
    <string>${USER_HOME}/gha/li1 ${USER_HOME}/gha/li2</string>
    <key>GOCACHE_DIRS</key>
    <string>${USER_HOME}/gha/cache/go-build-li1 ${USER_HOME}/gha/cache/go-build-li2</string>
    <key>PNPM_STORE</key>
    <string>${USER_HOME}/gha/cache/pnpm-store</string>
    <key>GOMODCACHE_DIR</key>
    <string>${USER_HOME}/go/pkg/mod</string>
    <key>MODE</key>
    <string>${mode}</string>
    <key>MAX_GB</key>
    <string>12</string>
    <key>LOG_FILE</key>
    <string>${LOG_ROOT}/gha-runner-maintenance.log</string>
  </dict>
${calendar_xml}
  <key>StandardOutPath</key>
  <string>${stdout}</string>
  <key>StandardErrorPath</key>
  <string>${stderr}</string>
</dict>
</plist>
EOF
}

echo "=== install maintenance LaunchDaemons ==="
write_maintenance_plist \
  com.cypressoai.gha-runner-maintenance \
  daily \
  "${LOG_ROOT}/gha-runner-maintenance.stdout.log" \
  "${LOG_ROOT}/gha-runner-maintenance.stderr.log" \
  "  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>3</integer>
    <key>Minute</key>
    <integer>25</integer>
  </dict>"

write_maintenance_plist \
  com.cypressoai.gha-runner-maintenance-weekly \
  weekly \
  "${LOG_ROOT}/gha-runner-maintenance-weekly.stdout.log" \
  "${LOG_ROOT}/gha-runner-maintenance-weekly.stderr.log" \
  "  <key>StartCalendarInterval</key>
  <dict>
    <key>Weekday</key>
    <integer>0</integer>
    <key>Hour</key>
    <integer>4</integer>
    <key>Minute</key>
    <integer>45</integer>
  </dict>"

echo "=== kickstart runners ==="
for slot in 1 2; do
  launchctl kickstart -k "system/actions.runner.cypressoai.lemon-imac-${slot}"
done

sleep 3
echo "=== launchd ==="
launchctl print system | grep actions.runner.cypressoai.lemon-imac || true
echo "=== processes ==="
ps aux | grep -E "Runner\.(Listener|Worker)|runsvc.sh" | grep -v grep || true
echo "done"
