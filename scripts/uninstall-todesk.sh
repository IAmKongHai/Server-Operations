#!/usr/bin/env bash
# 彻底卸载优趣 ToDesk（com.youqu.todesk / ToDesk.app）。
# 不会碰 ToDesktop（Cursor / Notion Calendar 用的 com.todesktop.*）。
#
# 用法：
#   sudo ./uninstall-todesk.sh --apply # 推荐：终端里直接 sudo
#   ./uninstall-todesk.sh --dry-run    # 只扫描，不改任何东西
#   ./uninstall-todesk.sh              # 先扫描；终端里会再要一次 sudo
#
# 不要依赖「图形密码框」。从「下载」目录走 osascript 提权时，
# macOS TCC 常在密码通过后仍拒绝执行，看起来像密码错了。
set -euo pipefail

MODE=auto
LOG=/tmp/uninstall-todesk.log

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

# 只匹配优趣 ToDesk，避开 ToDesktop。
is_todesk_process() {
  case "$1" in
    *'/ToDesk.app/'*|*/ToDesk_Service*|*/ToDesk_Session_Proxy*|*/ToDesk\ -*|*'com.youqu.todesk'*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

list_human_uids() {
  dscl . -list /Users UniqueID 2>/dev/null | awk '$2 >= 500 { print $2 }'
}

home_for_uid() {
  local uid="$1" name
  name=$(dscl . -search /Users UniqueID "$uid" 2>/dev/null | awk 'NR==1 { print $1 }')
  [ -n "$name" ] || return 1
  dscl . -read "/Users/$name" NFSHomeDirectory 2>/dev/null | awk '{ print $2 }'
}

collect_paths() {
  cat <<'EOF'
/Applications/ToDesk.app
/Library/LaunchAgents/com.youqu.todesk.startup.plist
/Library/LaunchAgents/com.youqu.todesk.session.plist
/Library/LaunchDaemons/com.youqu.todesk.service.plist
/Library/LaunchDaemons/com.youqu.todesk.UninstallerHelper.plist
/Library/LaunchDaemons/com.youqu.todesk.UninstallerWatcher.plist
/Library/PrivilegedHelperTools/com.youqu.todesk.UninstallerHelper
/Library/Audio/Plug-Ins/HAL/ToDeskOutputDriver.driver
/Library/Application Support/ToDesk
/Library/Logs/ToDesk
EOF
  local uid home
  for uid in $(list_human_uids); do
    home=$(home_for_uid "$uid" || true)
    [ -n "${home:-}" ] || continue
    cat <<EOF
$home/Library/Application Support/ToDesk
$home/Library/Application Support/com.youqu.todesk.mac
$home/Library/Logs/ToDesk
$home/Library/Caches/com.youqu.todesk.mac
$home/Library/HTTPStorages/com.youqu.todesk.mac
$home/Library/Preferences/com.youqu.todesk.mac.plist
$home/Library/Preferences/com.youqu.todesk.plist
$home/Library/Saved Application State/com.youqu.todesk.mac.savedState
$home/Library/WebKit/com.youqu.todesk.mac
$home/Library/LaunchAgents/com.youqu.todesk.startup.plist
$home/Library/LaunchAgents/com.youqu.todesk.session.plist
$home/.Trash/ToDesk.app
$home/.Trash/ToDesk_2026-08-14_22-44-45
EOF
    # 废纸篓里其它 ToDesk_日期 目录；找不到就忽略。
    if [ -d "$home/.Trash" ]; then
      find "$home/.Trash" -maxdepth 1 \( -name 'ToDesk.app' -o -name 'ToDesk_*' \) -print 2>/dev/null || true
    fi
  done
}

existing_paths() {
  local p
  collect_paths | awk 'NF && !seen[$0]++' | while IFS= read -r p; do
    if [ -e "$p" ] || [ -L "$p" ]; then
      printf '%s\n' "$p"
    fi
  done
}

scan() {
  log "=== 扫描 $(hostname) / $(sw_vers -productVersion) / user=$(id -un) ==="
  log "-- 进程 --"
  local found=0
  # ps 的 comm 可能被截断，用完整 command。
  ps -axo pid=,user=,etime=,command= | while IFS= read -r line; do
    if is_todesk_process "$line"; then
      log "  $line"
      found=1
    fi
  done
  [ "$found" -eq 1 ] 2>/dev/null || true

  log "-- launchd system --"
  launchctl print system 2>/dev/null | grep -iE 'todesk|youqu' || log "  (无)"

  local uid
  for uid in $(list_human_uids); do
    if launchctl print "gui/$uid" 2>/dev/null | grep -qiE 'todesk|youqu'; then
      log "-- launchd gui/$uid --"
      launchctl print "gui/$uid" 2>/dev/null | grep -iE 'todesk|youqu' || true
    fi
  done

  log "-- 文件 --"
  local paths
  paths=$(existing_paths || true)
  if [ -z "$paths" ]; then
    log "  (无已知残留文件)"
  else
    printf '%s\n' "$paths" | while IFS= read -r p; do
      log "  $p"
    done
  fi

  log "-- pkgutil --"
  pkgutil --pkgs 2>/dev/null | grep -iE 'youqu\.todesk|^com\.youqu\.todesk' || log "  (无)"

  log "-- 音频设备名含 ToDesk --"
  if system_profiler SPAudioDataType 2>/dev/null | grep -q 'ToDesk'; then
    system_profiler SPAudioDataType 2>/dev/null | grep -A4 -E 'ToDesk|Default Output'
  else
    log "  (当前设备列表无 ToDesk)"
  fi
}

bootout_label() {
  local target="$1"
  if launchctl bootout "$target" >/dev/null 2>&1; then
    log "bootout ok  $target"
  else
    log "bootout skip $target"
  fi
}

disable_label() {
  local target="$1"
  if launchctl disable "$target" >/dev/null 2>&1; then
    log "disable ok  $target"
  else
    log "disable skip $target"
  fi
}

scrub_audio_plist() {
  local plist=/Library/Preferences/Audio/com.apple.audio.SystemSettings.plist
  local bak=/Library/Preferences/Audio/com.apple.audio.SystemSettings.plist.bak.$(date +%Y%m%d)
  if [ ! -f "$plist" ]; then
    log "音频配置不存在，跳过"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    log "没有 python3，跳过音频配置清理"
    return 0
  fi
  cp -p "$plist" "$bak"
  log "音频配置已备份 $bak"
  python3 - <<'PY'
import plistlib
from pathlib import Path
p = Path("/Library/Preferences/Audio/com.apple.audio.SystemSettings.plist")
data = plistlib.loads(p.read_bytes())
removed = []
for k in list(data):
    if "ToDesk" in k or "TD_MULTIPLE_OUTPUT" in k:
        del data[k]
        removed.append(k)
uid_list = data.get("Meta_UIDList")
if isinstance(uid_list, list):
    new_list = [u for u in uid_list if "ToDesk" not in str(u) and u != "TD_MULTIPLE_OUTPUT_UID"]
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
            if not (
                isinstance(it, dict)
                and (
                    it.get("uid") == "TD_MULTIPLE_OUTPUT_UID"
                    or "ToDesk" in str(it.get("uid", ""))
                )
            )
        ]
        if new_items != items:
            prefs[bucket] = new_items
            removed.append(f"preferred devices.{bucket}")
p.write_bytes(plistlib.dumps(data, fmt=plistlib.FMT_BINARY))
print("audio keys removed:", ", ".join(removed) if removed else "(none)")
PY
  chown _coreaudiod:_coreaudiod "$plist" 2>/dev/null || true
  chmod 664 "$plist" 2>/dev/null || true
}

apply() {
  if ! is_root; then
    log "错误：--apply 需要 root"
    exit 1
  fi
  log "=== 开始卸载 $(ts) uid=0 ==="

  # 先停 UninstallerWatcher，避免删 App 时被它拉回来。
  bootout_label system/com.youqu.todesk.UninstallerWatcher
  bootout_label system/com.youqu.todesk.UninstallerHelper
  bootout_label system/com.youqu.todesk.service

  local uid
  for uid in $(list_human_uids); do
    bootout_label "gui/$uid/com.youqu.todesk.desktop"
    bootout_label "gui/$uid/com.youqu.todesk.client.startup"
  done

  local f
  for f in \
    /Library/LaunchDaemons/com.youqu.todesk.service.plist \
    /Library/LaunchDaemons/com.youqu.todesk.UninstallerHelper.plist \
    /Library/LaunchDaemons/com.youqu.todesk.UninstallerWatcher.plist \
    /Library/LaunchAgents/com.youqu.todesk.startup.plist \
    /Library/LaunchAgents/com.youqu.todesk.session.plist
  do
    if [ -f "$f" ]; then
      launchctl unload -w "$f" >/dev/null 2>&1 || true
      log "unload $f"
    fi
  done

  pkill -TERM -f '/ToDesk_Service' 2>/dev/null || true
  pkill -TERM -f '/ToDesk_Session_Proxy' 2>/dev/null || true
  pkill -TERM -f '/ToDesk.app/' 2>/dev/null || true
  pkill -TERM -f 'com.youqu.todesk' 2>/dev/null || true
  sleep 0.5
  pkill -KILL -f '/ToDesk_Service' 2>/dev/null || true
  pkill -KILL -f '/ToDesk_Session_Proxy' 2>/dev/null || true
  pkill -KILL -f '/ToDesk.app/' 2>/dev/null || true
  pkill -KILL -f 'com.youqu.todesk' 2>/dev/null || true

  local p
  existing_paths | while IFS= read -r p; do
    rm -rf "$p"
    log "removed $p"
  done

  pkgutil --forget com.youqu.todesk.UninstallerClient >/dev/null 2>&1 && log "forget com.youqu.todesk.UninstallerClient" || true
  pkgutil --forget com.youqu.todesk.UninstallerHelper >/dev/null 2>&1 && log "forget com.youqu.todesk.UninstallerHelper" || true
  pkgutil --forget com.youqu.todesk.mac >/dev/null 2>&1 && log "forget com.youqu.todesk.mac" || true

  disable_label system/com.youqu.todesk.service
  disable_label system/com.youqu.todesk.UninstallerWatcher
  disable_label system/com.youqu.todesk.UninstallerHelper
  for uid in $(list_human_uids); do
    disable_label "gui/$uid/com.youqu.todesk.desktop"
    disable_label "gui/$uid/com.youqu.todesk.client.startup"
  done

  scrub_audio_plist
  killall coreaudiod >/dev/null 2>&1 && log "restarted coreaudiod" || true
  sleep 1

  log "=== 卸载后复查 ==="
  scan
  log "=== 完成。日志 $LOG ==="
}

elevate_and_apply() {
  local self staged err
  self=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  if [ ! -f "$self" ]; then
    echo "找不到脚本自身: $self" >&2
    exit 1
  fi

  # 终端里用 sudo。图形密码框对「下载」目录经常密码对了也不让执行。
  if [ -t 0 ]; then
    echo "需要管理员权限。请在终端里输入登录密码（不会用图形密码框）："
    exec sudo /bin/bash "$self" --apply
  fi

  staged=/tmp/uninstall-todesk.sh
  cp "$self" "$staged"
  chmod 700 "$staged"
  xattr -c "$staged" 2>/dev/null || true
  echo "无终端，尝试图形密码框（执行 /tmp 副本以避免「下载」目录权限）…"
  err=$(mktemp /tmp/uninstall-todesk-osascript.XXXXXX)
  if osascript -e "do shell script \"/bin/bash /tmp/uninstall-todesk.sh --apply\" with administrator privileges" 2>"$err"; then
    rm -f "$err"
    return 0
  fi
  echo "图形提权失败。系统返回："
  cat "$err" 2>/dev/null || true
  rm -f "$err"
  echo
  echo "请打开「终端」执行："
  echo "  sudo /bin/bash /tmp/uninstall-todesk.sh --apply"
  exit 1
}

: >>"$LOG" || true
echo "======== $(ts) mode=$MODE ========" >>"$LOG"

scan

case "$MODE" in
  dry-run)
    log "dry-run：未做任何修改。"
    ;;
  apply)
    apply
    ;;
  auto)
    if is_root; then
      apply
    else
      elevate_and_apply
    fi
    ;;
esac
