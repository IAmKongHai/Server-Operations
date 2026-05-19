---
title: ClickHouse 诊断日志膨胀导致 dev-cypresso 磁盘压力升高
date: 2026-05-18
category: docs/solutions/dev-cypresso/runtime-errors
server: dev-cypresso
module: dev-cypresso / infra ClickHouse + MongoDB + cypresso-api
problem_type: runtime_error
component: tooling
symptoms:
  - 根分区 100G 一度使用约 71G，近期刚发生过日志占满磁盘
  - ClickHouse `system.trace_log`、`system.text_log` 等内部诊断表曾占用 6G+
  - ClickHouse 文件日志曾占用约 1.4G，并反复记录 `MEMORY_LIMIT_EXCEEDED`
  - `cypresso-api` 因 MongoDB 不可用反复正常退出，`RestartCount` 超过 600
root_cause: config_error
resolution_type: configuration
severity: high
tags: [clickhouse, mongodb, docker, journald, disk-full, log-retention, dev-cypresso]
---

# ClickHouse 诊断日志膨胀导致 dev-cypresso 磁盘压力升高

## Problem

dev-cypresso 的根盘是 100G。2026-05-18 排查时，低风险清理前根盘约 `71G used / 30G free`，主要增长源不再是业务数据，而是 ClickHouse 自身诊断日志和临时构建缓存。

清理后根盘回到约 `59G used / 42G free`，但如果不加保留策略，ClickHouse 内部日志表仍可能再次膨胀。

## Symptoms

- `docker system df -v` 显示 `shared_clickhouse_data` 曾约 7.4G、`shared_clickhouse_logs` 曾约 1.4G。
- ClickHouse 内部表清理前大头：
  - `system.trace_log` 约 5.04GiB
  - `system.text_log` 约 1.10GiB
  - `system.metric_log` 约 394MiB
  - `system.asynchronous_metric_log` 约 197MiB
- ClickHouse 日志反复出现后台 merge 的 `MEMORY_LIMIT_EXCEEDED`。
- `cypresso-api` `RestartCount` 超过 600，日志每轮重复初始化数据。
- `shared-mongodb` 长期 `health: starting`，并记录 `/data/configdb/keyfile` 缺失或无效。

## Root Cause

这次有两个叠加问题：

1. ClickHouse 资源和日志保留没有边界。
   - 原 compose 中 `shared-clickhouse` 只有 `mem_limit: 3g`，临时提升到 5G 后仍未固化到目标 8G。
   - 默认 ClickHouse server log 是 `trace` 级别，默认轮转为 `1000M x 10`。
   - `system.trace_log`、`system.text_log` 等 system log 表没有短 TTL，错误循环会快速放大磁盘占用。

2. `cypresso-api` 重启循环来自 MongoDB 配置问题。
   - `mongodb/mongodb-atlas-local:8.0` 镜像声明了 `/data/db` 和 `/data/configdb` 两个 volume。
   - compose 只挂载了 `shared_mongodb_data:/data/db`，未挂载已声明的 `shared_mongodb_config`。
   - `/data/configdb/keyfile` 落在匿名空 volume 中，或生成后属主/长度不符合 MongoDB 要求，导致 MongoDB 无法稳定启动。
   - `cypresso-api` 初始化后 ping MongoDB 超时，进程以 0 退出，被 `restart: unless-stopped` 反复拉起。

## What Changed

### ClickHouse

远端配置：`dev-cypresso:home/ec2-user/stacks/infra/docker-compose.yml`

- `shared-clickhouse` 内存限制从 5G 固化为 8G。
- 新增只读配置挂载：

```yaml
- ./clickhouse-config/zz-icare-retention.xml:/etc/clickhouse-server/config.d/zz-icare-retention.xml:ro
```

新增远端配置：`dev-cypresso:home/ec2-user/stacks/infra/clickhouse-config/zz-icare-retention.xml`

关键策略：

- ClickHouse server log 降为 `warning`。
- 文件日志轮转收敛到 `100M x 5`。
- `trace_log`、`text_log` 保留 3 天。
- `query_log`、`metric_log`、`asynchronous_metric_log`、`latency_log`、`processors_profile_log` 保留 7 天。
- `error_log` 保留 14 天。
- 对已存在的 system log 表执行了 `ALTER TABLE ... MODIFY TTL`，确保不是只对新表生效。

### journald

新增远端配置：`dev-cypresso:etc/systemd/journald.conf.d/99-disk-cap.conf`

```ini
[Journal]
SystemMaxUse=200M
SystemKeepFree=2G
MaxRetentionSec=7day
```

Docker daemon 已经有全局 `json-file` 上限：

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
```

`cypresso-ai` compose 中 `web` / `cypresso-api` / `cypresso-doc` 也已有更严格的 `10m x 3` 服务级上限，本次没有重启 Docker daemon。

### MongoDB

远端配置：`dev-cypresso:home/ec2-user/stacks/infra/docker-compose.yml`

- 给 `shared-mongodb` 挂载持久 config volume：

```yaml
- shared_mongodb_config:/data/configdb
```

- 在 `shared_mongodb_config` 中生成 MongoDB replica-set keyfile。
- keyfile 最终大小 684 bytes，权限 `400`，属主 `1000:1000`（镜像内 `mongod` 用户）。
- 覆盖镜像自带 healthcheck，改为直接 `mongosh ping`，避免 `/usr/local/bin/runner healthcheck` 长期 timeout。

```yaml
healthcheck:
  test:
    - CMD-SHELL
    - >-
      mongosh --quiet --username "$${MONGODB_INITDB_ROOT_USERNAME}" --password "$${MONGODB_INITDB_ROOT_PASSWORD}" --authenticationDatabase admin --eval 'db.adminCommand({ ping: 1 }).ok' | grep -q 1
  interval: 30s
  timeout: 10s
  retries: 5
  start_period: 60s
```

### Backups Created

远端备份文件：

- `dev-cypresso:home/ec2-user/stacks/infra/docker-compose.yml.bak-20260518062125-clickhouse-8g-retention`
- `dev-cypresso:home/ec2-user/stacks/infra/docker-compose.yml.bak-20260518062538-mongodb-configdb-keyfile`
- `dev-cypresso:home/ec2-user/stacks/infra/docker-compose.yml.bak-20260518063450-mongodb-healthcheck`
- `dev-cypresso:var/lib/docker/volumes/shared_mongodb_config/_data/keyfile.bak-20260518062749`

## Verification

Final observed state:

```text
/                  100G size, 59G used, 42G free, 59%
Mem available      ~8.8GiB
Swap used          ~1MiB / 4GiB
shared-clickhouse  healthy, 8GiB limit
shared-mongodb     healthy
cypresso-api       running, RestartCount stable at 697 after MongoDB fix
```

Functional checks:

```bash
ssh dev-cypresso "docker exec shared-clickhouse clickhouse-client --query 'SELECT 1'"
ssh dev-cypresso "docker exec shared-mongodb mongosh --quiet --eval 'db.adminCommand({ ping: 1 })'"
ssh dev-cypresso "curl -sS http://127.0.0.1:1989/"
```

Observed outputs:

- ClickHouse query returned `1`.
- MongoDB ping returned `ok: 1`.
- `cypresso-api` root endpoint returned HTTP 200 and body `Cypresso Studio API`.

Storage after fix:

| Path / volume | Size |
| --- | ---: |
| `shared_clickhouse_logs` | ~3.9M |
| `shared_clickhouse_data` | ~23M |
| `shared_mongodb_data` | ~550M |
| `shared_mongodb_config` | ~8K |
| `/var/log` | ~296M |

## Remaining Noise

`cypresso-api` is now stable, but it still logs an SQS error roughly every 5 seconds:

```text
runtime event consumer: receive failed ... AWS.SimpleQueueService.NonExistentQueue
```

This is not causing unbounded disk growth because the container has `json-file` rotation at `10m x 3`, but it is still an application configuration issue. Fix it separately by either provisioning the expected queue, correcting `RUNTIME_EVENT_QUEUE_URL`, or disabling the runtime event consumer for this environment.

## Backup / Cache Retention Candidates

Do not delete these without confirming restore value:

| File | Size | Date | Suggested handling |
| --- | ---: | --- | --- |
| `dev-cypresso:home/ec2-user/mssql-server-2022.tar` | ~1.53G | 2026-03-17 | Confirm whether still needed; likely removable if image exists elsewhere |
| `dev-cypresso:home/ec2-user/backups/sonarqube-community-branch-26.3.0.tar.gz` | ~1.05G | 2026-04-01 | Keep if plugin rollback still needed; otherwise archive/delete |
| `dev-cypresso:home/ec2-user/backups/CYP-327-mssql-fts-20260506-042202/medicalassistance_preprod.bak` | ~1.19G | 2026-05-06 | SQL backup; keep until restore chain is confirmed |
| `dev-cypresso:var/lib/docker/volumes/shared_sqlserver_data/_data/backup/CYP-327-mssql-fts-20260506-042202/medicalassistance_preprod.bak` | ~1.19G | 2026-05-06 | SQL backup inside volume; keep until restore chain is confirmed |
| `dev-cypresso:var/lib/docker/volumes/shared_sqlserver_data/_data/backup/medicalassistance_preprod_slim_20260318_005408.bak` | ~1.18G | 2026-03-17 | SQL backup; keep until restore chain is confirmed |
| `dev-cypresso:home/ec2-user/actions-runner/actions-runner-linux-x64-2.334.0.tar.gz` | ~215M | 2026-04-29 | Re-downloadable runner installer; removable after confirming runner install path |
| `dev-cypresso:home/ec2-user/.local/share/claude/versions/2.1.123` | ~236M | 2026-04-29 | Tool cache; removable if not actively used |

## Rollback

ClickHouse config rollback:

```bash
ssh dev-cypresso
cd /home/ec2-user/stacks/infra
cp docker-compose.yml.bak-20260518062125-clickhouse-8g-retention docker-compose.yml
docker-compose up -d clickhouse
```

MongoDB config rollback should be used only if the current healthy state regresses:

```bash
ssh dev-cypresso
cd /home/ec2-user/stacks/infra
cp docker-compose.yml.bak-20260518062538-mongodb-configdb-keyfile docker-compose.yml
docker-compose up -d mongodb
```

Note: rolling MongoDB back to the pre-fix compose reintroduces the missing `/data/configdb` persistence problem.

## Prevention

Use these checks during future disk investigations:

```bash
ssh dev-cypresso "df -h / && docker system df"
ssh dev-cypresso "sudo du -sh /var/lib/docker/volumes/shared_clickhouse_* /var/log"
ssh dev-cypresso "docker exec shared-clickhouse clickhouse-client --query \"SELECT database, table, formatReadableSize(sum(bytes_on_disk)) AS size, sum(rows) AS rows FROM system.parts WHERE active GROUP BY database, table ORDER BY sum(bytes_on_disk) DESC LIMIT 20\""
ssh dev-cypresso "docker inspect cypresso-api --format 'RestartCount={{.RestartCount}} Status={{.State.Status}} StartedAt={{.State.StartedAt}}'"
ssh dev-cypresso "docker ps --format 'table {{.Names}}\t{{.Status}}'"
```

Warning signs:

- Root disk over 80%.
- `shared_clickhouse_logs` grows beyond hundreds of MB.
- `system.trace_log` or `system.text_log` grows into hundreds of MB after TTL is enabled.
- `cypresso-api` RestartCount increases again.
- `shared-mongodb` is not healthy.

## Related

- `docs/solutions/dev-cypresso/integration-issues/docker-image-buildup-fills-disk-2026-05-14.md`
- `docs/solutions/nas/runtime-errors/docker-restart-policy-unless-stopped-trap-2026-05-13.md`
