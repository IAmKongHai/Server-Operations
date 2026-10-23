#!/bin/bash
# 把 mac-mini 上 konghai 名下的团队资产迁到 hon（计划：docs/plans/2026-10-22-1645-ops-mac-mini-team-assets-to-hon-plan.md）。
# 只放需要 root 的步骤；hon 侧不需要 root 的操作（建 colima team profile 等）经 ssh mac-mini-hon 直接做。
#
# 安装（以 konghai 执行，脚本改动后重跑）：sudo ~/hon-migrate-src/install-hon-migrate.sh（见 scripts/install-hon-migrate.sh）
#
# 子命令（root）：
#   --status                     只读：runner、CIWork、两个账户的 colima、团队 LaunchDaemon
#   --snapshot                   备份 plist / fstab / crontab / runner 配置 / stack 配置到 /var/backups
#   --baseline before|after      记录各库 / redis / garage 基线到导出目录（before 读 konghai VM，after 读 hon team）
#   --services-export            U2：dump、停容器、打包卷、存镜像、复制 stacks/backups 到 hon、改 konghai crontab
#   --stop-konghai-vm            U2：停 konghai 的 colima（磁盘保留）并 disable 守护
#   --services-import [stack..]  U2：导入镜像和卷，按顺序 up（不给参数时 up 除 cmm-postgres 外的全部）
#   --drain-runners              窗口开头：等 job 结束后停全部 konghai runner 与 hon 的 khmini
#   --runners                    U3：khmini 挪进子目录、CIWork 改挂 /Users/hon/gha、11 个普通 runner 改以 hon 运行，
#                                签名 runner 只改 workFolder（仍以 konghai 运行），拉起 runner，去掉 konghai 维护 crontab
#   --start-runners              出错中断后按现有 plist 拉起 runner（acquilang-ci-4/5 除外）
#   --signing                    U5：等签名 runner 空闲后停下，复制 ~/.config/icare 与 Android SDK 到 hon，
#                                两个签名 runner 改以 hon 运行，m1 / al1 给 hon，pnpm store 回到共享
#
# 注意：macOS /bin/bash 是 3.2，变量后紧跟中文全角字符要写成 ${VAR}。
set -euo pipefail

STAMP=$(date +%Y%m%d)
LOG=/var/log/hon-migrate.log
DOCKER=/opt/homebrew/bin/docker
COMPOSE=/opt/homebrew/bin/docker-compose
COLIMA=/opt/homebrew/bin/colima
K_HOME=/Users/konghai
H_HOME=/Users/hon
K_SOCK=unix://$K_HOME/.colima/default/docker.sock
H_SOCK=unix://$H_HOME/.colima/team/docker.sock
EXPORT_DIR=$H_HOME/migration
SNAPSHOT_DIR=/var/backups/hon-migration-$STAMP
# 导入后 up 的顺序：SonarQube 先起并核对，再起其余；cmm-postgres 只建不启（R7）
STACK_ORDER=(sonarqube shared-dev-postgres shared-dev-redis shared-dev-s3 acquilang-postgres nyh-postgres richer sub2api)
NO_START_STACKS=(cmm-postgres)
# konghai crontab 里迁走或删除的行（runner 维护两行留到 U3）
CRON_DROP_PATTERN_U3='gha-runner-maintenance'
CRON_DROP_PATTERN='claude-cron|Codex 每日触发|Claude Code 每日触发|sonarqube/backup.sh|SonarQube DB 每日备份|acquilangai-backup.sh|AcquiLangAI postgres|sync-from-prod.sh|AcquiLang 生产库同步'

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
die() { log "ERROR: $*"; exit 1; }
kdocker() { DOCKER_HOST=$K_SOCK "$DOCKER" "$@"; }
hdocker() { DOCKER_HOST=$H_SOCK "$DOCKER" "$@"; }
# 匿名卷名是 64 位十六进制，不迁
K_RUNNERS=$K_HOME/actions-runner
H_RUNNERS=$H_HOME/actions-runner
REGULAR_RUNNERS=(mac-mini-sonar-1 mac-mini-sonar-2 mac-mini-sonar-3 mac-mini-sonar-4
  mac-mini-acquilang-ci-1 mac-mini-acquilang-ci-2 mac-mini-acquilang-ci-3 mac-mini-acquilang-ci-4 mac-mini-acquilang-ci-5
  caimiamiao-1 konghai-friends-lab-1)
# U5 前仍以 konghai 运行
SIGNING_RUNNERS=(mac-mini-mobile-1 mac-mini-acquilang-native-1)
# 一直 disabled，plist 照改但不拉起
DISABLED_RUNNERS=(mac-mini-acquilang-ci-4 mac-mini-acquilang-ci-5)
KHMINI_LABEL=ai.cypresso.actions-runner
HON_UID=$(id -u hon)
CIWORK_UUID=8FF8D622-BAB7-47C3-8601-44CBB7988E7F
DRAIN_TIMEOUT_SEC=5400
named_volumes() { "$@" volume ls --format '{{.Name}}' | grep -vE '^[0-9a-f]{64}$' || true; }

[[ $(id -u) -eq 0 ]] || { echo "请用 sudo 运行" >&2; exit 1; }

status() {
  echo "--- CIWork"
  diskutil info CIWork 2>/dev/null | grep -E "Mount Point|Volume UUID" || echo "卷不存在"
  grep -i -E "ciwork|8FF8D622" /etc/fstab 2>/dev/null || echo "(fstab 无 CIWork 行)"
  echo "--- Runner.Listener（用户 / 路径）"
  ps -axo user=,command= | awk '/[R]unner.Listener/ {print $1, $2}' || true
  echo "--- runner LaunchDaemon（UserName / 是否加载）"
  local plist label
  for plist in /Library/LaunchDaemons/actions.runner.*.plist; do
    label=$(basename "$plist" .plist)
    printf '%-75s %-8s %s\n' "$label" "$(plutil -extract UserName raw -o - "$plist" 2>/dev/null || echo '?')" \
      "$(launchctl print "system/$label" >/dev/null 2>&1 && echo loaded || echo -)"
  done
  echo "--- 其它团队 LaunchDaemon"
  ls /Library/LaunchDaemons | grep -E 'colima|cypressoai|konghai' | grep -v '^actions.runner' || true
  echo "--- colima（konghai）"
  sudo -u konghai -H "$COLIMA" list 2>&1 || true
  echo "--- colima（hon）"
  sudo -u hon -H "$COLIMA" list 2>&1 || true
  echo "--- konghai crontab 非注释行数：$(crontab -u konghai -l 2>/dev/null | grep -cvE '^\s*(#|$)' || true)"
}

snapshot() {
  [[ -e $SNAPSHOT_DIR ]] && die "$SNAPSHOT_DIR 已存在"
  mkdir -p "$SNAPSHOT_DIR"/{launchdaemons,runners,stacks,hon}
  chmod 700 "$SNAPSHOT_DIR"
  cp -p /Library/LaunchDaemons/actions.runner.*.plist /Library/LaunchDaemons/com.konghai.*.plist "$SNAPSHOT_DIR/launchdaemons/"
  cp -p /etc/fstab "$SNAPSHOT_DIR/fstab"
  cp -pR /etc/sudoers.d "$SNAPSHOT_DIR/sudoers.d"
  crontab -u konghai -l >"$SNAPSHOT_DIR/crontab.konghai" 2>/dev/null || true
  crontab -u hon -l >"$SNAPSHOT_DIR/crontab.hon" 2>/dev/null || true
  local dir name f
  for dir in $K_HOME/actions-runner/*/ $H_HOME/actions-runner/; do
    [[ -f $dir/.runner ]] || continue
    name=$(basename "$dir")
    mkdir -p "$SNAPSHOT_DIR/runners/$name"
    for f in .runner .env .path; do
      [[ -f $dir/$f ]] && cp -p "$dir/$f" "$SNAPSHOT_DIR/runners/$name/"
    done
  done
  cp -p $H_HOME/actions-runner/ai.cypresso.actions-runner.plist "$SNAPSHOT_DIR/hon/" 2>/dev/null || true
  # stack 只存配置，不存数据目录
  for dir in $K_HOME/stacks/*/; do
    name=$(basename "$dir")
    mkdir -p "$SNAPSHOT_DIR/stacks/$name"
    find "$dir" -maxdepth 1 -type f \( -name '*.y*ml' -o -name '.env' -o -name '*.sh' -o -name '*.toml' \) \
      -exec cp -p {} "$SNAPSHOT_DIR/stacks/$name/" \;
  done
  cp -p $K_HOME/.colima/default/colima.yaml "$SNAPSHOT_DIR/colima.default.yaml"
  cp -p $K_HOME/scripts/acquilangai-backup.sh "$SNAPSHOT_DIR/"
  log "快照完成：${SNAPSHOT_DIR}（runner $(ls "$SNAPSHOT_DIR/runners" | wc -l | tr -d ' ') 个，plist $(ls "$SNAPSHOT_DIR/launchdaemons" | wc -l | tr -d ' ') 个）"
}

# 每个 postgres 的库大小与全部用户表的精确行数；redis 键数；garage bucket
baseline() {
  local which=${1:-} dk out
  case $which in
    before) dk=kdocker ;;
    after) dk=hdocker ;;
    *) die "用法：--baseline before|after" ;;
  esac
  mkdir -p "$EXPORT_DIR"
  out=$EXPORT_DIR/baseline-$which.txt
  : >"$out"
  local c user db
  for c in $($dk ps --format '{{.Names}}' | sort); do
    case $($dk inspect -f '{{.Config.Image}}' "$c") in
      postgres:* | timescale/*)
        user=$($dk exec "$c" printenv POSTGRES_USER 2>/dev/null || echo postgres)
        for db in $($dk exec "$c" psql -U "$user" -d postgres -Atc "select datname from pg_database where not datistemplate order by 1"); do
          echo "## $c/$db size=$($dk exec "$c" psql -U "$user" -d "$db" -Atc "select pg_database_size(current_database())")" >>"$out"
          $dk exec "$c" psql -U "$user" -d "$db" -Atc \
            "select format('select %L, count(*) from %I.%I;', schemaname||'.'||relname, schemaname, relname) from pg_stat_user_tables order by schemaname, relname" |
            $dk exec -i "$c" psql -U "$user" -d "$db" -At >>"$out" 2>&1 || echo "count failed" >>"$out"
        done
        ;;
      redis:*)
        echo "## $c dbsize=$($dk exec "$c" sh -c 'REDISCLI_AUTH=${REDISCLI_AUTH:-$REDIS_PASSWORD} redis-cli DBSIZE' 2>&1)" >>"$out"
        ;;
      dxflrs/garage:*)
        echo "## $c buckets" >>"$out"
        $dk exec "$c" /garage bucket list >>"$out" 2>&1 || true
        ;;
    esac
  done
  chown hon:staff "$EXPORT_DIR" "$out"
  log "基线（${which}）写入 ${out}：$(wc -l <"$out" | tr -d ' ') 行"
}

services_export() {
  [[ -d $EXPORT_DIR/volumes ]] && die "$EXPORT_DIR/volumes 已存在，可能导出过一次"
  [[ -d $H_HOME/stacks ]] && die "$H_HOME/stacks 已存在"
  mkdir -p "$EXPORT_DIR"/{dumps,volumes}

  log "1/6 逻辑备份（pg_dumpall，作保险）"
  local c user
  for c in $(kdocker ps --format '{{.Names}}' | sort); do
    case $(kdocker inspect -f '{{.Config.Image}}' "$c") in
      postgres:* | timescale/*)
        user=$(kdocker exec "$c" printenv POSTGRES_USER 2>/dev/null || echo postgres)
        kdocker exec "$c" pg_dumpall -U "$user" | gzip >"$EXPORT_DIR/dumps/$c.sql.gz"
        log "  $c → $(du -h "$EXPORT_DIR/dumps/$c.sql.gz" | cut -f1)"
        ;;
    esac
  done

  log "2/6 停全部容器"
  kdocker ps --format '{{.Names}}' | sort >"$EXPORT_DIR/running-before.txt"
  # shellcheck disable=SC2046
  kdocker stop -t 60 $(kdocker ps -q)

  log "3/6 打包命名卷（原始字节，--numeric-owner）"
  local v
  for v in $(named_volumes kdocker); do
    kdocker volume inspect -f '{{json .Labels}}' "$v" >"$EXPORT_DIR/volumes/$v.labels"
    kdocker run --rm -v "$v":/v:ro alpine:latest tar --numeric-owner -C /v -cf - . >"$EXPORT_DIR/volumes/$v.tar"
    log "  $v → $(du -h "$EXPORT_DIR/volumes/$v.tar" | cut -f1)"
  done

  log "4/6 保存镜像"
  local images
  images=$( (kdocker ps -a --format '{{.Image}}'; echo alpine:latest) | sort -u | tr '\n' ' ')
  echo "$images" >"$EXPORT_DIR/images.txt"
  # shellcheck disable=SC2086
  kdocker save -o "$EXPORT_DIR/images.tar" $images
  log "  images.tar $(du -h "$EXPORT_DIR/images.tar" | cut -f1)：$images"

  log "5/6 复制 stacks / backups / scripts 到 hon"
  ditto "$K_HOME/stacks" "$H_HOME/stacks"
  ditto "$K_HOME/backups" "$H_HOME/backups"
  mkdir -p "$H_HOME/scripts"
  cp -p "$K_HOME/scripts/acquilangai-backup.sh" "$H_HOME/scripts/"
  chown -R hon:staff "$H_HOME/stacks" "$H_HOME/backups" "$H_HOME/scripts" "$EXPORT_DIR"

  log "6/6 konghai crontab 去掉 claude-cron / 备份 / 同步（维护两行留到 U3）"
  local tmp
  tmp=$(mktemp)
  crontab -u konghai -l >"$tmp.before"
  grep -vE "$CRON_DROP_PATTERN" "$tmp.before" >"$tmp" || true
  crontab -u konghai "$tmp"
  cp -p "$tmp.before" "$EXPORT_DIR/crontab.konghai.before-export"
  log "  konghai crontab 剩余非注释行：$(grep -cvE '^\s*(#|$)' "$tmp" || true)"
  rm -f "$tmp" "$tmp.before"
  log "导出完成：$(du -sh "$EXPORT_DIR" | cut -f1)"
}

stop_konghai_vm() {
  launchctl bootout system/com.konghai.colima 2>/dev/null || true
  launchctl disable system/com.konghai.colima
  sudo -u konghai -H "$COLIMA" stop 2>&1 | tee -a "$LOG" || true
  # 以 --foreground 拉起的进程不随 stop 退出（2026-10-20 经验）
  pkill -u konghai -f 'colima start --foreground' 2>/dev/null || true
  sleep 3
  sudo -u konghai -H "$COLIMA" status 2>&1 | tee -a "$LOG" || true
  log "konghai colima 已停（磁盘保留）；回滚：launchctl enable system/com.konghai.colima && launchctl bootstrap system /Library/LaunchDaemons/com.konghai.colima.plist"
}

services_import() {
  hdocker info >/dev/null 2>&1 || die "hon 的 team VM 未运行（${H_SOCK}）"
  if [[ ! -f $EXPORT_DIR/.images-loaded ]]; then
    log "导入镜像"
    hdocker load -i "$EXPORT_DIR/images.tar" | tee -a "$LOG"
    touch "$EXPORT_DIR/.images-loaded"
  fi
  local f v labels args key
  for f in "$EXPORT_DIR"/volumes/*.tar; do
    v=$(basename "$f" .tar)
    hdocker volume inspect "$v" >/dev/null 2>&1 && continue
    # 还原 compose 标签，避免 compose 把它当成外来卷
    args=()
    labels=$(cat "$EXPORT_DIR/volumes/$v.labels")
    if [[ $labels != null && $labels != '{}' ]]; then
      for key in $(echo "$labels" | /usr/bin/python3 -c 'import json,sys; [print(f"{k}={v}") for k,v in json.load(sys.stdin).items()]'); do
        args+=(--label "$key")
      done
    fi
    hdocker volume create "${args[@]+"${args[@]}"}" "$v" >/dev/null
    hdocker run --rm -i -v "$v":/v alpine:latest tar --numeric-owner -C /v -xf - <"$f"
    log "  卷 $v 已导入"
  done
  local stacks=("$@") s
  ((${#stacks[@]})) || stacks=("${STACK_ORDER[@]}" "${NO_START_STACKS[@]}")
  for s in "${stacks[@]}"; do
    [[ -d $H_HOME/stacks/$s ]] || die "缺少 $H_HOME/stacks/$s"
    if [[ " ${NO_START_STACKS[*]} " == *" $s "* ]]; then
      sudo -u hon -H env DOCKER_HOST=$H_SOCK bash -c "cd '$H_HOME/stacks/$s' && '$COMPOSE' up --no-start" 2>&1 | tee -a "$LOG"
      log "  $s 已创建（不启动）"
    else
      sudo -u hon -H env DOCKER_HOST=$H_SOCK bash -c "cd '$H_HOME/stacks/$s' && '$COMPOSE' up -d" 2>&1 | tee -a "$LOG"
      log "  $s 已启动"
    fi
  done
  hdocker ps -a --format '{{.Names}}\t{{.Status}}' | sort | tee -a "$LOG"
}

runner_label() { basename "$(ls /Library/LaunchDaemons/actions.runner.*."$1".plist)" .plist; }
# slot 目录 → 是否在跑 job（Runner.Worker 是 Listener 的子进程）
runner_busy() { pgrep -f "$1/bin[^ ]*/Runner.Worker" >/dev/null; }
is_disabled_runner() { [[ " ${DISABLED_RUNNERS[*]} " == *" $1 "* ]]; }

# 逐个等空闲再停，不打断正在跑的 job
drain_runners() {
  local pending=() name label still deadline=$(($(date +%s) + DRAIN_TIMEOUT_SEC)) khmini_pending=1
  for name in "${REGULAR_RUNNERS[@]}" "${SIGNING_RUNNERS[@]}"; do
    is_disabled_runner "$name" || pending+=("$name")
  done
  while ((${#pending[@]} > 0 || khmini_pending)); do
    still=()
    for name in "${pending[@]+"${pending[@]}"}"; do
      label=$(runner_label "$name")
      if ! launchctl print "system/$label" >/dev/null 2>&1; then
        log "$label 未加载，跳过"
      elif runner_busy "$K_RUNNERS/$name"; then
        still+=("$name")
      else
        launchctl bootout "system/$label" && log "已停 $label"
      fi
    done
    pending=("${still[@]+"${still[@]}"}")
    if ((khmini_pending)); then
      if ! launchctl print "user/$HON_UID/$KHMINI_LABEL" >/dev/null 2>&1; then
        khmini_pending=0
      elif ! runner_busy "$H_RUNNERS" && ! runner_busy "$H_RUNNERS/khmini"; then
        launchctl bootout "user/$HON_UID/$KHMINI_LABEL" && log "已停 khmini"
        khmini_pending=0
      fi
    fi
    if ((${#pending[@]} > 0 || khmini_pending)); then
      (($(date +%s) < deadline)) || die "等待 runner 空闲超时：${pending[*]:-} khmini=${khmini_pending}（用 --start-runners 拉起已停的）"
      log "等待空闲：${pending[*]:-} $( ((khmini_pending)) && echo khmini)"
      sleep 30
    fi
  done
  sleep 3
  if pgrep -f "/actions-runner/.*Runner.Listener" >/dev/null; then die "仍有 Runner.Listener 在跑"; fi
  log "所有 runner 已停"
}

# khmini 原来直接装在 actions-runner 根下，挪进 khmini/ 子目录，hon 的 runner 根下只放 runner 子目录
move_khmini() {
  [[ -d $H_RUNNERS/khmini ]] && { log "khmini 已在子目录，跳过"; return; }
  mkdir "$H_RUNNERS/khmini"
  local entry
  for entry in "$H_RUNNERS"/* "$H_RUNNERS"/.[!.]*; do
    [[ -e $entry && $entry != "$H_RUNNERS/khmini" ]] && mv "$entry" "$H_RUNNERS/khmini/"
  done
  sed -i '' "s|$H_RUNNERS|$H_RUNNERS/khmini|g" "$H_RUNNERS/khmini/$KHMINI_LABEL.plist"
  chown -R hon:staff "$H_RUNNERS"
  launchctl bootstrap "user/$HON_UID" "$H_RUNNERS/khmini/$KHMINI_LABEL.plist"
  log "khmini 已挪到 $H_RUNNERS/khmini 并拉起"
}

remount_ciwork() {
  [[ $(diskutil info CIWork | awk -F': *' '/Mount Point/{print $2}') == "$H_HOME/gha" ]] && { log "CIWork 已挂在 $H_HOME/gha"; return; }
  # 常驻的 spindump / mds 会只读占着卷上的文件，普通 unmount 失败；runner 已全停，强制卸载不丢数据
  if [[ $(diskutil info CIWork | awk -F': *' '/Mount Point/{print $2}') == "$K_HOME/gha" ]]; then
    diskutil unmount force "$K_HOME/gha" | tee -a "$LOG"
  fi
  cp -p /etc/fstab "/etc/fstab.bak-hon-$STAMP"
  sed -i '' "s|^UUID=$CIWORK_UUID $K_HOME/gha |UUID=$CIWORK_UUID $H_HOME/gha |" /etc/fstab
  grep -q "$H_HOME/gha" /etc/fstab || die "fstab 未改成 $H_HOME/gha"
  if [[ -d $K_HOME/gha ]]; then rmdir "$K_HOME/gha"; fi
  # 挂载点下方的目录 root 所有：卷没挂上时写入直接失败，不会悄悄写回系统数据卷
  mkdir -p "$H_HOME/gha"
  chown root:wheel "$H_HOME/gha"
  chmod 755 "$H_HOME/gha"
  diskutil mount -mountPoint "$H_HOME/gha" CIWork | tee -a "$LOG"
  [[ $(diskutil info CIWork | awk -F': *' '/Mount Point/{print $2}') == "$H_HOME/gha" ]] || die "挂载到 $H_HOME/gha 失败"
  # 卷内除签名 runner 的 m1 / al1 外都给 hon；系统目录不动
  chown hon:staff "$H_HOME/gha"
  local entry
  for entry in "$H_HOME/gha"/* "$H_HOME/gha"/.[!.]*; do
    case $(basename "$entry") in
      m1 | al1 | .fseventsd | .Spotlight-V100 | .Trashes | .metadata_never_index) ;;
      *) [[ -e $entry ]] && chown -R hon:staff "$entry" ;;
    esac
  done
  # U5 前签名 runner 以 konghai 运行，用单独的 pnpm store（共享 store 已属 hon）
  mkdir -p "$H_HOME/gha/cache/pnpm-store-signing"
  chown konghai:staff "$H_HOME/gha/cache/pnpm-store-signing"
  log "CIWork 已改挂 $H_HOME/gha 并 chown hon"
}

# 把 runner 配置里的 konghai 路径换成 hon，PATH 去掉不用的 ~/.cargo/bin、~/.volta/bin
rewrite_runner_files() {
  local dir=$1 f
  for f in .runner .runner_migrated .env .path .service; do
    [[ -f $dir/$f ]] && sed -i '' "s|$K_HOME/|$H_HOME/|g" "$dir/$f"
  done
  [[ -f $dir/.path ]] && sed -i '' -e "s|:$H_HOME/.cargo/bin||" -e "s|:$H_HOME/.volta/bin||" "$dir/.path"
  return 0
}

move_regular_runner() {
  local name=$1 label plist
  label=$(runner_label "$name")
  plist=/Library/LaunchDaemons/$label.plist
  if [[ -d $K_RUNNERS/$name ]]; then
    mv "$K_RUNNERS/$name" "$H_RUNNERS/$name"
  fi
  rewrite_runner_files "$H_RUNNERS/$name"
  # runner 自更新留下的 bin / externals 是指向旧目录的绝对路径符号链接，改成相对路径
  local link target
  for link in "$H_RUNNERS/$name"/*; do
    [[ -L $link ]] || continue
    target=$(readlink "$link")
    [[ $target == "$K_RUNNERS/$name/"* ]] && ln -sfhn "$(basename "$target")" "$link"
  done
  chown -Rh hon:staff "$H_RUNNERS/$name"
  sed -i '' -e "s|$K_HOME/|$H_HOME/|g" -e "s|<string>konghai</string>|<string>hon</string>|" \
    -e "s|:$H_HOME/.cargo/bin||" -e "s|:$H_HOME/.volta/bin||" "$plist"
  plutil -replace EnvironmentVariables.DOCKER_HOST -string "$H_SOCK" "$plist"
  plutil -replace EnvironmentVariables.HOME -string "$H_HOME" "$plist"
  plutil -lint "$plist" >/dev/null
  [[ $(plutil -extract UserName raw -o - "$plist") == hon ]] || die "$plist UserName 未改成 hon"
  mkdir -p "$H_HOME/Library/Logs/$label"
  chown hon:staff "$H_HOME/Library/Logs/$label"
  log "  $name → $H_RUNNERS/$name"
}

start_runners() {
  local name label
  for name in "${REGULAR_RUNNERS[@]}" "${SIGNING_RUNNERS[@]}"; do
    is_disabled_runner "$name" && continue
    label=$(runner_label "$name")
    launchctl print "system/$label" >/dev/null 2>&1 && continue
    launchctl enable "system/$label"
    launchctl bootstrap system "/Library/LaunchDaemons/$label.plist" 2>&1 | tee -a "$LOG" || true
  done
  sleep 15
  ps -axo user=,command= | awk '/[R]unner.Listener/ {print "  " $1, $2}' | tee -a "$LOG"
}

runners() {
  hdocker info >/dev/null 2>&1 || die "team VM 未运行：sonar runner 需要 ${H_SOCK}"
  if pgrep -f "/actions-runner/.*Runner.Listener" >/dev/null; then die "还有 runner 在跑，先 --drain-runners"; fi
  mkdir -p "$H_RUNNERS"
  chown hon:staff "$H_RUNNERS"

  log "1/5 khmini 挪进子目录"
  move_khmini
  log "2/5 CIWork 改挂"
  remount_ciwork
  log "3/5 普通 runner 改以 hon 运行"
  local name
  for name in "${REGULAR_RUNNERS[@]}"; do move_regular_runner "$name"; done
  log "4/5 签名 runner 改 workFolder（仍以 konghai 运行）"
  for name in "${SIGNING_RUNNERS[@]}"; do
    sed -i '' "s|$K_HOME/gha/|$H_HOME/gha/|g" "$K_RUNNERS/$name/.runner"
    [[ -f $K_RUNNERS/$name/.runner_migrated ]] && sed -i '' "s|$K_HOME/gha/|$H_HOME/gha/|g" "$K_RUNNERS/$name/.runner_migrated"
    sed -i '' "s|^PNPM_STORE_PATH=.*|PNPM_STORE_PATH=$H_HOME/gha/cache/pnpm-store-signing|" "$K_RUNNERS/$name/.env"
  done
  log "5/5 拉起 runner，去掉 konghai 维护 crontab"
  start_runners
  local tmp
  tmp=$(mktemp)
  crontab -u konghai -l | grep -vE "$CRON_DROP_PATTERN_U3" >"$tmp" || true
  crontab -u konghai "$tmp"
  rm -f "$tmp"
  log "konghai crontab 剩余非注释行：$(crontab -u konghai -l | grep -cvE '^\s*(#|$)' || true)"
}

signing() {
  hdocker info >/dev/null 2>&1 || die "team VM 未运行"
  local name label deadline=$(($(date +%s) + DRAIN_TIMEOUT_SEC))
  log "1/5 等签名 runner 空闲后停下"
  for name in "${SIGNING_RUNNERS[@]}"; do
    label=$(runner_label "$name")
    while runner_busy "$K_RUNNERS/$name"; do
      (($(date +%s) < deadline)) || die "等待 $name 空闲超时"
      log "  等待 $name"
      sleep 30
    done
    launchctl bootout "system/$label" 2>/dev/null || true
    log "  已停 $label"
  done

  log "2/5 复制签名凭据与 Android SDK 到 hon"
  if [[ ! -d $H_HOME/.config/icare ]]; then
    mkdir -p "$H_HOME/.config"
    ditto "$K_HOME/.config/icare" "$H_HOME/.config/icare"
    # App Store Connect 密钥路径写死在 json 里
    sed -i '' "s|$K_HOME/.config/icare/|$H_HOME/.config/icare/|g" \
      "$H_HOME/.config/icare/preview/testflight.json" "$H_HOME/.config/icare/production/appstore.json"
    chown -R hon:staff "$H_HOME/.config/icare"
    chmod 700 "$H_HOME/.config/icare" "$H_HOME/.config/icare"/*
  fi
  if [[ ! -d $H_HOME/Library/Android/sdk ]]; then
    mkdir -p "$H_HOME/Library/Android"
    ditto "$K_HOME/Library/Android/sdk" "$H_HOME/Library/Android/sdk"
    chown -R hon:staff "$H_HOME/Library/Android"
  fi
  log "  icare 凭据与 Android SDK（$(du -sh "$H_HOME/Library/Android/sdk" | cut -f1)）已就绪"

  log "3/5 签名 runner 改以 hon 运行"
  for name in "${SIGNING_RUNNERS[@]}"; do
    move_regular_runner "$name"
    sed -i '' "s|^PNPM_STORE_PATH=.*|PNPM_STORE_PATH=$H_HOME/gha/cache/pnpm-store|" "$H_RUNNERS/$name/.env"
  done

  log "4/5 m1 / al1 给 hon，删除过渡用的 pnpm-store-signing"
  chown -R hon:staff "$H_HOME/gha/m1" "$H_HOME/gha/al1"
  rm -rf "$H_HOME/gha/cache/pnpm-store-signing"

  log "5/5 拉起签名 runner"
  for name in "${SIGNING_RUNNERS[@]}"; do
    label=$(runner_label "$name")
    launchctl enable "system/$label"
    launchctl bootstrap system "/Library/LaunchDaemons/$label.plist" 2>&1 | tee -a "$LOG" || true
  done
  sleep 15
  ps -axo user=,command= | awk '/[R]unner.Listener/ {print "  " $1, $2}' | tee -a "$LOG"
}

case "${1:-}" in
  --status) status ;;
  --snapshot) snapshot ;;
  --baseline) baseline "${2:-}" ;;
  --services-export) services_export ;;
  --stop-konghai-vm) stop_konghai_vm ;;
  --services-import) shift; services_import "$@" ;;
  --drain-runners) drain_runners ;;
  --runners) runners ;;
  --start-runners) start_runners ;;
  --signing) signing ;;
  *) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
