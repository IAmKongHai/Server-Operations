---
title: SIMPLE 模式下事务日志文件被大事务撑大不回收——DBCC SHRINKFILE 收缩
date: 2026-05-13
category: docs/solutions/nas/database-issues
server: nas
module: nas / mas-old-sql2022-fts-nas (Docker)
problem_type: database_issue
component: database
severity: low
symptoms:
  - SIMPLE 恢复模式下，事务日志文件（.ldf）分配了几 GB ~ 几十 GB，但 `SpaceUsed` 只有几 MB
  - 备份文件 `RESTORE FILELISTONLY` 显示 LDF Size 巨大，恢复时需要等量预分配磁盘
  - 数据目录中 ldf 文件持续占空间，但日志实际数据极少
root_cause: design_flaw
resolution_type: configuration_change
tags: [sql-server, mssql, transaction-log, dbcc-shrinkfile, simple-recovery, log-bloat]
---

# SIMPLE 模式下事务日志文件被大事务撑大不回收——DBCC SHRINKFILE 收缩

## Problem

NAS 上 SQL Server 实例的 `authprovidermasweb` 数据库（SIMPLE 恢复模式）：

| 文件 | 已分配 | 实际已用 |
| --- | --- | --- |
| TopLogicAuthProvider_log | **10,858 MB** | 726 MB |

LDF 占了 11 GB 已分配空间，里头实际数据只有 726 MB。同实例还有两个类似的：`maswebkit_log` 1 GB / 2 MB；`medicalassistance_log` 259 MB / 8 MB。

ROWS 数据文件没有这个问题——`SpaceUsed` 接近 `allocated`，是正常的"几乎填满"。

## Root Cause

**SIMPLE 恢复模式会自动截断日志（释放可重用空间），但不会自动收缩文件。**

历史上跑过一次超大事务（一次性 INSERT/DELETE 几百万行、`SELECT INTO` 大表、索引重建等），事务日志在事务期间必须保留全部 redo 信息，触发 LDF 的 autogrow 扩张。事务提交后空间变成"可重用"，但**物理文件大小不会自己缩回去**——这是 SQL Server 的设计：避免在下一次同类事务时再次 autogrow（autogrow 是同步的、慢的）。

代价：磁盘上一直占着实际并不需要的空间。如果备份这个库，备份元数据里也会带着这个 LDF size，恢复时要预分配等量空间（参见 [[restore-bak-with-huge-log-via-temp-disk-2026-05-13]] 里的踩坑）。

## Resolution

### 适用判断

- 日志文件**已分配 - 已用 > 几百 MB** → 值得收缩
- 数据文件几乎填满（free 几 MB ~ 几十 MB）→ **不要**收缩，会引起索引碎片化
- 系统库（master/msdb/model/tempdb）不要主动动

### 操作

```sql
USE <db>;
ALTER DATABASE <db> SET RECOVERY SIMPLE;  -- 如果已经是 SIMPLE 可省略
CHECKPOINT;                                -- 立刻把可重用空间释放给 SHRINKFILE
DBCC SHRINKFILE (<log_logical_name>, <target_mb>);   -- target_mb 通常 128-512
```

`<log_logical_name>` 不是文件名，而是逻辑名，从 `sys.database_files.name` 查：

```sql
SELECT name, type_desc FROM sys.database_files WHERE type_desc = 'LOG';
```

本案例三次收缩结果：

| LOG 逻辑名 | 之前 | 之后 |
| --- | --- | --- |
| `TopLogicAuthProvider_log` | 10,858 MB | **514 MB**（-10.1 GB）|
| `maswebkit_log` | 1,082 MB | **132 MB** |
| `medicalassistance_log` | 259 MB | **68 MB** |

### 不能用 `RESTORE` 时直接收日志吗？

不能。`RESTORE` 必须按备份头里的 LDF Size 预分配磁盘空间，没有"恢复时一并收缩"的选项。`WITH MOVE` 只能改路径不能改大小。要想让备份本身体积变小，必须**先在源端收缩 LDF，再做新备份**。

## Verification

```sql
SELECT name, size*8/1024 AS allocated_mb,
       CAST(FILEPROPERTY(name,'SpaceUsed')*8/1024 AS int) AS used_mb
FROM sys.database_files WHERE type_desc = 'LOG';
```

宿主机角度看 NAS 数据目录：本次三次收缩后逻辑大小从 137 GB → 127 GB（-10 GB），实际占用（稀疏文件，参见 [[mssql-sparse-file-disk-usage-illusion-2026-05-13]]）从 31 GB → 28 GB。

## 关键经验

1. **SIMPLE 模式只截断不收缩。** 见到 LDF 物理文件比 used 大很多别奇怪，是历史大事务的"印记"。
2. **CHECKPOINT 在 SIMPLE 模式下是 SHRINKFILE 的前置**，不跑 CHECKPOINT 直接 SHRINKFILE 经常收不下去（可重用空间还没释放）。
3. **不要碰 ROWS 数据文件**。即使 free 看起来有点，碎片化代价远超回收的那点磁盘。
4. **目标大小别给 0**：给个合理 baseline（128-512 MB），减少未来再次 autogrow 的概率。
5. **如果日志暴涨可复现**，要查上层应用是不是有批量 DML 没分批 commit，而不是反复收缩。
