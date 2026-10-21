#!/bin/bash
# lemon-imac：开机自动把 CIWork 卷挂到 /Users/for-konghai/gha，并让 runner 只在卷挂好之后启动。
#
# 为什么不用 /etc/fstab：写 /etc/fstab 需要 TCC 的 kTCCServiceSystemPolicySysAdminFiles。
# SSH 会话（责任进程 sshd-keygen-wrapper）和 launchd 拉起的 /bin/bash 都没有这项权限，
# 2026-10-21 两种方式都被拒；屏幕共享又登不进去，没法在图形界面里授权。
#
# 做法：
#   1. LaunchDaemon com.konghai.ciwork-mount（RunAtLoad + 每 5 分钟）跑 /usr/local/sbin/ciwork-mount.sh：
#      卷没挂在 ~/gha 就卸下（开机时系统会把它自动挂到 /Volumes/CIWork）再挂到 ~/gha
#   2. 卷根目录放标记文件 .ciwork-mounted，只有卷挂在 ~/gha 时 ~/gha/.ciwork-mounted 才存在
#   3. 3 个 runner plist 去掉 RunAtLoad，KeepAlive 改为 PathState 盯标记文件：卷没挂好 runner 不启动
#      （lemon-imac-1/2 由 install-lemon-imac-runner-daemons.sh 重写，这里只改 acquilang 那份）
#
#   sudo /Users/for-konghai/gha/scripts/install-lemon-imac-ciwork-automount.sh
# 回滚：
#   sudo launchctl bootout system/com.konghai.ciwork-mount
#   sudo rm /Library/LaunchDaemons/com.konghai.ciwork-mount.plist /usr/local/sbin/ciwork-mount.sh
#   acquilang plist 用 *.bak-automount-<日期> 还原；lemon-imac-1/2 用旧版安装器重装
set -euo pipefail

[[ $(id -u) -eq 0 ]] || { echo "请用 sudo 运行" >&2; exit 1; }

TARGET_DIR=/Users/for-konghai/gha
MARKER=$TARGET_DIR/.ciwork-mounted
VOLUME_NAME=CIWork
LABEL=com.konghai.ciwork-mount
PLIST=/Library/LaunchDaemons/$LABEL.plist
MOUNT_SCRIPT=/usr/local/sbin/ciwork-mount.sh
STAMP=$(date +%Y%m%d)
ACQ_LABEL=actions.runner.IAmKongHai-AcquiLangAI.lemon-imac-acquilang-ci-1
ACQ_PLISTS=(
  "/Library/LaunchDaemons/$ACQ_LABEL.plist"
  "/Users/for-konghai/actions-runner/lemon-imac-acquilang-ci-1/$ACQ_LABEL.plist"
)

mp=$(diskutil info "$VOLUME_NAME" | awk -F': *' '/Mount Point/{print $2}')
[[ $mp == "$TARGET_DIR" ]] || { echo "${VOLUME_NAME} 应挂在 ${TARGET_DIR}（当前 ${mp}）" >&2; exit 1; }

# 标记文件写在卷上
touch "$MARKER"
chown root:wheel "$MARKER"
chmod 644 "$MARKER"
echo "marker: $(ls -l "$MARKER")"

mkdir -p /usr/local/sbin
cat >"$MOUNT_SCRIPT" <<'EOF'
#!/bin/bash
# 把 CIWork 卷挂到 /Users/for-konghai/gha（由 com.konghai.ciwork-mount 开机及每 5 分钟调用，幂等）
TARGET_DIR=/Users/for-konghai/gha
VOLUME_NAME=CIWork
LOG=/var/log/ciwork-mount.log

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }
mount_point() { diskutil info "$VOLUME_NAME" 2>/dev/null | awk -F': *' '/Mount Point/{print $2}'; }

# 开机早期 diskarbitrationd 可能还没准备好，最多等 2 分钟
for _ in $(seq 1 60); do
  diskutil info "$VOLUME_NAME" >/dev/null 2>&1 && break
  sleep 2
done
mp=$(mount_point)
[[ $mp == "$TARGET_DIR" ]] && exit 0

log "CIWork 当前挂载点：${mp:-<none>}，挂到 $TARGET_DIR"
if [[ -n $mp && $mp != "Not applicable"* ]]; then
  diskutil unmount "$mp" >>"$LOG" 2>&1 || { log "ERROR: 卸载 $mp 失败"; exit 1; }
fi
if [[ ! -d $TARGET_DIR ]]; then
  mkdir "$TARGET_DIR"
  chown root:wheel "$TARGET_DIR"
  chmod 755 "$TARGET_DIR"
fi
if diskutil mount -mountPoint "$TARGET_DIR" "$VOLUME_NAME" >>"$LOG" 2>&1 && [[ $(mount_point) == "$TARGET_DIR" ]]; then
  log "已挂载；marker $([[ -f $TARGET_DIR/.ciwork-mounted ]] && echo 存在 || echo 缺失)"
else
  log "ERROR: 挂载到 $TARGET_DIR 失败"
  exit 1
fi
EOF
chown root:wheel "$MOUNT_SCRIPT"
chmod 755 "$MOUNT_SCRIPT"

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
    <string>$MOUNT_SCRIPT</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>300</integer>
  <key>StandardErrorPath</key>
  <string>/var/log/ciwork-mount.err.log</string>
</dict>
</plist>
EOF
chown root:wheel "$PLIST"
chmod 644 "$PLIST"
plutil -lint "$PLIST" >/dev/null
launchctl bootout "system/$LABEL" 2>/dev/null || true
launchctl bootstrap system "$PLIST"
echo "installed system/$LABEL"

# acquilang runner：去掉 RunAtLoad，KeepAlive 改为盯标记文件（系统那份和 runner 目录里的源文件都改）
for plist in "${ACQ_PLISTS[@]}"; do
  [[ -f $plist ]] || continue
  [[ -f $plist.bak-automount-$STAMP ]] || cp -p "$plist" "$plist.bak-automount-$STAMP"
  /usr/libexec/PlistBuddy \
    -c "Set :RunAtLoad false" \
    -c "Delete :KeepAlive" \
    -c "Add :KeepAlive dict" \
    -c "Add :KeepAlive:PathState dict" \
    -c "Add :KeepAlive:PathState:$MARKER bool true" \
    "$plist"
  plutil -lint "$plist" >/dev/null
  echo "patched $plist"
done
# 只改文件；它现在是 disabled + 未加载，--finish 会 enable 并 bootstrap

sleep 2
echo "--- $LABEL"
launchctl print "system/$LABEL" | grep -E 'state =|last exit code' || true
echo "--- acquilang KeepAlive"
plutil -p "${ACQ_PLISTS[0]}" | grep -A4 -E 'RunAtLoad|KeepAlive'
echo "--- /var/log/ciwork-mount.log"
tail -5 /var/log/ciwork-mount.log 2>/dev/null || echo "(空：卷已在目标位置，无需动作)"
