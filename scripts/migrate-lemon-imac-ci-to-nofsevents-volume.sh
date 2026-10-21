#!/bin/bash
# 把 lemon-imac 的 CI 目录迁到独立 APFS 卷 CIWork（.fseventsd/no_log，关闭 Spotlight），
# 让 fseventsd 不再为 CI 的海量文件改动写事件日志（mac-mini 2026-10-20 实测省约 28% fseventsd CPU）。
# 照搬 mac-mini 的 migrate-mac-mini-ci-to-nofsevents-volume.sh，差别：
#   - runner 是 lemon-imac-1/2（cypressoai）和 lemon-imac-acquilang-ci-1，都是 LaunchDaemon，没有 nohup runner
#   - GOCACHE 同时写在 .env、runner plist、维护 plist 里；迁移后重跑 install-lemon-imac-runner-daemons.sh
#     （已改成 ~/gha/cache/go-build-li{1,2}）统一重写 plist，.env 用 sed 改
#   - 不用符号链接：维护脚本的 find / du 不跟进符号链接，GOCACHE 清理会悄悄失效
#
# 卷直接挂到 /Users/for-konghai/gha（不用符号链接：符号链接会让进程实际目录和 GITHUB_WORKSPACE
# 不一致，LCOV 路径对不上 Sonar）。挂载点底下的原目录改成 root 所有，
# 卷没挂上时 runner 写入会直接 Permission denied，不会悄悄写回系统数据卷。
#
# 用法（root）：
#   sudo migrate-lemon-imac-ci-to-nofsevents-volume.sh --prepare   # 建卷、no_log、关 Spotlight；不影响 CI
#   sudo migrate-lemon-imac-ci-to-nofsevents-volume.sh --migrate   # 逐个等 runner 空闲后停掉，复制、挂载、改 GOCACHE、拉起
#   sudo migrate-lemon-imac-ci-to-nofsevents-volume.sh --status
#   sudo migrate-lemon-imac-ci-to-nofsevents-volume.sh --start-runners  # 出错中断后手动拉起所有 runner
#
# 注意：macOS /bin/bash 是 3.2，变量后紧跟中文全角字符会被当成变量名，一律写成 ${VAR}。
#
# 回滚：见 docs/operations/lemon-imac.md 对应条目（停 runner → 卸载 CIWork → 删 fstab 行 →
#       还原 gha.pre-ciwork-*、各 .env.bak-ciwork 和旧版安装器 → 拉起 runner）。
set -euo pipefail

USER_NAME=for-konghai
VOLUME_NAME=CIWork
APFS_CONTAINER=disk3
VOLUME_QUOTA=100g
TEMP_MOUNT=/Volumes/$VOLUME_NAME
TARGET_DIR=/Users/$USER_NAME/gha
RUNNER_ROOT=/Users/$USER_NAME/actions-runner
STAMP=$(date +%Y%m%d)
BACKUP_DIR=$TARGET_DIR.pre-ciwork-$STAMP
LOG=/var/log/ciwork-migrate.log
GO_SLOTS=(1 2)
DAEMON_LABELS=(
  actions.runner.cypressoai.lemon-imac-1
  actions.runner.cypressoai.lemon-imac-2
  actions.runner.IAmKongHai-AcquiLangAI.lemon-imac-acquilang-ci-1
)
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
  chown "$USER_NAME:staff" "$mp"
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
  while ((${#pending[@]} > 0)); do
    local still=()
    for label in "${pending[@]}"; do
      if ! launchctl print "system/$label" >/dev/null 2>&1; then
        log "$label 未加载，跳过"
      elif runner_busy "$(label_slot "$label")"; then
        still+=("$label")
      else
        launchctl bootout "system/$label" && log "已停 $label"
      fi
    done
    pending=("${still[@]+"${still[@]}"}")
    if ((${#pending[@]} > 0)); then
      (($(date +%s) < deadline)) || die "等待 runner 空闲超时，仍在跑：${pending[*]}（已停的 runner 用 --start-runners 拉起）"
      log "等待空闲：${pending[*]}"
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
  sleep 15
  log "Runner.Listener 数量：$(pgrep -f "$RUNNER_ROOT/.*/Runner.Listener" | wc -l | tr -d ' ')（期望 3）"
}

migrate() {
  volume_exists || die "先跑 --prepare"
  [[ $(volume_mountpoint) == "$TEMP_MOUNT" ]] || die "${VOLUME_NAME} 应挂在 ${TEMP_MOUNT}（当前 $(volume_mountpoint)）"
  [[ -e $BACKUP_DIR ]] && die "$BACKUP_DIR 已存在，可能迁移过一次"
  [[ -f $TEMP_MOUNT/.fseventsd/no_log ]] || die "缺少 no_log"
  grep -q 'gha/cache/go-build-li' "$TARGET_DIR/scripts/install-lemon-imac-runner-daemons.sh" \
    || die "${TARGET_DIR}/scripts/install-lemon-imac-runner-daemons.sh 还是旧版（GOCACHE 未指向 CIWork），先同步仓库版本"

  drain_and_stop

  log "复制 ${TARGET_DIR} → ${TEMP_MOUNT}（ditto）"
  ditto "$TARGET_DIR" "$TEMP_MOUNT"
  for n in "${GO_SLOTS[@]}"; do
    local src=$RUNNER_ROOT/lemon-imac-$n/cache/go-build
    if [[ -d $src ]]; then
      log "复制 $src → $TEMP_MOUNT/cache/go-build-li$n"
      ditto "$src" "$TEMP_MOUNT/cache/go-build-li$n"
    fi
  done
  chown -R "$USER_NAME:staff" "$TEMP_MOUNT/cache"
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

  # GOCACHE 改到卷上：.env 用 sed，plist 由安装器重写（它会同时 bootstrap 并 kickstart lemon-imac-1/2）
  for n in "${GO_SLOTS[@]}"; do
    local env_file=$RUNNER_ROOT/lemon-imac-$n/.env
    cp -p "$env_file" "$env_file.bak-ciwork-$STAMP"
    sed -i '' "s|^GOCACHE=.*|GOCACHE=$TARGET_DIR/cache/go-build-li$n|" "$env_file"
    log "lemon-imac-$n $(grep '^GOCACHE=' "$env_file")"
  done
  for label in actions.runner.cypressoai.lemon-imac-1 actions.runner.cypressoai.lemon-imac-2 \
    com.cypressoai.gha-runner-maintenance com.cypressoai.gha-runner-maintenance-weekly; do
    cp -p "/Library/LaunchDaemons/$label.plist" "/Library/LaunchDaemons/$label.plist.bak-ciwork-$STAMP"
  done
  bash "$TARGET_DIR/scripts/install-lemon-imac-runner-daemons.sh" 2>&1 | tee -a "$LOG"

  start_runners
  status
  log "完成。确认 CI 正常后，再删除 $BACKUP_DIR、$RUNNER_ROOT/lemon-imac-*/cache/go-build 和 /Library/LaunchDaemons/*.bak-ciwork-$STAMP"
}

status() {
  echo "--- volume"
  diskutil info "$VOLUME_NAME" 2>/dev/null | grep -E "Volume Name|Mount Point|Volume UUID|Owners|Container Total|Volume Used" || echo "卷不存在"
  local mp
  mp=$(volume_mountpoint 2>/dev/null || true)
  [[ -n $mp && -d $mp/.fseventsd ]] && ls -la "$mp/.fseventsd"
  [[ -n $mp ]] && mdutil -s "$mp" 2>/dev/null | tail -1
  echo "--- fstab"
  grep "$TARGET_DIR" /etc/fstab 2>/dev/null || echo "(无)"
  echo "--- GOCACHE"
  grep -H '^GOCACHE=' "$RUNNER_ROOT"/lemon-imac-{1,2}/.env 2>/dev/null || true
  echo "--- runners"
  pgrep -fl "$RUNNER_ROOT/.*/Runner.Listener" | awk '{print $1, $2}' || echo "(无 Runner.Listener)"
}

case "${1:-}" in
  --prepare) prepare ;;
  --migrate) migrate ;;
  --status) status ;;
  --start-runners) start_runners ;;
  *) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
