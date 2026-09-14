---
title: RDS PostgreSQL 大版本升级因 TimescaleDB 旧版 .so 预检查失败
date: 2026-09-14
category: docs/solutions/nyh-prod/database-issues
server: nyh-prod
module: 阿里云 RDS-Pg-2025 / TimescaleDB
problem_type: database_issue
component: database
severity: high
symptoms:
  - pg_upgrade 预检查 Checking for presence of required libraries fatal
  - loadable_libraries.txt 报 could not load library "$libdir/timescaledb-2.17.0"
  - 高权限账号 ALTER EXTENSION timescaledb UPDATE 报 permission denied for table pg_init_privs
root_cause: missing_permission
resolution_type: dependency_update
tags: [rds, postgresql, timescaledb, pg-upgrade, aliyun, ddricher]
---

# RDS PostgreSQL 大版本升级因 TimescaleDB 旧版 .so 预检查失败

## Context

实例 `pgm-j6cf5kaej216sx0z`（RDS-Pg-2025，香港，基础系列）。要从 PostgreSQL 17 升到 18。预检查只在 `ddricher_db_prod` 失败。该库有 TimescaleDB，且有 hypertable `public.market_candles`（49 chunks），不能删扩展。

## 原因

TimescaleDB 函数绑的是带版本号的库文件 `timescaledb-2.17.0.so`。`pg_upgrade` 要求新集群也能加载旧库。

| 侧 | TimescaleDB |
| --- | --- |
| PG17 内核 `20241030` 起 | 2.17.0 |
| PG17 内核 `20260330` 起 | 2.24 |
| PG18（官方插件表） | 2.24.0 |
| Timescale 官方矩阵 | 2.17–2.19 **不支持** PG18 |

RDS 不能往 PG18 镜像里塞 2.17.0 的 `.so`。必须先在 PG17 把扩展目录升到 2.24，再跑大版本检查。

官方路径与 PostGIS 同类问题相同：先升内核小版本，再 `ALTER EXTENSION … UPDATE`。

## 已做（2026-09-14）

1. 内核 `rds_postgres_1700_20260130` → `rds_postgres_1700_20260830`（社区 17.7 → 17.10）。实例已 Running。默认 TimescaleDB 变为 **2.24.0**。
2. 已安装版本仍是 **2.17.0**。`pg_extension_update_paths('timescaledb')` 有 `2.17.0--2.24.0`。
3. 高权限账号（`pg_rds_superuser`，`rolsuper=f`）执行 `ALTER EXTENSION timescaledb UPDATE;` 会进更新脚本，然后：

   ```text
   ERROR:  permission denied for table pg_init_privs
   ```

   事务回滚，目录不变。这是扩展脚本里的 `GRANT` 要写 `pg_catalog.pg_init_privs`，只有真正的 superuser（`alicloud_rds_admin` / `aurora`）能写。
4. 控制面 `UpdatePostgresExtensions` 返回 200 并把实例打成短暂 `InstanceMaintaining`（会杀掉 TimescaleDB background worker），错误日志里**没有** `alicloud_rds_admin` 执行的 `ALTER EXTENSION`。目录仍 2.17.0。

## 下一步（目录还没到 2.24）

必须让 `alicloud_rds_admin` 在 `ddricher_db_prod` 执行：

```sql
ALTER EXTENSION timescaledb UPDATE;
-- 或
ALTER EXTENSION timescaledb UPDATE TO '2.24.0';
```

可选做法：

1. 控制台 **插件管理 → 已安装插件 → timescaledb → 升级版本**（可能走和 OpenAPI 不同的内部任务）。
2. 工单请阿里云用 `alicloud_rds_admin` 跑上面的 SQL。
3. 不要 `DROP EXTENSION timescaledb CASCADE`。

完成后检查：

```sql
SELECT extversion FROM pg_extension WHERE extname = 'timescaledb';
-- 期望 2.24.0
SELECT DISTINCT probin FROM pg_proc WHERE probin LIKE '%timescaledb%';
-- 不应再出现 timescaledb-2.17.0
SELECT hypertable_name, num_chunks FROM timescaledb_information.hypertables;
```

然后重新跑 PG18 升级检查。`shared_preload_libraries` 里已有 `timescaledb`，升大版本后继续留着。

## 不要做

- 指望 PG18 自带 `timescaledb-2.17.0.so`。
- 用高权限账号硬跑 `ALTER EXTENSION`（会失败，已验证回滚）。
- 未迁走 `market_candles` 就 `DROP EXTENSION … CASCADE`。
