#!/bin/bash
# lemon-imac：通过一次性 LaunchDaemon 把 CIWork 写进 /etc/fstab。
# SSH 会话的 TCC 责任进程是 sshd-keygen-wrapper，没有 kTCCServiceSystemPolicySysAdminFiles，
# 即使 sudo 也写不了 /etc/fstab；改由 launchd 以 root 拉起，责任进程不再是 sshd。
# 同时把 3 个 runner 设为 disabled，重启后不会自动起来（--finish 的 start_runners 会重新 enable）。
#
#   sudo /Users/for-konghai/gha/scripts/lemon-imac-ciwork-fstab-via-launchd.sh
set -euo pipefail

[[ $(id -u) -eq 0 ]] || { echo "请用 sudo 运行" >&2; exit 1; }

TARGET_DIR=/Users/for-konghai/gha
LABEL=com.konghai.ciwork-fstab-once
PLIST=/Library/LaunchDaemons/$LABEL.plist
WORKER=/usr/local/sbin/ciwork-fstab-once.sh
RESULT=/var/log/ciwork-fstab-once.log
RUNNER_LABELS=(
  actions.runner.cypressoai.lemon-imac-1
  actions.runner.cypressoai.lemon-imac-2
  actions.runner.IAmKongHai-AcquiLangAI.lemon-imac-acquilang-ci-1
)

for label in "${RUNNER_LABELS[@]}"; do
  launchctl disable "system/$label"
  echo "disabled system/$label"
done

uuid=$(diskutil info CIWork | awk -F: '/Volume UUID/{gsub(/ /,"",$2); print $2}')
[[ -n $uuid ]] || { echo "找不到 CIWork 卷" >&2; exit 1; }
line="UUID=$uuid $TARGET_DIR apfs rw"

if grep -q "$uuid" /etc/fstab 2>/dev/null; then
  echo "fstab 已有：$line"
else
  mkdir -p /usr/local/sbin
  cat >"$WORKER" <<EOF
#!/bin/bash
{
  date
  [[ -f /etc/fstab ]] && cp -p /etc/fstab /etc/fstab.bak-ciwork-\$(date +%Y%m%d)
  if echo "$line" >>/etc/fstab; then echo OK; else echo FAILED; fi
} >"$RESULT" 2>&1
EOF
  chown root:wheel "$WORKER"
  chmod 755 "$WORKER"
  cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$WORKER</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF
  chown root:wheel "$PLIST"
  chmod 644 "$PLIST"
  rm -f "$RESULT"
  launchctl bootstrap system "$PLIST"
  sleep 5
  launchctl bootout "system/$LABEL" 2>/dev/null || true
  rm -f "$PLIST" "$WORKER"
  echo "--- 一次性任务输出"
  cat "$RESULT" 2>/dev/null || echo "(没有输出)"
fi

echo "--- /etc/fstab"
cat /etc/fstab 2>/dev/null || echo "(不存在)"
echo "--- runner 是否 disabled"
launchctl print-disabled system | grep -E "lemon-imac" || true
