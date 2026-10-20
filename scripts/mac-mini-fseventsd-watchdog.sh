#!/bin/bash
# mac-mini fseventsd 看门狗：由 LaunchDaemon 每 5 分钟以 root 跑一次。
# 1. 每次记一行 fseventsd 的内存占用（footprint）、RSS、CPU、swap、load
# 2. 占用超过 CAPTURE_MB：抓现场（进程快照、lsof、sample、15 秒 fs_usage），每小时最多一次
# 3. 占用超过 KILL_MB：先抓现场，再 killall fseventsd，由 launchd 自动拉起
#
# 日志：/var/log/fseventsd-watchdog/watchdog.log
# 现场：/var/log/fseventsd-watchdog/captures/<时间>/，保留 30 天
# 安装：sudo scripts/install-mac-mini-fseventsd-watchdog.sh
set -uo pipefail

CAPTURE_MB=${CAPTURE_MB:-1024}
KILL_MB=${KILL_MB:-4096}
CAPTURE_COOLDOWN_SEC=3600
LOG_DIR=/var/log/fseventsd-watchdog
LOG_FILE=$LOG_DIR/watchdog.log
CAPTURE_ROOT=$LOG_DIR/captures
LAST_CAPTURE_FILE=$LOG_DIR/.last_capture

mkdir -p "$CAPTURE_ROOT"
chmod 755 "$LOG_DIR" "$CAPTURE_ROOT"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG_FILE"
}

# top 的 MEM 列（物理 footprint，含压缩/换出）形如 32G+、850M、12K，统一换算成 MB
footprint_mb() {
  local pid="$1" raw
  raw=$(top -l 1 -pid "$pid" -stats mem 2>/dev/null | tail -1 | tr -d '+-')
  awk -v v="$raw" 'BEGIN {
    n = v + 0; u = substr(v, length(v), 1)
    if (u == "G") n *= 1024; else if (u == "K") n /= 1024; else if (u == "B") n /= 1048576
    printf "%d", n
  }'
}

# 抓现场：哪些进程在跑、fseventsd 打开了什么、它在忙什么、谁在大量改文件
capture() {
  local pid="$1" reason="$2" dir
  dir=$CAPTURE_ROOT/$(date '+%Y%m%d-%H%M%S')
  mkdir -p "$dir"
  {
    echo "reason: $reason"
    uptime
    sysctl vm.swapusage
    memory_pressure | tail -1
  } >"$dir/summary.txt" 2>&1
  ps -axo pid,user,etime,%cpu,rss,command -r | head -40 | cut -c1-250 >"$dir/ps.txt" 2>&1
  lsof -n -p "$pid" >"$dir/lsof-fseventsd.txt" 2>&1
  sample "$pid" 5 -file "$dir/sample-fseventsd.txt" >/dev/null 2>&1
  fs_usage -w -f filesys -t 15 >"$dir/fs_usage.txt" 2>/dev/null
  # 按进程统计会改动文件系统的操作，方便一眼看出谁在制造事件
  grep -E 'WrData|unlink|rename|mkdir|rmdir|truncate|clonefile|\(.W' "$dir/fs_usage.txt" \
    | awk '{print $NF}' | sed -E 's/\.[0-9]+$//' | sort | uniq -c | sort -rn | head -30 >"$dir/writers-by-process.txt"
  gzip -f "$dir/fs_usage.txt"
  chmod -R a+rX "$dir"
  date +%s >"$LAST_CAPTURE_FILE"
  log "capture pid=$pid reason=\"$reason\" dir=$dir"
}

capture_allowed() {
  local last=0
  [[ -f $LAST_CAPTURE_FILE ]] && last=$(cat "$LAST_CAPTURE_FILE")
  (($(date +%s) - last >= CAPTURE_COOLDOWN_SEC))
}

# 日志超过 5MB 轮转一份；现场目录保留 30 天
rotate() {
  if [[ -f $LOG_FILE ]] && (($(stat -f %z "$LOG_FILE") > 5242880)); then
    mv -f "$LOG_FILE" "$LOG_FILE.1"
  fi
  find "$CAPTURE_ROOT" -mindepth 1 -maxdepth 1 -type d -mtime +30 -exec rm -rf {} + 2>/dev/null
}

main() {
  rotate
  local pid
  pid=$(pgrep -x fseventsd | head -1)
  if [[ -z $pid ]]; then
    log "fseventsd not running"
    return
  fi

  local mem_mb rss_mb cpu etime swap_used load1
  mem_mb=$(footprint_mb "$pid")
  rss_mb=$(($(ps -o rss= -p "$pid") / 1024))
  cpu=$(ps -o %cpu= -p "$pid" | tr -d ' ')
  etime=$(ps -o etime= -p "$pid" | tr -d ' ')
  swap_used=$(sysctl -n vm.swapusage | awk '{print $6}')
  load1=$(sysctl -n vm.loadavg | awk '{print $2}')
  log "pid=$pid etime=$etime mem_mb=$mem_mb rss_mb=$rss_mb cpu=$cpu swap_used=$swap_used load1=$load1"

  if ((mem_mb >= KILL_MB)); then
    capture_allowed && capture "$pid" "mem_mb=$mem_mb >= KILL_MB=$KILL_MB"
    killall fseventsd
    sleep 5
    log "killed fseventsd pid=$pid mem_mb=$mem_mb; new pid=$(pgrep -x fseventsd | head -1)"
  elif ((mem_mb >= CAPTURE_MB)) && capture_allowed; then
    capture "$pid" "mem_mb=$mem_mb >= CAPTURE_MB=$CAPTURE_MB"
  fi
  chmod 644 "$LOG_FILE"
}

main
