#!/usr/bin/env bash
# mas-go-dev 数据基准采集（AL2023 → Debian 13 迁移用，见
# docs/plans/2026-10-31-1418-ops-mas-go-dev-debian13-migration-plan.md 的 Verification Contract）。
#
# 只读：在新旧机上各跑一次，输出可直接 diff 的纯文本。
#   ssh mas-go-dev 'sudo bash -s' < scripts/mas-go-dev-data-baseline.sh > before.txt
#
# 覆盖：
#   - shared-sit PostgreSQL：每个库大小（仅参考）+ 每张用户表的精确行数
#   - Garage：各 bucket 对象数
#   - Redis（iCare redis、shared-sit-redis）：各 DB 的 keys / expires / keys-expires
#   - azurite：容器列表与 blob 数（读 LokiJS 元数据文件，不需要账号密钥）
# 不打印任何密码；shared-sit-redis 的密码从服务器 .env 读入环境变量后只传给 redis-cli。
set -uo pipefail

echo "## postgres"
databases="$(docker exec shared-sit-postgres psql -U postgres -Atc \
  "select datname from pg_database where not datistemplate order by 1")"
for database in $databases; do
  docker exec shared-sit-postgres psql -U postgres -d "$database" -Atc "
    select '$database' || '|' || table_schema || '.' || table_name || '|' ||
      (xpath('/row/c/text()', query_to_xml(
        format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text
    from information_schema.tables
    where table_type = 'BASE TABLE'
      and table_schema not in ('pg_catalog', 'information_schema')
    order by table_schema, table_name"
done

echo "## garage"
docker exec shared-sit-s3 /garage bucket list 2>/dev/null \
  | awk 'NR>1 && $3!="" {print $3}' | while read -r bucket; do
    objects="$(docker exec shared-sit-s3 /garage bucket info "$bucket" 2>/dev/null \
      | awk -F: '/^Objects/ {gsub(/ /,"",$2); print $2}')"
    echo "garage|$bucket|objects=$objects"
  done

echo "## redis"
print_keyspace() {
  local label="$1"; shift
  "$@" INFO keyspace 2>/dev/null | tr -d '\r' | grep '^db' | while IFS=: read -r db stats; do
    keys="$(echo "$stats" | sed -E 's/.*keys=([0-9]+).*/\1/')"
    expires="$(echo "$stats" | sed -E 's/.*expires=([0-9]+).*/\1/')"
    echo "$label|$db|keys=$keys|expires=$expires|persistent=$((keys - expires))"
  done
}
print_keyspace icare-redis docker exec redis redis-cli
shared_redis_password="$(grep '^REDIS_PASSWORD=' /opt/shared-sit/redis/.env | cut -d= -f2-)"
print_keyspace shared-sit-redis docker exec -e REDISCLI_AUTH="$shared_redis_password" shared-sit-redis redis-cli

echo "## azurite"
python3 - <<'PY'
import json
with open('/var/lib/docker/volumes/icare-backend-infra_azurite-data/_data/__azurite_db_blob__.json') as fh:
    collections = {c['name']: c.get('data', []) for c in json.load(fh)['collections']}
for container in sorted(c['name'] for c in collections['$CONTAINERS_COLLECTION$']):
    blob_count = sum(1 for b in collections['$BLOBS_COLLECTION$'] if b.get('containerName') == container)
    print(f"azurite|{container}|blobs={blob_count}")
PY
