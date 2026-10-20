#!/bin/bash
# 在 mac-mini 上安装 fseventsd 看门狗 LaunchDaemon（每 5 分钟跑一次）。
# sudo /Users/konghai/gha/scripts/install-mac-mini-fseventsd-watchdog.sh
# 重复执行会覆盖脚本和 plist 并重新加载，不影响其它服务。
# 卸载：
#   sudo launchctl bootout system/com.konghai.fseventsd-watchdog
#   sudo rm /Library/LaunchDaemons/com.konghai.fseventsd-watchdog.plist /usr/local/sbin/fseventsd-watchdog.sh
set -euo pipefail

if [[ $(id -u) -ne 0 ]]; then
  echo "请使用 sudo 运行：$0" >&2
  exit 1
fi

label=com.konghai.fseventsd-watchdog
plist=/Library/LaunchDaemons/${label}.plist
source_script="$(cd "$(dirname "$0")" && pwd)/mac-mini-fseventsd-watchdog.sh"
target_script=/usr/local/sbin/fseventsd-watchdog.sh
log_dir=/var/log/fseventsd-watchdog

if [[ ! -f $source_script ]]; then
  echo "找不到 ${source_script}" >&2
  exit 1
fi

install -m 755 -o root -g wheel "$source_script" "$target_script"
mkdir -p "$log_dir"
chmod 755 "$log_dir"

cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${target_script}</string>
  </array>
  <key>StartInterval</key>
  <integer>300</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>${log_dir}/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>${log_dir}/launchd.err.log</string>
</dict>
</plist>
EOF
chown root:wheel "$plist"
chmod 644 "$plist"

launchctl bootout "system/${label}" 2>/dev/null || true
launchctl bootstrap system "$plist"
sleep 3
launchctl print "system/${label}" | grep -E 'state|last exit code' || true
tail -3 "${log_dir}/watchdog.log" 2>/dev/null || true
