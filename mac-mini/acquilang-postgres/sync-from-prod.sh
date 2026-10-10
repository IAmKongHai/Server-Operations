#!/bin/bash
# 每 6 小时把 nyh-prod 上的 AcquiLang 生产库同步到 mac-mini 的 acquilang_db。
#
# 生产侧只读：在 nyh-prod 上用已有的 postgres:18.6-alpine 做 pg_dump。
# 密码留在 nyh-prod 的 /www/wwwroot/python/backup-rds.sh，不复制到本机，也不写进日志。
#
# 顺序：
#   1. 导出生产库到临时文件
#   2. 把当前开发库打成自定义格式 dump，保留 7 天
#   3. 恢复到旁边的库 acquilang_db_incoming，核对 alembic / 表数 / 用户数
#   4. 核对通过后，把 acquilang_db 改名为 acquilang_db_prev，再把 incoming 改名为 acquilang_db
#
# 回滚到上一份开发库（切换后的几小时内，prev 还在）：
#   docker exec acquilang-postgres psql -U acquilang_user -d postgres -c \
#     "ALTER DATABASE acquilang_db RENAME TO acquilang_db_failed;"
#   docker exec acquilang-postgres psql -U acquilang_user -d postgres -c \
#     "ALTER DATABASE acquilang_db_prev RENAME TO acquilang_db;"
# 更早的开发库用 ~/backups/acquilang-dev-before-sync/ 里的 dump，pg_restore 回去。
#
# 手动跑：
#   ~/stacks/acquilang-postgres/sync-from-prod.sh

set -euo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export DOCKER_HOST="${DOCKER_HOST:-unix:///Users/konghai/.colima/default/docker.sock}"
export HOME="${HOME:-/Users/konghai}"

STACK="$HOME/stacks/acquilang-postgres"
BACKUP_DIR="$HOME/backups/acquilang-dev-before-sync"
WORK_DIR="$STACK/sync-work"
LOCK_DIR="$STACK/sync.lockdir"
CONTAINER="acquilang-postgres"
DB_USER="acquilang_user"
KEEP_DAYS=7

umask 077

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  log "ERROR $*"
  exit 1
}

psql_admin() {
  docker exec -i "$CONTAINER" psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -Atq "$@"
}

mkdir -p "$BACKUP_DIR" "$WORK_DIR" "$HOME/Library/Logs"
chmod 700 "$BACKUP_DIR" "$WORK_DIR"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  oldpid="$(cat "$LOCK_DIR/pid" 2>/dev/null || true)"
  if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
    log "已有同步在跑 (pid $oldpid)，这次退出"
    exit 0
  fi
  log "清掉过期锁 (pid ${oldpid:-unknown})"
  rm -rf "$LOCK_DIR"
  mkdir "$LOCK_DIR"
fi
echo $$ > "$LOCK_DIR/pid"

CLEAN_INCOMING=1
RENAME_STARTED=0
cleanup() {
  status=$?
  if [ "$status" -ne 0 ] && [ "$RENAME_STARTED" = 1 ]; then
    has_live="$(docker exec -i "$CONTAINER" psql -U "$DB_USER" -d postgres -Atq -c "SELECT 1 FROM pg_database WHERE datname = 'acquilang_db'" 2>/dev/null || true)"
    has_prev="$(docker exec -i "$CONTAINER" psql -U "$DB_USER" -d postgres -Atq -c "SELECT 1 FROM pg_database WHERE datname = 'acquilang_db_prev'" 2>/dev/null || true)"
    if [ "$has_live" != "1" ] && [ "$has_prev" = "1" ]; then
      log "切换中断，把 acquilang_db_prev 改回 acquilang_db"
      docker exec -i "$CONTAINER" psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -c \
        "ALTER DATABASE acquilang_db_prev RENAME TO acquilang_db;" >/dev/null 2>&1 || true
    fi
  fi
  if [ "$CLEAN_INCOMING" = 1 ] && [ "$RENAME_STARTED" = 0 ]; then
    docker exec -i "$CONTAINER" psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -c \
      "DROP DATABASE IF EXISTS acquilang_db_incoming;" >/dev/null 2>&1 || true
  fi
  docker exec "$CONTAINER" rm -f /tmp/acquilang-prod.dump >/dev/null 2>&1 || true
  rm -rf "$LOCK_DIR"
  if [ "$status" -ne 0 ]; then
    log "同步失败，开发库应仍是切换前的内容"
  fi
  exit "$status"
}
trap cleanup EXIT

log "开始同步"
health="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$CONTAINER" 2>/dev/null || true)"
[ "$health" = "healthy" ] || die "容器 $CONTAINER 不是 healthy（当前: ${health:-missing}）"

avail_kb="$(df -k "$HOME" | awk 'NR==2 { print $4 }')"
[ "${avail_kb:-0}" -gt 2097152 ] || die "磁盘剩余不足 2GB"

DUMP="$WORK_DIR/prod.dump"
META="$WORK_DIR/prod.meta"
rm -f "$DUMP" "$META"

log "从 nyh-prod 只读导出生产库"
ssh -o BatchMode=yes -o ConnectTimeout=20 -o ServerAliveInterval=30 -o ServerAliveCountMax=10 \
  nyh-prod bash -s >"$DUMP" 2>"$META" << 'REMOTE'
set -euo pipefail
umask 077
envfile=/dev/shm/acquilang-sync.env
rm -f "$envfile"
trap 'rm -f /dev/shm/acquilang-sync.env' EXIT
python3 - "$envfile" << 'PY'
import os, re, sys
path = sys.argv[1]
text = open("/www/wwwroot/python/backup-rds.sh").read()
def get(key):
    match = re.search(rf'^{key}="([^"]*)"', text, re.M)
    if not match:
        raise SystemExit("missing " + key)
    return match.group(1)
with open(path, "w") as handle:
    handle.write("PGPASSWORD=" + get("DB_PASS") + "\n")
    handle.write("PGHOST=" + get("DB_HOST") + "\n")
    handle.write("PGPORT=" + get("DB_PORT") + "\n")
    handle.write("PGUSER=" + get("DB_USER") + "\n")
    handle.write("PGDATABASE=" + get("DB_NAME") + "\n")
os.chmod(path, 0o600)
PY
docker run --rm --network host --env-file "$envfile" postgres:18.6-alpine \
  sh -eu -c 'alembic=$(psql -Atq -c "SELECT version_num FROM alembic_version"); tables=$(psql -Atq -c "SELECT count(*) FROM pg_tables WHERE schemaname = '\''public'\''"); users=$(psql -Atq -c "SELECT count(*) FROM users"); echo "SYNC_META alembic=${alembic} tables=${tables} users=${users}" >&2; exec pg_dump -Fc --no-owner --no-privileges'
REMOTE

meta_line="$(grep -E '^SYNC_META ' "$META" | tail -n 1 || true)"
[ -n "$meta_line" ] || die "没有拿到生产库核对信息。远程输出见 $META"
# shellcheck disable=SC2086
set -- $meta_line
alembic=""; tables=""; users=""
for item in "$@"; do
  case "$item" in
    alembic=*) alembic="${item#alembic=}" ;;
    tables=*) tables="${item#tables=}" ;;
    users=*) users="${item#users=}" ;;
  esac
done
[ -n "$alembic" ] && [ -n "$tables" ] && [ -n "$users" ] || die "核对信息不完整: $meta_line"
[[ "$tables" =~ ^[0-9]+$ ]] || die "表数量不是数字: $tables"
[[ "$users" =~ ^[0-9]+$ ]] || die "用户数量不是数字: $users"
[ "$tables" -ge 60 ] || die "生产库 public 表只有 ${tables}，停止"
[ "$users" -ge 1 ] || die "生产库 users 为空，停止"

magic="$(dd if="$DUMP" bs=5 count=1 2>/dev/null || true)"
[ "$magic" = "PGDMP" ] || die "生产 dump 不是 PostgreSQL 自定义格式"
dump_bytes="$(wc -c < "$DUMP" | tr -d ' ')"
[ "$dump_bytes" -gt 1000000 ] || die "生产 dump 过小 (${dump_bytes} bytes)"
log "生产库 alembic=$alembic tables=$tables users=$users dump=${dump_bytes} bytes"

stamp="$(date '+%Y%m%d_%H%M%S')"
dev_backup="$BACKUP_DIR/acquilang_db_${stamp}.dump"
log "备份当前开发库到 $dev_backup"
docker exec "$CONTAINER" pg_dump -U "$DB_USER" -d acquilang_db -Fc --no-owner --no-privileges > "$dev_backup"
dev_magic="$(dd if="$dev_backup" bs=5 count=1 2>/dev/null || true)"
[ "$dev_magic" = "PGDMP" ] || die "开发库备份不是 PostgreSQL 自定义格式"
dev_bytes="$(wc -c < "$dev_backup" | tr -d ' ')"
[ "$dev_bytes" -gt 100000 ] || die "开发库备份过小 (${dev_bytes} bytes)"

log "恢复到 acquilang_db_incoming"
psql_admin -c "DROP DATABASE IF EXISTS acquilang_db_incoming;" >/dev/null
psql_admin -c "CREATE DATABASE acquilang_db_incoming OWNER ${DB_USER} TEMPLATE template0 ENCODING 'UTF8';" >/dev/null
docker cp "$DUMP" "$CONTAINER":/tmp/acquilang-prod.dump
docker exec "$CONTAINER" pg_restore -U "$DB_USER" -d acquilang_db_incoming \
  --no-owner --no-privileges --exit-on-error --single-transaction /tmp/acquilang-prod.dump
docker exec "$CONTAINER" rm -f /tmp/acquilang-prod.dump

restored="$(docker exec -i "$CONTAINER" psql -U "$DB_USER" -d acquilang_db_incoming -v ON_ERROR_STOP=1 -Atq << 'SQL'
SELECT version_num FROM alembic_version;
SELECT count(*) FROM pg_tables WHERE schemaname = 'public';
SELECT count(*) FROM users;
SQL
)"
restored_alembic="$(printf '%s\n' "$restored" | sed -n '1p')"
restored_tables="$(printf '%s\n' "$restored" | sed -n '2p')"
restored_users="$(printf '%s\n' "$restored" | sed -n '3p')"
[ "$restored_alembic" = "$alembic" ] || die "恢复后的 alembic 是 $restored_alembic，生产是 $alembic"
[ "$restored_tables" = "$tables" ] || die "恢复后的表数是 ${restored_tables}，生产是 ${tables}"
[ "$restored_users" -ge 1 ] || die "恢复后的用户数是 $restored_users"
if [ "$restored_users" != "$users" ]; then
  log "WARN 用户数以 dump 为准：恢复后 ${restored_users}，导出前查询 ${users}"
fi
log "恢复核对通过"

db_exists() {
  local found
  found="$(psql_admin -c "SELECT 1 FROM pg_database WHERE datname = '$1'")"
  [ "$found" = "1" ]
}

terminate_db() {
  docker exec -i "$CONTAINER" psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -c \
    "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$1' AND pid <> pg_backend_pid();" >/dev/null
}

log "切换数据库名"
if db_exists acquilang_db && db_exists acquilang_db_prev; then
  terminate_db acquilang_db_prev || true
  psql_admin -c "DROP DATABASE acquilang_db_prev;" >/dev/null
fi

swap_ok=0
for _ in 1 2 3 4 5 6 7 8 9 10; do
  terminate_db acquilang_db || true
  terminate_db acquilang_db_incoming || true
  if db_exists acquilang_db && db_exists acquilang_db_incoming; then
    RENAME_STARTED=1
    if ! psql_admin -c "ALTER DATABASE acquilang_db RENAME TO acquilang_db_prev;" >/dev/null; then
      sleep 1
      continue
    fi
  fi
  if ! db_exists acquilang_db && db_exists acquilang_db_prev && db_exists acquilang_db_incoming; then
    RENAME_STARTED=1
    if psql_admin -c "ALTER DATABASE acquilang_db_incoming RENAME TO acquilang_db;" >/dev/null; then
      swap_ok=1
      break
    fi
  fi
  if db_exists acquilang_db && db_exists acquilang_db_prev && ! db_exists acquilang_db_incoming; then
    swap_ok=1
    break
  fi
  sleep 1
done
[ "$swap_ok" = 1 ] || die "切换数据库名失败"
CLEAN_INCOMING=0

live="$(docker exec -i "$CONTAINER" psql -U "$DB_USER" -d acquilang_db -Atq -c "SELECT version_num FROM alembic_version;")"
[ "$live" = "$alembic" ] || die "切换后 acquilang_db 的 alembic 是 ${live}，期望 ${alembic}"

find "$BACKUP_DIR" -name 'acquilang_db_*.dump' -type f -mtime +"$KEEP_DAYS" -delete
rm -f "$DUMP" "$META"
log "完成。acquilang_db 现为生产内容 alembic=${live} users=${users}。上一份开发库在 acquilang_db_prev，dump 为 ${dev_backup}"
