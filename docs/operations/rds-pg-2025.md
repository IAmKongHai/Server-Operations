# RDS-Pg-2025 运维时间线

阿里云香港 PostgreSQL RDS `pgm-j6cf5kaej216sx0z`（控制台名 **RDS-Pg-2025**）。应用从 `nyh-prod`（`172.31.138.210`）经 VPC 访问内网 `172.31.138.209:5432`。

## 2026-09-14 16:08–16:32 CST - 卸 TimescaleDB 后本地升级到 PostgreSQL 18，再装回 2.24.0

- 服务器：阿里云 RDS `pgm-j6cf5kaej216sx0z`（RDS-Pg-2025）
- 操作人：`Grok`（用户确认可停服；走「先卸扩展 → 升 PG18 → 再安装」）
- 原因：TimescaleDB 2.17.0 无法在 PG17 上 `ALTER EXTENSION UPDATE` 到 2.24（`pg_init_privs` 权限 + 控制台「升级版本」无效），卡住 PG18 预检查。
- 影响：16:08–16:13 卸扩展（`market_candles` 先拷成普通表）。16:18–16:31 本地大版本升级，实例 `Transing`，连接地址不变，包年包月保留。`richer_go_db` 与其它库一起升到 18.4。
- 备份：手动快照 `BackupId 4001679489`（2026-09-14 16:09–16:12 CST，Job `561015`）。另有卸扩展前的表拷贝 `market_candles` 143969 行。
- 回滚方式：大版本升级不可降回。只能用快照 `4001679489`（升级前、仍为 PG17 + 已拷贝的普通表）做实例级恢复。

### 变更时序

1. 确认 `public.market_candles` 为 hypertable（`time` timestamptz，chunk 7 天，49 chunks，无压缩/无 cagg，143969 行 / 43 MB，时间范围 2025-03-13～2026-02-18）。当时无业务会话。
2. 手动 Snapshot 备份成功后，`CREATE TABLE market_candles_plain` 并 `INSERT … SELECT`，行数 143969=143969。
3. `DROP TABLE market_candles`（hypertable）→ 将 plain 表改回 `market_candles` 并补 PK / UNIQUE → `DROP EXTENSION timescaledb`（无 CASCADE）。`pg_proc` 不再引用 timescaledb 库。
4. `UpgradeDBInstanceMajorVersionPrecheck` 目标 `18.0` / `inPlaceUpgrade`，TaskId `54854424`，**Success**（不再有 loadable_libraries fatal）。
5. `UpgradeDBInstanceMajorVersion` 本地升级、立即割接。TaskId `54854430`。16:31 CST `Running`，内核 `rds_postgres_1800_20260830`，`version()` = PostgreSQL **18.4**。计费仍 Prepaid。
6. `shared_preload_libraries` 仍含 `timescaledb`。在 `ddricher_db_prod`：`CREATE EXTENSION timescaledb`（**2.24.0**）→ `create_hypertable(..., chunk_time_interval => '7 days', migrate_data => true)`。仍 49 chunks、143969 行、相同 min/max。

### 验证

- `EngineVersion=18.0`，`CurrentKernelVersion=rds_postgres_1800_20260830`，`DBInstanceStatus=Running`
- `ddricher_db_prod`：`timescaledb 2.24.0`（默认 2.24.0），`uuid-ossp 1.1` 仍在
- `market_candles` hypertable 49 chunks / 143969 行
- `richer_go_db` 可连，`version()` 为 PostgreSQL 18.4

### 后续

应用侧确认读写 `market_candles` 与其它库。TimescaleDB 2.24 对 `varchar` 列有 best-practice 警告，未改列类型。

## 2026-09-14 15:17–15:49 CST - 升级内核到 20260830；TimescaleDB 目录仍为 2.17.0

- 服务器：阿里云 RDS `pgm-j6cf5kaej216sx0z`（RDS-Pg-2025，`cn-hongkong-d`）
- 操作人：`Grok`（用户确认走路径 A：先把 TimescaleDB 升到 2.24，为 PG17→18 大版本升级预检查扫 fatal）
- 原因：大版本升级预检查 `loadable_libraries.txt` fatal：`ddricher_db_prod` 引用 `$libdir/timescaledb-2.17.0`，PG18 只带 TimescaleDB 2.24.0。
- 影响：内核升级期间实例约 15:17–15:21 CST 处于 `EngineVersionUpgrading`，短暂中断。随后几次 `UpdatePostgresExtensions` 把实例打成短暂 `InstanceMaintaining`（杀掉 TimescaleDB background worker 后拉起）。`ddricher_db_prod.public.market_candles` hypertable（49 chunks）仍在，未删扩展。
- 备份：升级前最近一次自动快照 `BackupId 4001668109`（2026-09-13 17:47 CST，FullBackup Snapshot）。日志备份开启，保留 7 天。未另开手动备份。
- 回滚方式：内核小版本不能降回去。只能按快照 `4001668109`（或之后的自动快照）做实例级恢复。不要 `DROP EXTENSION timescaledb CASCADE`（会丢掉 `market_candles`）。

### 变更时序

1. 确认当前内核 `rds_postgres_1700_20260130`（社区 17.7），最新 `rds_postgres_1700_20260830`。`shared_preload_libraries` 已含 `timescaledb`。仅 `ddricher_db_prod` 安装了 TimescaleDB **2.17.0**（owner `ddricher_prod_user`）。
2. `UpgradeDBInstanceKernelVersion`，目标 `rds_postgres_1700_20260830`，`UpgradeTime=Immediate`。TaskId `54854356`。15:21 CST 回到 `Running`，`version()` 为 PostgreSQL **17.10**。此时 `pg_available_extensions` 默认 TimescaleDB **2.24.0**，已安装仍是 **2.17.0**。
3. `UpdatePostgresExtensions`（无 `AccountName`）立刻返回 RequestId，目录未变。
4. 从 `nyh-prod` 用 `ddricher_prod_user` 执行 `ALTER EXTENSION timescaledb UPDATE;`：脚本已开始跑（`WARNING: job history configuration modified`），随后 `ERROR: permission denied for table pg_init_privs`，事务回滚，版本仍 2.17.0。
5. 再调 `UpdatePostgresExtensions`（带/不带 `AccountName`）以及 `CreatePostgresExtensions`。实例短暂 `InstanceMaintaining`，`alicloud_rds_admin` 连上 `ddricher_db_prod` 但错误日志里没有它执行的 `ALTER EXTENSION`；目录仍 2.17.0。

### 验证

- 内核：`CurrentKernelVersion=rds_postgres_1700_20260830`，`DBInstanceStatus=Running`。
- `SELECT extversion FROM pg_extension WHERE extname='timescaledb'` → **2.17.0**（未达标）。
- `pg_extension_update_paths('timescaledb')` 存在路径 `2.17.0--2.24.0`。
- hypertable `public.market_candles` 仍 49 chunks。
- `pg_proc.probin` 仍指向 `$libdir/timescaledb-2.17.0`。

### 后续

目录升级必须由真正的 `rolsuper`（`alicloud_rds_admin`）执行 `ALTER EXTENSION timescaledb UPDATE;`。高权限账号属于 `pg_rds_superuser`，不是 superuser。下一步：控制台 **插件管理 → 已安装插件 → timescaledb → 升级版本**；若仍失败，提工单让阿里云用 `alicloud_rds_admin` 跑这条 SQL。完成后再重跑 PG18 升级检查。
