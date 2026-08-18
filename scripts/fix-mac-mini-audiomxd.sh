#!/usr/bin/env bash
# 修 mac-mini 上 audiomxd 长期高 CPU。
# 1. 备份 /Library/Preferences/Audio
# 2. 删掉仍挂着缺失 BlackHole 的「多输出设备」
# 3. 清 Splashtop 残留虚拟声卡（App 已不在，却是当前默认输入）
# 4. 重启 coreaudiod / audiomxd
#
# 用法：
#   sudo ./fix-mac-mini-audiomxd.sh --apply
#   ./fix-mac-mini-audiomxd.sh --dry-run
#
# 不要从「下载」目录走图形密码框（TCC 会误报成取消）。
# 在本机终端执行：sudo /tmp/fix-mac-mini-audiomxd.sh --apply
set -euo pipefail

MODE=auto
LOG=/tmp/fix-mac-mini-audiomxd.log
STAMP=$(date +%Y%m%d-%H%M%S)
AUDIO_DIR=/Library/Preferences/Audio
SYS_PLIST=$AUDIO_DIR/com.apple.audio.SystemSettings.plist
DEV_PLIST=$AUDIO_DIR/com.apple.audio.DeviceSettings.plist

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run|-n) MODE=dry-run ;;
    --apply) MODE=apply ;;
    --help|-h) usage ;;
    *) echo "未知参数: $1" >&2; usage ;;
  esac
  shift
done

ts() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
  local line="$*"
  printf '%s\n' "$line"
  printf '%s %s\n' "$(ts)" "$line" >>"$LOG" 2>/dev/null || true
}

is_root() { [ "$(id -u)" -eq 0 ]; }

audiomxd_cpu() {
  ps -axo pid=,pcpu=,command= | awk '/\/usr\/libexec\/audiomxd( |$)/ && $0 !~ /awk/ { s += $2 } END { if (s == "") s = 0; printf "%.1f", s }'
}

show_state() {
  log "--- 当前状态 ---"
  log "audiomxd CPU: $(audiomxd_cpu)%"
  ps -axo pid,pcpu,etime,user,command | awk 'BEGIN{IGNORECASE=1} /audiomxd|coreaudiod/ && $0 !~ /awk/ { print }' | while IFS= read -r line; do
    log "  $line"
  done
  if command -v system_profiler >/dev/null 2>&1; then
    system_profiler SPAudioDataType 2>/dev/null | while IFS= read -r line; do
      log "  $line"
    done
  fi
  log "HAL: $(ls /Library/Audio/Plug-Ins/HAL 2>/dev/null | tr '\n' ' ')"
}

scrub_audio_plist() {
  if [ ! -f "$SYS_PLIST" ]; then
    log "音频配置不存在，跳过"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    log "没有 python3，跳过音频配置清理"
    return 1
  fi
  python3 - <<'PY'
import plistlib
from pathlib import Path

p = Path("/Library/Preferences/Audio/com.apple.audio.SystemSettings.plist")
data = plistlib.loads(p.read_bytes())
removed = []
drop_uids = {
    "BlackHole2ch_UID",
    "BlackHole2ch_2_UID",
    "SplashtopRemoteSoundDevice_UID",
    "~:AMS2_StackedOutput:0",
}

for k in list(data):
    ks = str(k)
    if "AMS2_StackedOutput" in ks or "SplashtopRemoteSound" in ks:
        del data[k]
        removed.append(ks)

uid_list = data.get("Meta_UIDList")
if isinstance(uid_list, list):
    new_list = [u for u in uid_list if "AMS2_StackedOutput" not in str(u)]
    if new_list != uid_list:
        data["Meta_UIDList"] = new_list
        removed.append("Meta_UIDList")

prefs = data.get("preferred devices")
if isinstance(prefs, dict):
    for bucket in ("output", "system output", "input"):
        items = prefs.get(bucket)
        if not isinstance(items, list):
            continue
        new_items = [
            it for it in items
            if not (isinstance(it, dict) and it.get("uid") in drop_uids)
        ]
        if new_items != items:
            prefs[bucket] = new_items
            removed.append(f"preferred devices.{bucket}")

p.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
print("audio keys removed:", ", ".join(removed) if removed else "(none)")
PY
  chown _coreaudiod:_coreaudiod "$SYS_PLIST" 2>/dev/null || true
  chmod 664 "$SYS_PLIST" 2>/dev/null || true
}

bootout_label() {
  local domain="$1" label="$2"
  if launchctl bootout "$domain/$label" >/dev/null 2>&1; then
    log "bootout ok  $domain/$label"
  else
    log "bootout skip $domain/$label"
  fi
  if launchctl disable "$domain/$label" >/dev/null 2>&1; then
    log "disable ok  $domain/$label"
  else
    log "disable skip $domain/$label"
  fi
}

list_human_uids() {
  dscl . -list /Users UniqueID 2>/dev/null | awk '$2 >= 500 { print $2 }'
}

apply() {
  if ! is_root; then
    log "错误：--apply 需要 root"
    exit 1
  fi
  log "=== 开始修复 $(ts) uid=0 ==="
  show_state

  mkdir -p "$AUDIO_DIR"
  if [ -f "$SYS_PLIST" ]; then
    cp -p "$SYS_PLIST" "$SYS_PLIST.bak.$STAMP"
    log "已备份 $SYS_PLIST.bak.$STAMP"
  fi
  if [ -f "$DEV_PLIST" ]; then
    cp -p "$DEV_PLIST" "$DEV_PLIST.bak.$STAMP"
    log "已备份 $DEV_PLIST.bak.$STAMP"
  fi

  log "清理 SystemSettings 里的多输出 / Splashtop / BlackHole 首选"
  scrub_audio_plist | while IFS= read -r line; do log "  $line"; done

  bootout_label system com.splashtop.streamer-daemon
  local uid
  for uid in $(list_human_uids); do
    bootout_label "gui/$uid" com.splashtop.streamer
  done

  local f
  for f in \
    /Library/Audio/Plug-Ins/HAL/SplashtopRemoteSound.driver \
    /Library/LaunchDaemons/com.splashtop.streamer-daemon.plist \
    /Library/LaunchAgents/com.splashtop.streamer.plist
  do
    if [ -e "$f" ]; then
      rm -rf "$f"
      log "deleted $f"
    else
      log "absent  $f"
    fi
  done

  log "重启 coreaudiod / audiomxd"
  killall coreaudiod >/dev/null 2>&1 && log "restarted coreaudiod" || log "coreaudiod 当时未在跑"
  killall audiomxd >/dev/null 2>&1 && log "restarted audiomxd" || log "audiomxd 当时未在跑"

  sleep 8
  show_state

  local cpu
  cpu=$(audiomxd_cpu)
  log "修复后 audiomxd CPU=${cpu}%"
  log "=== 结束 $(ts) ==="
}

scan() {
  log "=== 扫描 $(ts) user=$(id -un) uid=$(id -u) ==="
  show_state
  log "Splashtop plist / HAL:"
  ls -la \
    /Library/Audio/Plug-Ins/HAL/SplashtopRemoteSound.driver \
    /Library/LaunchDaemons/com.splashtop.streamer-daemon.plist \
    /Library/LaunchAgents/com.splashtop.streamer.plist \
    2>/dev/null | while IFS= read -r line; do log "  $line"; done || true
  if [ -f "$SYS_PLIST" ]; then
    python3 - <<'PY' | while IFS= read -r line; do log "  $line"; done
import plistlib
from pathlib import Path
p = Path("/Library/Preferences/Audio/com.apple.audio.SystemSettings.plist")
data = plistlib.loads(p.read_bytes())
print("Meta_UIDList:", data.get("Meta_UIDList"))
for k, v in data.items():
    if "AMS2" in str(k) or str(k).startswith("MetaDevice"):
        print(k, "=>", v)
PY
  fi
  log "=== 扫描结束 ==="
}

scan

if [ "$MODE" = dry-run ]; then
  log "dry-run：未改任何东西"
  exit 0
fi

if [ "$MODE" = apply ]; then
  apply
  exit 0
fi

if is_root; then
  apply
  exit 0
fi

log "需要 root。请在本机终端执行："
log "  sudo $0 --apply"
exit 1
