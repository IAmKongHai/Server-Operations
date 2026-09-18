#!/usr/bin/env bash
# new-api 数据库每日备份
# 服务器路径：/home/ec2-user/stacks/new-api/new-api-backup.sh（chmod 750）
#
# 单独成脚本而非写在 ExecStart 里：systemd 的 ExecStart 不经 shell，
# 不支持重定向与 find 管道，写在单元里会静默不生效。
set -euo pipefail

BACKUP_DIR=/home/ec2-user/backups/new-api
KEEP=14

mkdir -p "$BACKUP_DIR"
DUMP_FILE="$BACKUP_DIR/new_api-$(date -u +%Y%m%d).dump"

# 只导 new_api 一个库，不碰共享库上的其它租户。
# -Fc 自定义格式，可用 pg_restore --list 校验与选择性恢复。
# PGPASSWORD 由 systemd 的 EnvironmentFile（600，只含这一行）注入本脚本环境，
# 再用 -e 透传进容器，不出现在命令行与进程列表里。
: "${PGPASSWORD:?PGPASSWORD 未设置，检查 /home/ec2-user/stacks/new-api/backup.env}"
docker exec -e PGPASSWORD -i shared-postgres \
  pg_dump -U new_api -Fc -d new_api > "$DUMP_FILE.tmp"

# 先写 .tmp 再改名：中途失败不会留下一个看着像成功的半截备份
mv "$DUMP_FILE.tmp" "$DUMP_FILE"
chmod 600 "$DUMP_FILE"

# 滚动保留最近 KEEP 份，多余的按文件名（即日期）倒序删除
ls -1t "$BACKUP_DIR"/new_api-*.dump 2>/dev/null | tail -n +$((KEEP + 1)) | while read -r old; do
  rm -f -- "$old"
  echo "removed old backup: $old"
done

echo "backup ok: $DUMP_FILE ($(du -h "$DUMP_FILE" | cut -f1))"
