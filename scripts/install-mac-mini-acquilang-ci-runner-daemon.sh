#!/bin/bash
# 在 mac-mini 上安装 AcquiLangAI 日常 CI 的 LaunchDaemon。
# sudo /Users/konghai/gha/scripts/install-mac-mini-acquilang-ci-runner-daemon.sh
# 只安装新服务；已有服务或配置时退出，不重启任何 runner。
set -euo pipefail

RUNNER_ROOT="/Users/konghai/actions-runner/mac-mini-acquilang-ci-1"
LABEL="actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-1"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
SOURCE_PLIST="${RUNNER_ROOT}/${LABEL}.plist"
LOG_DIR="/Users/konghai/Library/Logs/${LABEL}"

if [[ $(id -u) -ne 0 ]]; then
  echo "请使用 sudo 运行：$0" >&2
  exit 1
fi
if [[ ! -x "${RUNNER_ROOT}/runsvc.sh" || ! -f "${RUNNER_ROOT}/.runner" ]]; then
  echo "runner 尚未完成注册或缺少 runsvc.sh" >&2
  exit 1
fi
if [[ -e "$PLIST" ]] || launchctl print "system/${LABEL}" >/dev/null 2>&1; then
  echo "服务或 plist 已存在，请先检查状态；本脚本不会覆盖或重启。" >&2
  exit 1
fi
if pgrep -f "${RUNNER_ROOT}/(bin/Runner.Listener|runsvc.sh)" >/dev/null; then
  echo "该 runner 已有进程，请先检查，避免启动第二个实例。" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"
chown konghai:staff "$LOG_DIR"
cat > "$SOURCE_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key><array><string>${RUNNER_ROOT}/runsvc.sh</string></array>
  <key>UserName</key><string>konghai</string>
  <key>GroupName</key><string>staff</string>
  <key>WorkingDirectory</key><string>${RUNNER_ROOT}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>SessionCreate</key><true/>
  <key>StandardOutPath</key><string>${LOG_DIR}/stdout.log</string>
  <key>StandardErrorPath</key><string>${LOG_DIR}/stderr.log</string>
  <key>EnvironmentVariables</key><dict>
    <key>ACTIONS_RUNNER_SVC</key><string>1</string>
    <key>HOME</key><string>/Users/konghai</string>
    <key>LANG</key><string>en_US.UTF-8</string>
    <key>LC_ALL</key><string>en_US.UTF-8</string>
    <key>PATH</key><string>/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict></plist>
EOF
chown konghai:staff "$SOURCE_PLIST"
plutil -lint "$SOURCE_PLIST"
install -o root -g wheel -m 644 "$SOURCE_PLIST" "$PLIST"
launchctl enable "system/${LABEL}"
launchctl bootstrap system "$PLIST"
printf '%s\n' "$PLIST" > "${RUNNER_ROOT}/.service"
chown konghai:staff "${RUNNER_ROOT}/.service"
launchctl print "system/${LABEL}" | grep -E 'state =|pid =|path ='
echo "已安装：system/${LABEL}"
