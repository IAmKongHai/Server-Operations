#!/usr/bin/env bash
# mas-go-dev 数据基准采集（AL2023 → Debian 13 迁移用，见
# docs/plans/2026-10-31-1418-ops-mas-go-dev-debian13-migration-plan.md 的 Verification Contract）。
#
# 只读：在新旧机上各跑一次，输出可直接 diff 的纯文本。
#   ssh mas-sit 'sudo bash -s' < scripts/mas-go-dev-data-baseline.sh > before.txt
#
# 覆盖：
#   - shared-sit PostgreSQL：每张用户表的精确行数
#   - Garage：各 bucket 对象数
#   - Redis（iCare redis、shared-sit-redis）：PING 结果 + 各 DB 的 keys / expires / keys-expires
#   - azurite：容器列表与 blob 数（读 LokiJS 元数据文件，不需要账号密钥）
#
# 这是迁移的校验闸门：任何一段采集失败或结果为空都以非零退出，
# 避免新旧两边同时失败时输出一致、diff 被空结果通过。
# 只比计数，不比内容；内容一致性另用 rsync -c -n 逐字节核对卷。
# 不打印任何密码；shared-sit-redis 的密码只经环境变量传给 redis-cli（不进 argv）。
set -uo pipefail

failures=0
fail() { echo "ERROR: $*" >&2; failures=$((failures + 1)); }

echo "## postgres"
if ! databases="$(docker exec shared-sit-postgres psql -U postgres -Atc \
    "select datname from pg_database where not datistemplate order by 1")" || [ -z "$databases" ]; then
  fail "postgres: cannot list databases"
fi
for database in $databases; do
  if ! table_counts="$(docker exec shared-sit-postgres psql -U postgres -d "$database" -Atc "
      select '$database' || '|' || table_schema || '.' || table_name || '|' ||
        (xpath('/row/c/text()', query_to_xml(
          format('select count(*) as c from %I.%I', table_schema, table_name), false, true, '')))[1]::text
      from information_schema.tables
      where table_type = 'BASE TABLE'
        and table_schema not in ('pg_catalog', 'information_schema')
      order by table_schema, table_name")"; then
    fail "postgres: cannot count tables in $database"
    continue
  fi
  # 空库（如 postgres）也要留一行，证明这个库被采集过
  echo "postgres|$database|tables=$(printf '%s' "$table_counts" | grep -c .)"
  [ -n "$table_counts" ] && echo "$table_counts"
done

echo "## garage"
if ! bucket_list="$(docker exec shared-sit-s3 /garage bucket list 2>/dev/null)"; then
  fail "garage: bucket list failed"
fi
# 第一列是 bucket ID（无别名的 bucket 也能列出），第三列是全局别名
bucket_ids="$(printf '%s\n' "$bucket_list" | awk 'NR>1 && $1 ~ /^[0-9a-f]+$/ {print $1 "|" $3}')"
[ -z "$bucket_ids" ] && fail "garage: no buckets parsed"
for entry in $bucket_ids; do
  bucket_id="${entry%%|*}"; alias="${entry#*|}"
  objects="$(docker exec shared-sit-s3 /garage bucket info "$bucket_id" 2>/dev/null \
    | awk -F: '/^Objects/ {gsub(/ /,"",$2); print $2}')"
  [ -z "$objects" ] && fail "garage: cannot read object count of $bucket_id"
  echo "garage|${alias:-$bucket_id}|objects=$objects"
done

echo "## redis"
print_keyspace() {
  local label="$1"; shift
  local pong keyspace
  pong="$("$@" PING 2>/dev/null | tr -d '\r')"
  if [ "$pong" != "PONG" ]; then
    fail "$label: PING returned '${pong:-<empty>}'"
    return
  fi
  echo "$label|ping=PONG"
  keyspace="$("$@" INFO keyspace 2>/dev/null | tr -d '\r' | grep '^db')"
  [ -z "$keyspace" ] && return   # 空 keyspace 是合法结果，PING 行已证明采集成功
  echo "$keyspace" | while IFS=: read -r db stats; do
    keys="$(echo "$stats" | sed -E 's/.*keys=([0-9]+).*/\1/')"
    expires="$(echo "$stats" | sed -E 's/.*expires=([0-9]+).*/\1/')"
    echo "$label|$db|keys=$keys|expires=$expires|persistent=$((keys - expires))"
  done
}
print_keyspace icare-redis docker exec redis redis-cli
REDISCLI_AUTH="$(grep '^REDIS_PASSWORD=' /opt/shared-sit/redis/.env | cut -d= -f2-)"
export REDISCLI_AUTH
print_keyspace shared-sit-redis docker exec -e REDISCLI_AUTH shared-sit-redis redis-cli
unset REDISCLI_AUTH

echo "## azurite"
if ! python3 - <<'PY'
import json
with open('/var/lib/docker/volumes/icare-backend-infra_azurite-data/_data/__azurite_db_blob__.json') as fh:
    collections = {c['name']: c.get('data', []) for c in json.load(fh)['collections']}
for container in sorted(c['name'] for c in collections['$CONTAINERS_COLLECTION$']):
    blob_count = sum(1 for b in collections['$BLOBS_COLLECTION$'] if b.get('containerName') == container)
    print(f"azurite|{container}|blobs={blob_count}")
PY
then
  fail "azurite: cannot read metadata"
fi

if [ "$failures" -gt 0 ]; then
  echo "BASELINE INCOMPLETE: $failures section(s) failed" >&2
  exit 1
fi
