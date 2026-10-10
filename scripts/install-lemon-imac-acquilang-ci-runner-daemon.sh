#!/bin/bash
# 把 lemon-imac 上的 AcquiLang 仓库级 runner 装成系统 LaunchDaemon。
# 只处理这一个 slot。不碰 cypressoai 的 lemon-imac-1/2。
#
# sudo /Users/for-konghai/gha/scripts/install-lemon-imac-acquilang-ci-runner-daemon.sh
#
# 不要运行 ./svc.sh install / start。那会再写一份用户域 LaunchAgent，和 Daemon 双开。
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "请使用 sudo 运行：$0" >&2
  exit 1
fi

USER_NAME="for-konghai"
GROUP_NAME="staff"
USER_HOME="/Users/${USER_NAME}"
UID_NUM="$(id -u "$USER_NAME")"
RUNNER_ROOT="${USER_HOME}/actions-runner/lemon-imac-acquilang-ci-1"
LABEL="actions.runner.IAmKongHai-AcquiLangAI.lemon-imac-acquilang-ci-1"
PLIST="/Library/LaunchDaemons/${LABEL}.plist"
SOURCE_PLIST="${RUNNER_ROOT}/${LABEL}.plist"
LOG_DIR="${USER_HOME}/Library/Logs/${LABEL}"
USER_AGENT="${USER_HOME}/Library/LaunchAgents/${LABEL}.plist"

if [[ ! -x "${RUNNER_ROOT}/runsvc.sh" && -f "${RUNNER_ROOT}/bin/runsvc.sh" ]]; then
  cp "${RUNNER_ROOT}/bin/runsvc.sh" "${RUNNER_ROOT}/runsvc.sh"
  chown "${USER_NAME}:${GROUP_NAME}" "${RUNNER_ROOT}/runsvc.sh"
  chmod 755 "${RUNNER_ROOT}/runsvc.sh"
fi
if [[ ! -x "${RUNNER_ROOT}/runsvc.sh" || ! -f "${RUNNER_ROOT}/.runner" ]]; then
  echo "runner 尚未注册，或缺少 runsvc.sh：${RUNNER_ROOT}" >&2
  exit 1
fi
if [[ -e "$PLIST" ]] || launchctl print "system/${LABEL}" >/dev/null 2>&1; then
  echo "系统服务已存在，跳过。"
  launchctl print "system/${LABEL}" | grep -E 'state =|pid =|path =' || true
  exit 0
fi
if pgrep -f "${RUNNER_ROOT}/bin/Runner.Worker" >/dev/null; then
  echo "这个 runner 正在执行 job，请等它结束再安装系统服务。" >&2
  exit 1
fi

if launchctl print "user/${UID_NUM}/${LABEL}" >/dev/null 2>&1; then
  echo "卸下用户域 LaunchAgent。"
  launchctl bootout "user/${UID_NUM}/${LABEL}" || true
fi
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if ! pgrep -f "${RUNNER_ROOT}/bin/Runner.Listener" >/dev/null; then
    break
  fi
  sleep 1
done
rm -f "$USER_AGENT"
if pgrep -f "${RUNNER_ROOT}/(bin/Runner.Listener|runsvc.sh)" >/dev/null; then
  echo "listener 还在，请先停掉再安装系统服务。" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"
chown "${USER_NAME}:${GROUP_NAME}" "$LOG_DIR"
cat > "$SOURCE_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key><array><string>${RUNNER_ROOT}/runsvc.sh</string></array>
  <key>UserName</key><string>${USER_NAME}</string>
  <key>GroupName</key><string>${GROUP_NAME}</string>
  <key>WorkingDirectory</key><string>${RUNNER_ROOT}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>SessionCreate</key><true/>
  <key>StandardOutPath</key><string>${LOG_DIR}/stdout.log</string>
  <key>StandardErrorPath</key><string>${LOG_DIR}/stderr.log</string>
  <key>EnvironmentVariables</key><dict>
    <key>ACTIONS_RUNNER_SVC</key><string>1</string>
    <key>HOME</key><string>${USER_HOME}</string>
    <key>LANG</key><string>en_US.UTF-8</string>
    <key>LC_ALL</key><string>en_US.UTF-8</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>PNPM_STORE_PATH</key><string>${USER_HOME}/gha/cache/acquilang-pnpm-store</string>
    <key>npm_config_store_dir</key><string>${USER_HOME}/gha/cache/acquilang-pnpm-store</string>
    <key>NPM_CONFIG_CACHE</key><string>${USER_HOME}/gha/cache/acquilang-npm</string>
  </dict>
</dict></plist>
EOF
chown "${USER_NAME}:${GROUP_NAME}" "$SOURCE_PLIST"
plutil -lint "$SOURCE_PLIST"
install -o root -g wheel -m 644 "$SOURCE_PLIST" "$PLIST"
launchctl enable "system/${LABEL}"
launchctl bootstrap system "$PLIST"
printf '%s\n' "$PLIST" > "${RUNNER_ROOT}/.service"
chown "${USER_NAME}:${GROUP_NAME}" "${RUNNER_ROOT}/.service"
launchctl print "system/${LABEL}" | grep -E 'state =|pid =|path ='
echo "已安装：system/${LABEL}"
