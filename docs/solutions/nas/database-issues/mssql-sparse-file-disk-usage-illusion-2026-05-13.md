---
title: SQL Server 数据目录"大小 137 GB / 占用 30 GB"——稀疏文件错觉，不是数据丢失
date: 2026-05-13
category: docs/solutions/nas/database-issues
server: nas
module: nas / mas-old-sql2022-fts-nas (Docker)
problem_type: database_issue
component: database
severity: low
symptoms:
  - 文件管理器查看 SQL Server 数据目录显示"大小 136.79 GB / 占用空间 30.65 GB"，差异巨大
  - 怀疑数据库文件被截断或数据丢失
  - `du --apparent-size` 与 `du` 默认值差几倍
root_cause: environmental_issue
resolution_type: workaround
tags: [sql-server, mssql, sparse-file, btrfs, du, file-manager, disk-usage]
---

# SQL Server 数据目录"大小 137 GB / 占用 30 GB"——稀疏文件错觉，不是数据丢失

## Problem

文件管理器 / 资源监控看 `/vol2/1000/mas-old-sqlserver/`：

- 大小 **136.79 GB**
- 占用空间 **30.65 GB**

差异巨大。担心数据库损坏或数据丢失。

## Root Cause

SQL Server 数据/日志文件（mdf/ndf/ldf）**预分配空间**，但底层文件系统（Btrfs / XFS / ext4 都支持）将"预分配但未写入"的部分作为**稀疏存储**，不占实际磁盘块。

两种 du 的差异：

| 工具 / 列 | 反映什么 |
| --- | --- |
| `du --apparent-size` / 文件管理器"大小" | 文件**逻辑大小**（文件描述的字节数）|
| `du`（默认）/ 文件管理器"占用空间" | 实际写入磁盘的块数 |

mdf/ldf 几乎总是稀疏文件，所以这两个数差几倍是**正常现象**，不是异常。

实测本次案例：

| 文件 | 逻辑大小 (apparent) | 实际占用 (du) |
| --- | --- | --- |
| `medicalassistance.mdf` | 98 GB | 16 GB |
| `authprovidermasweb.mdf` | 22 GB | 8.3 GB |
| `authprovidermasweb_log.ldf` | 11 GB | 3.5 GB |
| `maswebkit.mdf` | 5.8 GB | 3.3 GB |
| `maswebkit_log.ldf` | 1.1 GB | 8.5 MB |

## Resolution

**不要看磁盘字节数判断数据是否丢失。** 要看 SQL Server 自己的视图：

```sql
USE <db>;
SELECT name, type_desc,
       size*8/1024 AS allocated_mb,
       CAST(FILEPROPERTY(name, 'SpaceUsed')*8/1024 AS int) AS used_mb
FROM sys.database_files;
```

- `size`：已分配空间（SQL Server 占着不放的部分）
- `FILEPROPERTY(name, 'SpaceUsed')`：实际数据页占用

数据是否真的在那里，看 `used_mb`。如果 ROWS 文件 `used_mb ≈ allocated_mb`（差几 MB 算正常），说明数据真实存在。

本案例验证：

| 数据库 | 已分配 (MB) | 实际已用 (MB) |
| --- | --- | --- |
| medicalassistance (ROWS) | 99,885 | 99,884 ✅ |
| authprovidermasweb (ROWS) | 21,913 | 21,904 ✅ |
| maswebkit (ROWS) | 5,911 | 5,886 ✅ |

ROWS 几乎填满，数据完整。

## 关键经验

1. **稀疏文件是常态，不是异常。** 任何用过一段时间的 SQL Server 数据目录，逻辑大小都会显著大于实际占用。
2. **判断数据是否丢失，永远先查 `sys.database_files` 的 `SpaceUsed`**，不要被磁盘字节数误导。
3. **跨稀疏文件系统迁移要警惕**：如果用 `cp`、`tar` 不带 `--sparse=auto`/`-S` 参数，目标端可能把稀疏区域物化成真实零字节，占用突然暴涨。
4. 相关：[[mssql-shrink-bloated-transaction-log-2026-05-13]] —— 如果想真正回收逻辑空间，需要 SHRINKFILE，但通常**不值得**对 ROWS 数据文件做（会引起索引碎片化）。
