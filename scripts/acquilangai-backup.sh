#!/bin/bash
#
# AcquiLangAI postgres (TimescaleDB) 每日备份脚本
# 由 crontab 触发，每日凌晨执行一次
#
# 设计要点：
#   1. TimescaleDB 不能用普通 pg_dump 干净恢复（hypertable / chunk 元数据不会还原），
#      所以本脚本采取"备份整个 docker volume"策略：tar 整个 /var/lib/postgresql/data
#   2. 容器在跑时先 docker stop 再 tar，保证快照一致；结束后 docker start
#   3. Colima 只挂载 ~/stacks，不能把 ~/backups 直接 bind 进容器。
#      tar 先写到 ~/stacks/acquilang-postgres/backup-stage，再 mv 到备份目录
#   4. 滚动保留 7 份
#
# 恢复方式（volume tar 路径）：
#   docker volume create acquilangai_postgres_data
#   # 把 tar 拷到 ~/stacks/acquilang-postgres/（Colima 可见）后解压进 volume
#   docker run --rm \
#     -v acquilangai_postgres_data:/dest \
#     -v "$HOME/stacks/acquilang-postgres:/src:ro" \
#     alpine sh -c 'tar --numeric-owner -xzf /src/acquilangai-YYYYMMDD.tar.gz -C /dest && rm -f /dest/postmaster.pid'
#   cd ~/stacks/acquilang-postgres && docker-compose up -d

set -euo pipefail

PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
DOCKER="$(command -v docker)"
BACKUP_DIR="$HOME/backups/acquilangai"
STAGE_DIR="$HOME/stacks/acquilang-postgres/backup-stage"
KEEP_COUNT=7
TIMESTAMP="$(date +%Y%m%d)"
TARGET="$BACKUP_DIR/acquilangai-$TIMESTAMP.tar.gz"
VOLUME_NAME="acquilangai_postgres_data"
LOCK_DIR="/tmp/acquilangai-backup.lock"
START_AFTER=""

mkdir -p "$BACKUP_DIR" "$STAGE_DIR"

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Another backup is already running (lock: $LOCK_DIR). Exiting." >&2
  exit 4
fi

cleanup() {
  if [ -n "$START_AFTER" ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Restarting containers: $START_AFTER"
    # shellcheck disable=SC2086
    echo "$START_AFTER" | xargs "$DOCKER" start || true
    START_AFTER=""
  fi
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting backup → $TARGET"

if [ -z "$DOCKER" ]; then
  echo "[ERROR] docker not found in PATH=$PATH" >&2
  exit 5
fi

if ! "$DOCKER" volume inspect "$VOLUME_NAME" >/dev/null 2>&1; then
  echo "[ERROR] Volume $VOLUME_NAME does not exist." >&2
  exit 2
fi

RUNNING_USERS="$("$DOCKER" ps --filter "volume=$VOLUME_NAME" --format '{{.Names}}')"
if [ -n "$RUNNING_USERS" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopping for consistent snapshot: $RUNNING_USERS"
  START_AFTER="$RUNNING_USERS"
  echo "$RUNNING_USERS" | xargs "$DOCKER" stop
fi

TMP_NAME="acquilangai-$TIMESTAMP.tar.gz.tmp"
"$DOCKER" run --rm \
  -v "$VOLUME_NAME":/data:ro \
  -v "$STAGE_DIR":/backup \
  alpine sh -c "cd /data && tar -czf /backup/$TMP_NAME ."

STAGE_TMP="$STAGE_DIR/$TMP_NAME"
if [ ! -f "$STAGE_TMP" ]; then
  echo "[ERROR] Staging backup missing: $STAGE_TMP" >&2
  exit 3
fi

SIZE="$(stat -f%z "$STAGE_TMP")"
if [ "$SIZE" -lt 1000000 ]; then
  echo "[ERROR] Backup file too small ($SIZE bytes). Aborting." >&2
  rm -f "$STAGE_TMP"
  exit 3
fi

mv "$STAGE_TMP" "$TARGET"
HUMAN_SIZE="$(ls -lh "$TARGET" | awk '{print $5}')"
echo "[$(date '+%Y-%m-%d %H:%M:%S')] Backup OK: $TARGET ($HUMAN_SIZE)"

cd "$BACKUP_DIR"
EXCESS="$(ls -t acquilangai-*.tar.gz 2>/dev/null | tail -n +"$((KEEP_COUNT + 1))" || true)"
if [ -n "$EXCESS" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Removing old backups:"
  echo "$EXCESS" | sed 's/^/  /'
  echo "$EXCESS" | xargs rm -f
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Current backups ($KEEP_COUNT slots):"
ls -lht acquilangai-*.tar.gz | head -n "$KEEP_COUNT" | awk '{print "  " $5 "\t" $9}'

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Done."
