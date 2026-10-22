#!/bin/bash
# 在 mac-mini 上以 hon 身份常驻的团队服务（LaunchDaemon，UserName=hon，注销后仍运行）：
#   com.cypressoai.colima-team          colima profile team（替代 konghai 的 com.konghai.colima）
#   com.cypressoai.sonarqube-backup     每天 03:30
#   com.cypressoai.acquilang-backup     每天 04:00
#   com.cypressoai.acquilang-prod-sync  0/6/12/18 点；装好但保持 disabled，nyh-prod 受限密钥落地后再 enable
#
# 用法（root）：
#   sudo hon-team-services.sh --colima      # 只装 colima team 守护（先由 hon 手动建好 team profile）
#   sudo hon-team-services.sh --jobs        # 装三个定时任务
#   sudo hon-team-services.sh --enable-sync # 受限密钥就绪后启用同步
#
# 所有任务显式设置 DOCKER_HOST 指向 team：hon 下还有 moo / multica，docker 当前 context 会漂移。
set -euo pipefail

[[ $(id -u) -eq 0 ]] || { echo "must run as root" >&2; exit 1; }

H_HOME=/Users/hon
LOG_ROOT=$H_HOME/Library/Logs
PATH_VALUE=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
TEAM_SOCK=unix://$H_HOME/.colima/team/docker.sock
SYNC_LABEL=com.cypressoai.acquilang-prod-sync

# 从 stdin 写 plist；第二个参数为 disabled 时只装不启
install_daemon() {
  local label=$1 mode=${2:-enabled}
  local plist=/Library/LaunchDaemons/$label.plist
  cat >"$plist"
  chown root:wheel "$plist"
  chmod 644 "$plist"
  plutil -lint "$plist" >/dev/null
  launchctl bootout "system/$label" 2>/dev/null || true
  if [[ $mode == disabled ]]; then
    launchctl disable "system/$label"
    echo "installed system/$label (disabled)"
    return
  fi
  # 先 enable：disabled 的服务 bootstrap 会报 5: Input/output error
  launchctl enable "system/$label"
  launchctl bootstrap system "$plist"
  echo "installed system/$label"
}

# 公共的 plist 头：UserName=hon、HOME、PATH、DOCKER_HOST
plist_head() {
  cat <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$1</string>
  <key>UserName</key><string>hon</string>
  <key>GroupName</key><string>staff</string>
  <key>WorkingDirectory</key><string>$H_HOME</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>$H_HOME</string>
    <key>PATH</key><string>$PATH_VALUE</string>
    <key>DOCKER_HOST</key><string>$TEAM_SOCK</string>
  </dict>
EOF
}

install_colima() {
  [[ -f $H_HOME/.colima/team/colima.yaml ]] || { echo "缺少 team profile，先以 hon 建好" >&2; exit 1; }
  {
    plist_head com.cypressoai.colima-team
    cat <<EOF
  <key>ProgramArguments</key>
  <array>
    <string>/opt/homebrew/bin/colima</string>
    <string>start</string>
    <string>--profile</string>
    <string>team</string>
    <string>--foreground</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$LOG_ROOT/colima-team.stdout.log</string>
  <key>StandardErrorPath</key><string>$LOG_ROOT/colima-team.stderr.log</string>
</dict>
</plist>
EOF
  } | install_daemon com.cypressoai.colima-team
}

# label、脚本、日志名、StartCalendarInterval 片段、启用状态
install_job() {
  local label=$1 program=$2 log_name=$3 calendar=$4 mode=${5:-enabled}
  {
    plist_head "$label"
    cat <<EOF
  <key>ProgramArguments</key>
  <array><string>$program</string></array>
  <key>StartCalendarInterval</key>
$calendar
  <key>StandardOutPath</key><string>$LOG_ROOT/$log_name.log</string>
  <key>StandardErrorPath</key><string>$LOG_ROOT/$log_name.log</string>
</dict>
</plist>
EOF
  } | install_daemon "$label" "$mode"
}

install_jobs() {
  install_job com.cypressoai.sonarqube-backup "$H_HOME/stacks/sonarqube/backup.sh" sonarqube-backup \
    '  <dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>30</integer></dict>'
  install_job com.cypressoai.acquilang-backup "$H_HOME/scripts/acquilangai-backup.sh" acquilangai-backup \
    '  <dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>0</integer></dict>'
  local hour sync_calendar='  <array>'
  for hour in 0 6 12 18; do
    sync_calendar+="<dict><key>Hour</key><integer>$hour</integer><key>Minute</key><integer>0</integer></dict>"
  done
  sync_calendar+='</array>'
  install_job "$SYNC_LABEL" "$H_HOME/stacks/acquilang-postgres/sync-from-prod.sh" acquilang-prod-sync \
    "$sync_calendar" disabled
}

case "${1:-}" in
  --colima) install_colima ;;
  --jobs) install_jobs ;;
  --enable-sync)
    launchctl enable "system/$SYNC_LABEL"
    launchctl bootstrap system "/Library/LaunchDaemons/$SYNC_LABEL.plist"
    echo "enabled system/$SYNC_LABEL"
    ;;
  *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
