#!/bin/bash
# nyh-prod → nyh-prod-2026 切换（计划 U5），旧机这一侧。在 nyh-prod 上以 root 执行。
#
# 做的事：停掉旧机所有会写数据的进程（定时任务、队列、有定时逻辑的容器），
# 存一份宝塔 Redis 快照，做最后一次增量同步。nginx / php-fpm / nyh-wechat-mp 继续运行，
# 接住 DNS 切换期间还会打到旧机的请求（它们共用同一个 RDS，短时间内两边都能正常响应）。
#
# 回滚（22:30 前）：bash /root/cutover-20261110/rollback-old.sh（本脚本会生成）
set -uo pipefail
B=/root/cutover-20261110
mkdir -p "$B"
log() { echo "[$(date '+%F %T')] $*" | tee -a "$B/cutover-old.log"; }

STATEFUL_CONTAINERS="yunshu-api acquilang-backend richer-engine-1 richer-gateway-1 archery"

log "== 0. 备份当前状态"
crontab -l > "$B/root.crontab"
cp -a /www/server/panel/data/db/crontab.db "$B/" 2>/dev/null
supervisorctl status > "$B/supervisor.before.txt"
docker ps -a --format '{{.Names}} {{.Status}}' > "$B/docker.before.txt"
for c in $STATEFUL_CONTAINERS; do echo "$c $(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$c")"; done > "$B/restart-policy.before.txt"

cat > "$B/rollback-old.sh" <<ROLLBACK
#!/bin/bash
# 恢复旧机：定时任务、supervisor、容器、guagua-api
crontab "$B/root.crontab"
supervisorctl start all
while read -r c p; do docker update --restart="\$p" "\$c" >/dev/null; docker start "\$c"; done < "$B/restart-policy.before.txt"
systemctl enable --now guagua-api
supervisorctl status | grep -vc RUNNING
ROLLBACK
chmod 700 "$B/rollback-old.sh"

log "== 1. 停定时任务（root crontab 里所有任务行加 #CUTOVER# 前缀，含宝塔计划任务）"
crontab -l | awk '/^[[:space:]]*#/ || /^[A-Za-z_]+=/ || /^[[:space:]]*$/ {print; next} {print "#CUTOVER# " $0}' | crontab -
log "剩余启用的任务行：$(crontab -l | grep -cvE '^[[:space:]]*#|^[A-Za-z_]+=|^[[:space:]]*$')"

log "== 2. 停 supervisor 全部程序（PHP 队列、line-*、nyh-notify）"
supervisorctl stop all >> "$B/cutover-old.log" 2>&1
log "仍在运行：$(supervisorctl status | grep -c RUNNING)"

log "== 3. 停有定时逻辑 / 有本地状态的容器与服务"
for c in $STATEFUL_CONTAINERS; do docker update --restart=no "$c" >/dev/null; docker stop "$c" >/dev/null && log "stopped $c"; done
systemctl disable --now guagua-api 2>&1 | tail -1
log "guagua-api: $(systemctl is-active guagua-api)"

log "== 4. 宝塔 Redis 7480 快照（不停 Redis，旧机 PHP 在 DNS 切换期间还要用）"
P=$(awk '/^requirepass/{print $2}' /www/server/redis/redis.conf)
before=$(REDISCLI_AUTH="$P" /www/server/redis/src/redis-cli -p 7480 --no-auth-warning LASTSAVE)
REDISCLI_AUTH="$P" /www/server/redis/src/redis-cli -p 7480 --no-auth-warning BGSAVE >/dev/null
until [ "$(REDISCLI_AUTH="$P" /www/server/redis/src/redis-cli -p 7480 --no-auth-warning LASTSAVE)" != "$before" ]; do sleep 1; done
cp -a /www/server/redis/dump.rdb "$B/redis-7480-dump.rdb"
log "redis dump $(du -h "$B/redis-7480-dump.rdb" | cut -f1)"

log "== 5. 最后一次增量同步"
/root/migrate-rsync.sh >> "$B/cutover-old.log" 2>&1
rsync -a -e "ssh -i /root/.ssh/migrate_nyh2026 -o BatchMode=yes" "$B/redis-7480-dump.rdb" root@8.217.145.133:/root/redis-7480-dump.rdb </dev/null
log "== 旧机侧完成"
