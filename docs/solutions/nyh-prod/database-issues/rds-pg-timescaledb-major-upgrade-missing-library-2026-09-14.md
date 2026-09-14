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

实例 `pgm-j6cf5kaej216sx0z`（RDS-Pg-2025，香港，基础系列）。要从 PostgreSQL 17 升到 18。预检查只在 `ddricher_db_prod` 失败。该库有 TimescaleDB，且有 hypertable `public.market_candles`（49 chunks）。原地 `ALTER EXTENSION UPDATE` 升到 2.24 失败后，改为：把 hypertable 拷成普通表 → 卸扩展 → 升 PG18 → 再装 TimescaleDB 2.24.0 并 `create_hypertable`。

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

## 实际处理（2026-09-14）

控制台「升级版本」和 DMS 都走不通之后，用户确认可停服，改为卸扩展再升大版本：

1. 手动快照 `BackupId 4001679489`。
2. 把 `market_candles` 拷到普通表（143969 行对齐），再 `DROP TABLE` hypertable、改回原名并补 PK/UNIQUE，然后 `DROP EXTENSION timescaledb`（**不要 CASCADE**）。
3. 预检查 `18.0` / `inPlaceUpgrade` 变为 Success。
4. 本地升级立即割接，实例升到 PostgreSQL **18.4**（内核 `rds_postgres_1800_20260830`），连接串与包年包月不变。
5. `CREATE EXTENSION timescaledb` → **2.24.0**，`create_hypertable(..., chunk_time_interval => '7 days', migrate_data => true)`。仍是 49 chunks、143969 行。

`shared_preload_libraries` 升级前后都含 `timescaledb`，装扩展无需再改参数。

## 不要做

- 指望 PG18 自带 `timescaledb-2.17.0.so`。
- 用高权限账号硬跑 `ALTER EXTENSION`（会失败，已验证回滚）。
- 未迁走 `market_candles` 就 `DROP EXTENSION … CASCADE`。
- 用 DMS 当 superuser：DMS 账号同样不是 `alicloud_rds_admin`。
