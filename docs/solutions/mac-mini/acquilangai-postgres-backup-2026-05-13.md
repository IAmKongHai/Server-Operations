---
title: AcquiLangAI postgres (TimescaleDB) 每日备份方案
date: 2026-05-13
category: docs/solutions/mac-mini/workflow-issues
server: mac-mini
module: mac-mini / AcquiLangAI postgres
problem_type: workflow_issue
component: infrastructure
severity: medium
symptoms:
  - 项目暂时不运行（acquilang-postgres 容器 Exited 状态），数据在 docker volume 里
  - TimescaleDB 不能用普通 pg_dump 干净恢复（hypertable/chunk 元数据丢失，恢复时报 30 个错误）
  - 需要每日备份兜底，但不能让容器长期运行
root_cause: configuration_change
resolution_type: workflow_improvement
tags: [postgres, timescaledb, backup, docker-volume, acquilangai, mac-mini, cron]
---

# AcquiLangAI postgres (TimescaleDB) 每日备份方案

## Context

mac-mini 上的 AcquiLangAI 项目（语言学习 / 阅读行为分析）数据存于 docker volume `acquilangai_postgres_data`。容器 `acquilang-postgres-test` / `acquilang-postgres` 当前是 **Exited** 状态（项目暂时下线），但 volume 仍保留 149.8 MB 数据：

- 63 张表，包括 `llm_request_logs`、`reading_sessions`、`reading_behavior_events`、`lexemes`、`token_usage` 等
- 使用 TimescaleDB 扩展（基于 `timescale/timescaledb:latest-pg16`）
- 当前没有 hypertable 在用（`SELECT count(*) FROM timescaledb_information.hypertables` = 0），但扩展已安装且未来可能启用

## Why not just `pg_dump`

TimescaleDB 的 hypertable / chunk / continuous_agg 是通过 **`_timescaledb_catalog`** 元数据表自管理的。普通 `pg_dump` 会备份这些元数据表，但**恢复时新数据库的 TimescaleDB 扩展会创建自己的 `_timescaledb_catalog.dimension_slice_id_seq` 等序列**，与 dump 里 SETVAL 命令冲突，导致 30+ 个 restore 错误，hypertable 状态丢失。

实测（2026-05-13）：

```
pg_restore: error: could not execute query: ERROR:  relation "_timescaledb_catalog.dimension_slice_id_seq" does not exist
pg_restore: error: could not execute query: ERROR:  relation "_timescaledb_catalog.hypertable_id_seq" does not exist
pg_restore: warning: errors ignored on restore: 30
```

Timescale 官方推荐的 dump/restore 流程涉及 `timescaledb_pre_restore()` / `timescaledb_post_restore()` 函数调用，配置复杂且容易踩坑。

## Solution: 整 volume tar 备份

由于：
1. 容器目前不在跑，volume 处于 **quiescent**（静止）状态 → tar 出来必然一致
2. Volume 只有 ~150 MB，tar.gz 压缩到 ~27 MB，每日成本可忽略
3. 恢复 = 解压 tar 到新 volume + 启 timescaledb 容器，**TimescaleDB 元数据完整保留**，零特殊处理

### 文件

- 脚本：`~/scripts/acquilangai-backup.sh`（仓库副本 `scripts/acquilangai-backup.sh`）
- 备份目录：`~/backups/acquilangai/acquilangai-YYYYMMDD.tar.gz`
- 恢复源归档：`~/backups/acquilangai-restore-sources/`（不被 7 日滚动删除）
- 日志：`~/Library/Logs/acquilangai-backup.log`
- crontab：`0 4 * * *`（每天 04:00 本地时间，错开 codex/claude 07:00 高峰）
- 滚动保留：7 份（~189 MB 总占用）

### 脚本核心逻辑

```bash
# 1. 单实例锁（mkdir 原子）
# 2. 检查 volume 存在 → 检查是否有容器在用 volume
#    - 没在用：直接 tar（一致快照）
#    - 在用：警告日志，继续 tar（不一致风险，但仍有备份总比没有强；
#           生产场景下应该改为 docker stop + tar）
# 3. 用一次性 alpine 容器挂 volume:/data:ro 跑 tar -czf
# 4. 用 .tmp 中转避免半截文件，成功后 mv
# 5. 滚动删除超过 7 份的（按 mtime 倒序）
```

### 恢复方式

Colima 只挂载 `~/stacks`，不要 bind `~/backups`。当前常驻方式是 `~/stacks/acquilang-postgres/docker-compose.yml`，宿主端口 **5435**。

```bash
# 1. 把 tar 拷到 Colima 可见目录后解压到 volume
docker volume create acquilangai_postgres_data
cp ~/backups/acquilangai/acquilangai-YYYYMMDD.tar.gz ~/stacks/acquilang-postgres/restore.tar.gz
docker run --rm \
  -v acquilangai_postgres_data:/dest \
  -v "$HOME/stacks/acquilang-postgres":/src:ro \
  alpine sh -c 'tar --numeric-owner -xzf /src/restore.tar.gz -C /dest && rm -f /dest/postmaster.pid'
rm ~/stacks/acquilang-postgres/restore.tar.gz

# 2. 启动（不要 --rm）
cd ~/stacks/acquilang-postgres && docker-compose up -d

# 3. 等 ready；若镜像 Timescale 版本更新，升级扩展
docker exec acquilang-postgres pg_isready -U acquilang_user -d acquilang_db
docker exec acquilang-postgres psql -U acquilang_user -d acquilang_db -c 'ALTER EXTENSION timescaledb UPDATE;'
```

### 恢复演练（2026-05-13）

实际跑通：
- 表数 63 ✅（与源一致）
- llm_request_logs 1547 行 ✅
- reading_sessions 323 行 ✅
- lexemes 6648 行 ✅
- 启动到 ready：1 秒
- TimescaleDB 扩展正常加载（`timescaledb_information.hypertables` 视图可查）

## Restored 2026-09-13

从 `acquilangai-20260814.tar.gz` 恢复到 Colima。要点（详见 `docs/operations/mac-mini.md` 当日条目）：

- **端口**：宿主 **5435**（5433 已被 `cmm-postgres` 占用）。栈：`~/stacks/acquilang-postgres/`。
- **Colima virtiofs 只挂 `~/stacks`**：不能把 `~/backups` bind 进容器。解压 / 备份 tar 都要先落到 `~/stacks/acquilang-postgres/`。
- **活库 tar 含 `postmaster.pid`**：解压后必须删掉，否则 PG 可能拒绝启动。
- **扩展**：新镜像 Timescale 2.30.0，数据目录仍是 2.21.3，要对每个装了扩展的库执行 `ALTER EXTENSION timescaledb UPDATE;`（本实例是 `acquilang_db` 与 `ddricher_db`）。
- **滚动 7 份会删恢复源**：恢复前把 tar 拷到 `~/backups/acquilangai-restore-sources/`。
- **备份脚本**（2026-09-13 已改）：`PATH` 含 Homebrew docker；经 stacks 中转；容器先 `docker stop` 再 tar。仓库副本 `scripts/acquilangai-backup.sh`。

### 项目重新上线时

2026-09-13 起容器再次常驻。备份脚本已改为 `docker stop → tar → docker start`，不再对运行中 volume 做活 tar。

### 监控

每日跑后 `~/Library/Logs/acquilangai-backup.log` 会增加一段。建议偶尔检查（或后续接入告警，crontab 任务退出非 0 时触发邮件 / push 通知）。

### 与其它备份的关系

mac-mini 上当前两份每日 cron 备份：

| 任务 | 时间 | 备份对象 | 体积 | 方式 |
|---|---|---|---|---|
| sonarqube | 03:30 | sonarqube PG DB | ~102 MB / 份 × 7 = 715 MB | `pg_dump --format=custom -Z9` |
| acquilangai | 04:00 | acquilangai_postgres_data volume | ~27 MB / 份 × 7 = 189 MB | `tar -czf` 整 volume |

两个时间错开，互不打架。

## Related

- SonarQube 备份（同类思路但用 pg_dump 因为 sonarqube 用普通 PostgreSQL）：[`sonarqube-migrated-from-dev-cypresso-2026-05-13.md`](sonarqube-migrated-from-dev-cypresso-2026-05-13.md) §9
- TimescaleDB 官方 backup docs：https://docs.timescale.com/self-hosted/latest/backup-and-restore/
