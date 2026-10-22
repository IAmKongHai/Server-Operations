#!/bin/bash
# 把 mac-mini 上 konghai 名下的团队资产迁到 hon（计划：docs/plans/2026-10-22-1645-ops-mac-mini-team-assets-to-hon-plan.md）。
# 只放需要 root 的步骤；hon 侧不需要 root 的操作（建 colima team profile 等）经 ssh mac-mini-hon 直接做。
#
# 安装（用户执行一次，脚本改动后重装）：
#   sudo install -o root -g wheel -m 755 scripts/migrate-mac-mini-team-to-hon.sh /usr/local/sbin/hon-migrate.sh
#   sudo install -o root -g wheel -m 755 scripts/install-mac-mini-team-services-daemons.sh /usr/local/sbin/hon-team-services.sh
#   echo 'konghai ALL=(root) NOPASSWD: /usr/local/sbin/hon-migrate.sh, /usr/local/sbin/hon-team-services.sh' \
#     | sudo tee /etc/sudoers.d/konghai-hon-migrate && sudo chmod 440 /etc/sudoers.d/konghai-hon-migrate
#
# 子命令（root）：
#   --status                     只读：runner、CIWork、两个账户的 colima、团队 LaunchDaemon
#   --snapshot                   备份 plist / fstab / crontab / runner 配置 / stack 配置到 /var/backups
#   --baseline before|after      记录各库 / redis / garage 基线到导出目录（before 读 konghai VM，after 读 hon team）
#   --services-export            U2：dump、停容器、打包卷、存镜像、复制 stacks/backups 到 hon、改 konghai crontab
#   --stop-konghai-vm            U2：停 konghai 的 colima（磁盘保留）并 disable 守护
#   --services-import [stack..]  U2：导入镜像和卷，按顺序 up（不给参数时 up 除 cmm-postgres 外的全部）
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
CRON_DROP_PATTERN='claude-cron|Codex 每日触发|Claude Code 每日触发|sonarqube/backup.sh|SonarQube DB 每日备份|acquilangai-backup.sh|AcquiLangAI postgres|sync-from-prod.sh|AcquiLang 生产库同步'

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$LOG"; }
die() { log "ERROR: $*"; exit 1; }
kdocker() { DOCKER_HOST=$K_SOCK "$DOCKER" "$@"; }
hdocker() { DOCKER_HOST=$H_SOCK "$DOCKER" "$@"; }
# 匿名卷名是 64 位十六进制，不迁
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
  log "快照完成：$SNAPSHOT_DIR（runner $(ls "$SNAPSHOT_DIR/runners" | wc -l | tr -d ' ') 个，plist $(ls "$SNAPSHOT_DIR/launchdaemons" | wc -l | tr -d ' ') 个）"
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
  log "基线（$which）写入 $out：$(wc -l <"$out" | tr -d ' ') 行"
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
  hdocker info >/dev/null 2>&1 || die "hon 的 team VM 未运行（$H_SOCK）"
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

case "${1:-}" in
  --status) status ;;
  --snapshot) snapshot ;;
  --baseline) baseline "${2:-}" ;;
  --services-export) services_export ;;
  --stop-konghai-vm) stop_konghai_vm ;;
  --services-import) shift; services_import "$@" ;;
  *) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
