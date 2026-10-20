#!/bin/bash
# 把 mac-mini 的 CI 目录迁到独立 APFS 卷 CIWork（.fseventsd/no_log，关闭 Spotlight），
# 让 fseventsd 不再为 CI 的海量文件改动写事件日志（2026-10-20 实测省约 28% fseventsd CPU）。
#
# 卷直接挂到 /Users/konghai/gha（不用符号链接：符号链接会让进程实际目录和 GITHUB_WORKSPACE
# 不一致，Vitest LCOV 路径对不上 Sonar）。挂载点底下的原目录改成 root 所有，
# 卷没挂上时 runner 写入会直接 Permission denied，不会悄悄写回系统数据卷。
#
# 用法（root）：
#   sudo migrate-mac-mini-ci-to-nofsevents-volume.sh --prepare   # 建卷、no_log、关 Spotlight；不影响 CI
#   sudo migrate-mac-mini-ci-to-nofsevents-volume.sh --migrate   # 逐个等 runner 空闲后停掉，复制、挂载、改 GOCACHE、拉起
#   sudo migrate-mac-mini-ci-to-nofsevents-volume.sh --status
#   sudo migrate-mac-mini-ci-to-nofsevents-volume.sh --start-runners  # 出错中断后手动拉起所有 runner
#
# 注意：macOS /bin/bash 是 3.2，变量后紧跟中文全角字符会被当成变量名，一律写成 ${VAR}。
#
# 回滚：见 docs/operations/mac-mini.md 对应条目（停 runner → 卸载 CIWork → 删 fstab 行 →
#       还原 gha.pre-ciwork-* 和各 .env.bak-ciwork → 拉起 runner）。
set -euo pipefail

VOLUME_NAME=CIWork
APFS_CONTAINER=disk3
VOLUME_QUOTA=300g
TEMP_MOUNT=/Volumes/$VOLUME_NAME
TARGET_DIR=/Users/konghai/gha
RUNNER_ROOT=/Users/konghai/actions-runner
STAMP=$(date +%Y%m%d)
BACKUP_DIR=$TARGET_DIR.pre-ciwork-$STAMP
LOG=/var/log/ciwork-migrate.log
SONAR_SLOTS=(1 2 3 4)
# 当前 loaded 的 runner LaunchDaemon（acquilang-ci-4/5 是 disabled，不碰）
DAEMON_LABELS=(
  actions.runner.cypressoai.mac-mini-sonar-1
  actions.runner.cypressoai.mac-mini-sonar-2
  actions.runner.cypressoai.mac-mini-sonar-3
  actions.runner.cypressoai.mac-mini-sonar-4
  actions.runner.cypressoai.mac-mini-mobile-1
  actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-1
  actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-2
  actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-3
  actions.runner.konghai-friends-lab-AcquiLangAI.mac-mini-acquilang-native-1
)
# konghai-friends-lab-1 不是 launchd 任务，是 nohup ./runsvc.sh
NOHUP_RUNNER=konghai-friends-lab-1
DRAIN_TIMEOUT_SEC=5400

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
die() { log "ERROR: $*"; exit 1; }

[[ $(id -u) -eq 0 ]] || { echo "请用 sudo 运行" >&2; exit 1; }

volume_exists() { diskutil info "$VOLUME_NAME" >/dev/null 2>&1; }
volume_uuid() { diskutil info "$VOLUME_NAME" | awk -F: '/Volume UUID/{gsub(/ /,"",$2); print $2}'; }
volume_mountpoint() { diskutil info "$VOLUME_NAME" | awk -F': *' '/Mount Point/{print $2}'; }

# slot 目录名 → 该 runner 当前是否在跑 job（Runner.Worker 是 Listener 拉起的子进程）
runner_busy() { pgrep -f "$RUNNER_ROOT/$1/bin[^ ]*/Runner.Worker" >/dev/null; }
label_slot() { echo "${1##*.}"; }

prepare() {
  if volume_exists; then
    log "卷 $VOLUME_NAME 已存在，跳过创建"
  else
    diskutil apfs addVolume "$APFS_CONTAINER" APFS "$VOLUME_NAME" -quota "$VOLUME_QUOTA" | tee -a "$LOG"
  fi
  local mp
  mp=$(volume_mountpoint)
  [[ -n $mp && $mp != "Not applicable"* ]] || { diskutil mount "$VOLUME_NAME" | tee -a "$LOG"; mp=$(volume_mountpoint); }
  diskutil enableOwnership "$mp" | tee -a "$LOG"
  chown konghai:staff "$mp"
  mkdir -p "$mp/.fseventsd"
  touch "$mp/.fseventsd/no_log" "$mp/.metadata_never_index"
  mdutil -i off "$mp" | tee -a "$LOG" || true
  # no_log 在挂载时读取，重新挂一次
  diskutil unmount "$mp" | tee -a "$LOG"
  diskutil mount "$VOLUME_NAME" | tee -a "$LOG"
  status
}

# 逐个 runner 等空闲再停，避免打断正在跑的 job
drain_and_stop() {
  local pending=("${DAEMON_LABELS[@]}") deadline=$(($(date +%s) + DRAIN_TIMEOUT_SEC))
  local nohup_pending=1
  while ((${#pending[@]} > 0 || nohup_pending)); do
    local still=()
    for label in "${pending[@]+"${pending[@]}"}"; do
      if ! launchctl print "system/$label" >/dev/null 2>&1; then
        log "$label 未加载，跳过"
      elif runner_busy "$(label_slot "$label")"; then
        still+=("$label")
      else
        launchctl bootout "system/$label" && log "已停 $label"
      fi
    done
    pending=("${still[@]+"${still[@]}"}")
    if ((nohup_pending)); then
      if ! pgrep -f "$RUNNER_ROOT/$NOHUP_RUNNER/bin/Runner.Listener" >/dev/null; then
        nohup_pending=0
      elif ! runner_busy "$NOHUP_RUNNER"; then
        # 进程链：bash ./runsvc.sh → node ./bin/RunnerService.js → Runner.Listener；命令行是相对路径，按 PID 往上找
        local listener_pid service_pid runsvc_pid
        listener_pid=$(pgrep -f "$RUNNER_ROOT/$NOHUP_RUNNER/bin/Runner.Listener" | head -1)
        service_pid=$(ps -o ppid= -p "$listener_pid" | tr -d ' ')
        runsvc_pid=$(ps -o ppid= -p "$service_pid" | tr -d ' ')
        kill "$runsvc_pid" "$service_pid" "$listener_pid" 2>/dev/null || true
        nohup_pending=0
        log "已停 ${NOHUP_RUNNER}（nohup）"
      fi
    fi
    if ((${#pending[@]} > 0 || nohup_pending)); then
      (($(date +%s) < deadline)) || die "等待 runner 空闲超时，仍在跑：${pending[*]:-} nohup=${nohup_pending}（已停的 runner 用 --start-runners 拉起）"
      log "等待空闲：${pending[*]:-} $( ((nohup_pending)) && echo $NOHUP_RUNNER)"
      sleep 30
    fi
  done
  sleep 3
  pgrep -f "$RUNNER_ROOT/.*/Runner.Listener" && die "仍有 Runner.Listener 在跑" || log "所有 runner 已停"
}

start_runners() {
  for label in "${DAEMON_LABELS[@]}"; do
    launchctl bootstrap system "/Library/LaunchDaemons/$label.plist" 2>&1 | tee -a "$LOG" || true
  done
  sudo -u konghai -H bash -c "cd '$RUNNER_ROOT/$NOHUP_RUNNER' && nohup ./runsvc.sh >> _diag/nohup-runsvc.log 2>&1 &"
  sleep 15
  log "Runner.Listener 数量：$(pgrep -f "$RUNNER_ROOT/.*/Runner.Listener" | wc -l | tr -d ' ')（期望 10）"
}

migrate() {
  volume_exists || die "先跑 --prepare"
  [[ $(volume_mountpoint) == "$TEMP_MOUNT" ]] || die "${VOLUME_NAME} 应挂在 ${TEMP_MOUNT}（当前 $(volume_mountpoint)）"
  [[ -e $BACKUP_DIR ]] && die "$BACKUP_DIR 已存在，可能迁移过一次"
  [[ -f $TEMP_MOUNT/.fseventsd/no_log ]] || die "缺少 no_log"

  drain_and_stop

  log "复制 ${TARGET_DIR} → ${TEMP_MOUNT}（ditto）"
  ditto "$TARGET_DIR" "$TEMP_MOUNT"
  for n in "${SONAR_SLOTS[@]}"; do
    local src=$RUNNER_ROOT/mac-mini-sonar-$n/cache/go-build
    if [[ -d $src ]]; then
      log "复制 $src → $TEMP_MOUNT/cache/go-build-s$n"
      ditto "$src" "$TEMP_MOUNT/cache/go-build-s$n"
    fi
  done
  chown -R konghai:staff "$TEMP_MOUNT/cache"
  log "复制完成：$(du -sh "$TEMP_MOUNT" | cut -f1)"

  # 原目录留作备份；新建一个 root 所有的空挂载点
  mv "$TARGET_DIR" "$BACKUP_DIR"
  mkdir "$TARGET_DIR"
  chown root:wheel "$TARGET_DIR"
  chmod 755 "$TARGET_DIR"

  diskutil unmount "$TEMP_MOUNT" | tee -a "$LOG"
  diskutil mount -mountPoint "$TARGET_DIR" "$VOLUME_NAME" | tee -a "$LOG"
  [[ $(volume_mountpoint) == "$TARGET_DIR" ]] || die "挂载到 $TARGET_DIR 失败"

  # 开机自动挂到同一路径
  local uuid line
  uuid=$(volume_uuid)
  line="UUID=$uuid $TARGET_DIR apfs rw"
  [[ -f /etc/fstab ]] && cp /etc/fstab "/etc/fstab.bak-ciwork-$STAMP"
  grep -q "$uuid" /etc/fstab 2>/dev/null || echo "$line" >>/etc/fstab
  log "fstab：$line"

  # sonar slot 的 GOCACHE 改到卷上
  for n in "${SONAR_SLOTS[@]}"; do
    local env_file=$RUNNER_ROOT/mac-mini-sonar-$n/.env
    cp -p "$env_file" "$env_file.bak-ciwork-$STAMP"
    sed -i '' "s|^GOCACHE=.*|GOCACHE=$TARGET_DIR/cache/go-build-s$n|" "$env_file"
    log "mac-mini-sonar-$n $(grep '^GOCACHE=' "$env_file")"
  done

  start_runners
  status
  log "完成。确认 CI 正常后，再删除 $BACKUP_DIR 和 $RUNNER_ROOT/mac-mini-sonar-*/cache/go-build"
}

status() {
  echo "--- volume"
  diskutil info "$VOLUME_NAME" 2>/dev/null | grep -E "Volume Name|Mount Point|Volume UUID|Owners|Container Total|Volume Used" || echo "卷不存在"
  local mp
  mp=$(volume_mountpoint 2>/dev/null || true)
  [[ -n $mp && -d $mp/.fseventsd ]] && ls -la "$mp/.fseventsd"
  [[ -n $mp ]] && mdutil -s "$mp" 2>/dev/null | tail -1
  echo "--- fstab"
  grep -i ciwork /etc/fstab 2>/dev/null || grep "$TARGET_DIR" /etc/fstab 2>/dev/null || echo "(无)"
  echo "--- runners"
  pgrep -fl "$RUNNER_ROOT/.*/Runner.Listener" | awk '{print $1, $2}' || echo "(无 Runner.Listener)"
}

case "${1:-}" in
  --prepare) prepare ;;
  --migrate) migrate ;;
  --status) status ;;
  --start-runners) start_runners ;;
  *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
