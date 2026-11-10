#!/bin/bash
# nyh-prod → nyh-prod-2026 切换（计划 U5），新机这一侧。旧机 cutover-old.sh 跑完后，在 nyh-prod-2026 上以 root 执行。
#
# 做的事：导入 Redis 快照，启动所有会写数据的进程（PHP 队列容器、宿主机 supervisor、
# 有定时逻辑的容器、guagua-api、cron）。之后由用户切 DNS。
#
# 回滚（22:30 前）：bash /root/cutover-20261110/rollback-new.sh（本脚本会生成）
set -uo pipefail
B=/root/cutover-20261110
mkdir -p "$B"
log() { echo "[$(date '+%F %T')] $*" | tee -a "$B/cutover-new.log"; }

cat > "$B/rollback-new.sh" <<'ROLLBACK'
#!/bin/bash
# 停掉新机上所有会写数据的进程，回到切换前状态（之后在旧机执行 rollback-old.sh、DNS 改回旧 IP）
sed -i 's/^\([^#A-Z].*\)$/#OFF# \1/' /etc/cron.d/nyh-tasks
docker stop php74-worker yunshu-api acquilang-backend richer-engine-1 richer-gateway-1 richer-web-1 2>/dev/null
supervisorctl stop all; systemctl disable --now supervisor
systemctl disable --now guagua-api nyh-wechat-mp-watchdog.timer
ROLLBACK
chmod 700 "$B/rollback-new.sh"

log "== 1. 导入宝塔 Redis 快照"
test -s /root/redis-7480-dump.rdb || { log "缺少 /root/redis-7480-dump.rdb，先跑旧机脚本"; exit 1; }
cd /opt/stacks/redis-7480 && docker compose stop >/dev/null 2>&1
install -o redis7480 -g redis7480 -m 600 /root/redis-7480-dump.rdb /opt/stacks/redis-7480/data/dump.rdb
docker compose up -d >/dev/null 2>&1; sleep 2
log "redis-7480 keyspace: $(docker exec -i redis-7480 sh -c 'REDISCLI_AUTH=$(awk "/^requirepass/{print \$2}" /usr/local/etc/redis/redis.conf) redis-cli -p 7480 --no-auth-warning INFO keyspace' </dev/null | grep -c '^db')个库"

log "== 2. 重启 archery（SQLite 已被最后一次同步覆盖）"
cd /www/wwwroot/Archery && docker compose restart >/dev/null 2>&1

log "== 3. PHP 队列容器 php74-worker"
cd /opt/stacks/php && docker compose --profile worker up -d php74-worker >/dev/null 2>&1

log "== 4. 宿主机 supervisor（10 个 line-* + nyh-notify）"
sed -i 's/^autostart=false/autostart=true/' /etc/supervisor/conf.d/*.conf
systemctl enable --now supervisor >/dev/null 2>&1; sleep 3
supervisorctl update >/dev/null 2>&1; supervisorctl start all >/dev/null 2>&1

log "== 5. 有定时逻辑的容器"
cd /www/yunshu/infra/prod && docker compose up -d --no-build >/dev/null 2>&1
cd /www/wwwroot/python/acquilang && docker compose -f docker-compose.prod.yml up -d --no-build --no-deps backend >/dev/null 2>&1
cd /www/wwwroot/ddricher/richer && docker compose -f docker-compose.prod.yml up -d --no-build gateway engine web >/dev/null 2>&1

log "== 6. systemd 服务"
systemctl enable --now guagua-api >/dev/null 2>&1
systemctl enable nyh-wechat-mp >/dev/null 2>&1
systemctl enable --now nyh-wechat-mp-watchdog.timer >/dev/null 2>&1

log "== 7. 启用定时任务"
sed -i 's/^#OFF# //' /etc/cron.d/nyh-tasks

log "== 状态"
sleep 10
{
  echo "-- php74-worker 内队列："; docker exec php74-worker supervisorctl status 2>&1 </dev/null
  echo "-- 宿主机 supervisor："; supervisorctl status
  echo "-- 容器："; docker ps --format '{{.Names}}\t{{.Status}}' | sort
  echo "-- 服务：guagua-api=$(systemctl is-active guagua-api) nyh-wechat-mp=$(systemctl is-active nyh-wechat-mp) watchdog=$(systemctl is-active nyh-wechat-mp-watchdog.timer)"
  echo "-- cron 启用行数：$(grep -cE '^[^#A-Z]' /etc/cron.d/nyh-tasks)"
} | tee -a "$B/cutover-new.log"
log "== 新机侧完成，可以切 DNS"
