#!/usr/bin/env bash
# sub2api 数据库每日备份
# 服务器路径：/home/ec2-user/stacks/sub2api/sub2api-backup.sh（chmod 750）
#
# 单独成脚本而非写在 ExecStart 里：systemd 的 ExecStart 不经 shell，
# 不支持重定向与 find 管道，写在单元里会静默不生效。
set -euo pipefail

BACKUP_DIR=/home/ec2-user/backups/sub2api
KEEP=14

mkdir -p "$BACKUP_DIR"
DUMP_FILE="$BACKUP_DIR/sub2api-$(date -u +%Y%m%d).dump"

# 只导 sub2api 一个库，不碰共享库上的其它租户。
# PGPASSWORD 由 systemd 的 EnvironmentFile（600）注入，再用 -e 透传进容器。
: "${PGPASSWORD:?PGPASSWORD 未设置，检查 /home/ec2-user/stacks/sub2api/backup.env}"
docker exec -e PGPASSWORD -i shared-postgres \
  pg_dump -U sub2api -Fc -d sub2api > "$DUMP_FILE.tmp"

mv "$DUMP_FILE.tmp" "$DUMP_FILE"
chmod 600 "$DUMP_FILE"

ls -1t "$BACKUP_DIR"/sub2api-*.dump 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -f -- "$old"
  echo "removed old backup: $old"
done

echo "backup ok: $DUMP_FILE ($(du -h "$DUMP_FILE" | cut -f1))"
