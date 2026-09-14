# RDS-Pg-2025 运维时间线

阿里云香港 PostgreSQL RDS `pgm-j6cf5kaej216sx0z`（控制台名 **RDS-Pg-2025**）。应用从 `nyh-prod`（`172.31.138.210`）经 VPC 访问内网 `172.31.138.209:5432`。

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
