#!/bin/bash
# 在 mac-mini 上安装 AcquiLangAI 日常 CI 的 LaunchDaemon。
# sudo /Users/konghai/gha/scripts/install-mac-mini-acquilang-ci-runner-daemon.sh [slot...]
# 不带参数时只处理 slot 1。只安装新服务；已有服务或配置时跳过该 slot，不覆盖、不重启。
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "请使用 sudo 运行：$0" >&2
  exit 1
fi

slots=("$@")
if [[ ${#slots[@]} -eq 0 ]]; then
  slots=(1)
fi

install_slot() {
  local slot="$1"
  if [[ ! "$slot" =~ ^[1-9][0-9]*$ ]]; then
    echo "slot 必须是正整数：${slot}" >&2
    exit 1
  fi

  local runner_root="/Users/konghai/actions-runner/mac-mini-acquilang-ci-${slot}"
  local label="actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-${slot}"
  local plist="/Library/LaunchDaemons/${label}.plist"
  local source_plist="${runner_root}/${label}.plist"
  local log_dir="/Users/konghai/Library/Logs/${label}"

  if [[ ! -x "${runner_root}/runsvc.sh" && -f "${runner_root}/bin/runsvc.sh" ]]; then
    # config.sh 不生成根目录的 runsvc.sh。不跑 svc.sh install，避免它再写一份用户域 LaunchAgent。
    cp "${runner_root}/bin/runsvc.sh" "${runner_root}/runsvc.sh"
    chown konghai:staff "${runner_root}/runsvc.sh"
    chmod 755 "${runner_root}/runsvc.sh"
  fi
  if [[ ! -x "${runner_root}/runsvc.sh" || ! -f "${runner_root}/.runner" ]]; then
    echo "slot ${slot} 尚未完成注册或缺少 runsvc.sh" >&2
    exit 1
  fi
  if [[ -e "$plist" ]] || launchctl print "system/${label}" >/dev/null 2>&1; then
    echo "slot ${slot} 的服务或 plist 已存在，跳过。"
    return 0
  fi
  # 系统域 plist 需要 sudo。注册后先用用户域 LaunchAgent 把 runner 拉起来；
  # 这里把它卸下，再装成重启后仍在的 LaunchDaemon。正在跑 job 时不打断。
  local user_uid user_agent i
  user_uid="$(id -u konghai)"
  user_agent="/Users/konghai/Library/LaunchAgents/${label}.plist"
  if pgrep -f "${runner_root}/bin/Runner.Worker" >/dev/null; then
    echo "slot ${slot} 正在执行 job，请等它结束再安装系统服务。" >&2
    exit 1
  fi
  if launchctl print "user/${user_uid}/${label}" >/dev/null 2>&1; then
    echo "卸下 slot ${slot} 的用户域 LaunchAgent。"
    launchctl bootout "user/${user_uid}/${label}" || true
  fi
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if ! pgrep -f "${runner_root}/bin/Runner.Listener" >/dev/null; then
      break
    fi
    sleep 1
  done
  rm -f "$user_agent"
  if pgrep -f "${runner_root}/(bin/Runner.Listener|runsvc.sh)" >/dev/null; then
    echo "slot ${slot} 的进程还在，请先停掉再安装。" >&2
    exit 1
  fi

  mkdir -p "$log_dir"
  chown konghai:staff "$log_dir"
  cat > "$source_plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>${label}</string>
  <key>ProgramArguments</key><array><string>${runner_root}/runsvc.sh</string></array>
  <key>UserName</key><string>konghai</string>
  <key>GroupName</key><string>staff</string>
  <key>WorkingDirectory</key><string>${runner_root}</string>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>SessionCreate</key><true/>
  <key>StandardOutPath</key><string>${log_dir}/stdout.log</string>
  <key>StandardErrorPath</key><string>${log_dir}/stderr.log</string>
  <key>EnvironmentVariables</key><dict>
    <key>ACTIONS_RUNNER_SVC</key><string>1</string>
    <key>HOME</key><string>/Users/konghai</string>
    <key>LANG</key><string>en_US.UTF-8</string>
    <key>LC_ALL</key><string>en_US.UTF-8</string>
    <key>PATH</key><string>/opt/homebrew/opt/node@22/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict></plist>
EOF
  chown konghai:staff "$source_plist"
  plutil -lint "$source_plist"
  install -o root -g wheel -m 644 "$source_plist" "$plist"
  launchctl enable "system/${label}"
  launchctl bootstrap system "$plist"
  printf '%s\n' "$plist" > "${runner_root}/.service"
  chown konghai:staff "${runner_root}/.service"
  launchctl print "system/${label}" | grep -E 'state =|pid =|path ='
  echo "已安装：system/${label}"
}

for slot in "${slots[@]}"; do
  install_slot "$slot"
done
