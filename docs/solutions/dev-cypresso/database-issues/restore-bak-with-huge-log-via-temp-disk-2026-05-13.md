---
title: 恢复带巨型 LDF 元数据的 SQL Server 备份到磁盘空间不足的目标机
date: 2026-05-13
category: docs/solutions/dev-cypresso/database-issues
server: dev-cypresso
module: dev-cypresso / shared-sqlserver (SQL Server 2017, Docker)
problem_type: database_issue
component: database
severity: medium
symptoms:
  - .bak 文件本身只有 5.8 / 10 GB，但 RESTORE FILELISTONLY 显示 LDF Size = 53 GB / 137 GB（源端 LDF 历史大事务残留）
  - 目标机根分区只剩十几 GB，docker volume 也在根分区上，直接 RESTORE 必爆盘
  - RESTORE 必须按备份元数据里的 LDF Size 预分配磁盘，无法在 RESTORE 时直接指定更小日志大小
root_cause: environmental_issue
resolution_type: workaround
tags: [sql-server, mssql, restore, transaction-log, dbcc-shrinkfile, docker, disk-space, temp-disk, cross-version]
---

# 恢复带巨型 LDF 元数据的 SQL Server 备份到磁盘空间不足的目标机

## Problem

需要把两个 SQL Server 备份恢复到 dev-cypresso 上的 `shared-sqlserver` 容器（SQL Server 2017）：

| 备份文件 | 大小 | LDF 元数据 Size | 目标库 |
| --- | --- | --- | --- |
| `maswebkit-05032026.bak` | 5.8 GB | **137 GB** | `maswebkit_preprod` |
| `authprovidermas_preprod-13032026.bak` | 10 GB | **53 GB** | `authprovidermas_preprod` |

目标机状态：

- 根分区 100 GB / 剩 ~18 GB（docker volume 在根分区上）
- 直接恢复任一备份都会把根分区写爆（恢复时按 LDF 元数据 Size 预分配磁盘空间）

## Root Cause

`RESTORE DATABASE` 在 SQL Server 中**必须按备份头里记录的物理文件大小预分配磁盘**，即使日志文件实际数据是空的：

- `WITH MOVE` 只能改路径，不能改大小
- 没有 `WITH SHRINKLOG` 这种"恢复时一并收缩"的选项
- 兼容级别 / 数据库选项都得**恢复之后**才能改

源端 LDF 体积巨大的根因见 [[../../nas/database-issues/mssql-shrink-bloated-transaction-log-2026-05-13]]：SIMPLE 模式只截断不收缩，历史大事务把 LDF 撑大就再也不会自己回去。

## Resolution

### 核心思路：临时盘 + "恢复 → 收日志 → 再备份 → 再恢复" 循环

```
[原始 .bak（LDF 元数据巨大）]
        ↓ 临时盘上 RESTORE
[临时盘上的库：mdf 正常 + ldf 几十 GB ~ 137 GB]
        ↓ ALTER SET SIMPLE + CHECKPOINT + DBCC SHRINKFILE
[临时盘上的库：mdf 正常 + ldf 256 MB]
        ↓ BACKUP WITH COMPRESSION
[紧凑 .bak]   ← 元数据里 LDF 已变小
        ↓ DROP + RESTORE 回原 docker volume
[最终库落在 docker volume：约等于原始数据量]
```

第二次 RESTORE 只需要"正常大小"的空间，能塞进原 docker volume。

### Step 1：临时盘上线（加挂 250 GB 盘到 dev-cypresso）

```bash
ssh dev-cypresso "
  sudo mkfs.xfs -f -L mssql_tmp /dev/nvme1n1
  sudo mkdir -p /var/lib/docker/volumes/shared_sqlserver_data/_data/restore_disk
  sudo mount /dev/nvme1n1 /var/lib/docker/volumes/shared_sqlserver_data/_data/restore_disk
  sudo chown 999:999 /var/lib/docker/volumes/shared_sqlserver_data/_data/restore_disk
"
```

关键点：
- **不重启容器**，直接把新盘挂载到 docker volume **内部一个子目录**，容器内自然能看见路径 `/var/opt/mssql/restore_disk`
- 这种"在已挂载的 docker volume 里再 mount 新盘"是 hack 但有效，适合临时使用（拆走时只要 umount + rmdir）
- xfs label 限制 12 字符（13 字符直接报错）
- chown 用**容器内** mssql 的 uid，本案例容器内 uid=999（NAS 那台 SQL 容器是 10001，**uid 因镜像而异，必须先 `docker exec <c> id mssql` 确认**）

### Step 2：传 .bak 到容器

dev-cypresso 的 `/tmp` 是 8 GB tmpfs，**5+ GB 文件直接进 /tmp 会吃掉一半内存**。详细做法见 [[../../best-practices/sqlcmd-shell-pitfalls-2026-05-13]] 里的"流式传输绕过 tmpfs"。

简短版：

```bash
# 5.8 GB 小文件：rsync 走 /tmp 中转再 docker cp，传完立刻 rm /tmp 副本
rsync -avP --partial local.bak dev-cypresso:/tmp/local.bak
ssh dev-cypresso "docker cp /tmp/local.bak shared-sqlserver:/var/opt/mssql/restore_tmp/ && rm /tmp/local.bak"

# 10 GB 大文件：cat 流式直送容器，完全不走宿主磁盘
cat local.bak | ssh dev-cypresso \
  "docker exec -i shared-sqlserver bash -c 'cat > /var/opt/mssql/restore_tmp/local.bak'"
ssh dev-cypresso "docker exec shared-sqlserver chown mssql:mssql /var/opt/mssql/restore_tmp/local.bak"
```

后者实测 10 GB 用 ~35 分钟，md5 一致。

### Step 3：确认跨版本兼容

```sql
RESTORE HEADERONLY FROM DISK = '/var/opt/mssql/restore_tmp/local.bak';
```

关键列 `DatabaseVersion`：

| DatabaseVersion | SQL Server 版本 |
| --- | --- |
| 904 | 2022 |
| 869 | 2017 |
| 852 | 2016 |
| 782 | 2014 |

**备份只能恢复到 >= 同版本的实例**。本次两份都是 869 → 目标 2017，✅ 兼容。

如果源版本 > 目标版本，这条路堵死——`COMPATIBILITY_LEVEL` 只是语法兼容开关，**不**改变数据文件版本。

### Step 4：DROP 旧库（如存在）+ RESTORE 到临时盘

`RESTORE FILELISTONLY` 拿逻辑文件名（**不是物理文件名**，注意区分）：

```sql
RESTORE FILELISTONLY FROM DISK = '/var/opt/mssql/restore_tmp/local.bak';
```

输出关键列 `LogicalName`、`Type`（D=ROWS, L=LOG）、`Size`。

两份备份的差别：

| 备份 | ROWS 逻辑名 | LOG 逻辑名 |
| --- | --- | --- |
| maswebkit | `maswebkit` | `maswebkit_log` |
| authprovidermas | `TopLogicAuthProvider` | `TopLogicAuthProvider_log` |

逻辑名跟物理文件名经常不一样（源端是 Windows 路径 `F:\data\...`，恢复时必须 MOVE 到 Linux 路径）。

```sql
-- 如果目标侧已有同名库（哪怕是空库）需先 DROP
ALTER DATABASE <db> SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
DROP DATABASE <db>;

RESTORE DATABASE <db>
  FROM DISK = '/var/opt/mssql/restore_tmp/local.bak'
  WITH MOVE '<logical_rows>' TO '/var/opt/mssql/restore_disk/<db>.mdf',
       MOVE '<logical_log>'  TO '/var/opt/mssql/restore_disk/<db>_log.ldf',
       REPLACE, RECOVERY, STATS = 10;
```

实测耗时（瓶颈是容器内 LDF zero-init，~128 MB/s）：

| 备份 | 数据 | LDF 元数据 | 总耗时 |
| --- | --- | --- | --- |
| maswebkit | 5.8 GB | 137 GB | **19 分钟** |
| authprovidermas | 10 GB | 53 GB | **8.7 分钟** |

**容器内 mssql 没有 SeManageVolumePrivilege**（Instant File Initialization），LDF 必须实打实 zero-init，没法绕过。

`percent_complete = 100`、`state_desc = RESTORING` 是 zero-init 进行中的正常态，**要等 `state_desc = ONLINE` 才算结束**。等待的正确做法：

```bash
until ssh host "docker exec -i c bash -c '... sqlcmd ... -Q \"SELECT state_desc FROM sys.databases WHERE name=N'\''mydb'\''\"'" \
  2>&1 | grep -q '^ONLINE'; do
  sleep 30
done
```

### Step 5：切 SIMPLE + 收缩 LOG

```sql
ALTER DATABASE <db> SET RECOVERY SIMPLE;
USE <db>;
CHECKPOINT;
DBCC SHRINKFILE (<log_logical_name>, 256);   -- 目标 MB
```

详细原理与 SIMPLE/CHECKPOINT 关系见 [[../../nas/database-issues/mssql-shrink-bloated-transaction-log-2026-05-13]]。

结果：

| LOG | 之前 | 之后 |
| --- | --- | --- |
| `maswebkit_log` | 139,855 MB | **259 MB** |
| `TopLogicAuthProvider_log` | 54,840 MB | **263 MB** |

### Step 6：生成紧凑备份

```sql
BACKUP DATABASE <db>
  TO DISK = '/var/opt/mssql/restore_disk/<db>_compact.bak'
  WITH COMPRESSION, INIT, FORMAT, STATS = 25;
```

结果：

| 库 | 原始 .bak | 紧凑 .bak | 比 |
| --- | --- | --- | --- |
| maswebkit | 5.8 GB（无压缩）| **2.6 GB** | 0.45× |
| authprovidermas | 10 GB（无压缩）| **3.5 GB** | 0.35× |

注意紧凑 bak 的元数据里 LDF Size 已经变成 256 MB——这正是后续能恢复回原盘的关键。

### Step 7：DROP 临时盘上的库 + 用紧凑 bak 恢复回 docker volume

恢复前**先确认根分区够装数据文件**。本案例做 authprovidermas 时根分区一度只剩 5.8 GB（装不下 11 GB mdf），原因是容器内还残留着 11 GB 原始 .bak。解法：**在 DROP 之前先删原始 .bak**：

```bash
docker exec shared-sqlserver rm /var/opt/mssql/restore_tmp/<db>-original.bak
```

然后：

```sql
DROP DATABASE <db>;

RESTORE DATABASE <db>
  FROM DISK = '/var/opt/mssql/restore_disk/<db>_compact.bak'
  WITH MOVE '<logical_rows>' TO '/var/opt/mssql/data/<db>.mdf',
       MOVE '<logical_log>'  TO '/var/opt/mssql/data/<db>_log.ldf',
       REPLACE, RECOVERY, STATS = 25;
```

实测耗时：

| 库 | 二次 RESTORE 用时 |
| --- | --- |
| maswebkit | **51 秒** |
| authprovidermas | **88 秒** |

没有 zero-init 卡顿，恢复速度回归正常。

### Step 8：拆临时盘

```bash
ssh dev-cypresso "
  docker exec shared-sqlserver rm -rf /var/opt/mssql/restore_tmp /var/opt/mssql/restore_disk/*.bak
  sudo umount /var/lib/docker/volumes/shared_sqlserver_data/_data/restore_disk
  sudo rmdir /var/lib/docker/volumes/shared_sqlserver_data/_data/restore_disk
"
# 此时 /dev/nvme1n1 已无挂载，可物理拔出
```

## Verification

```sql
USE <db>;
-- 物理路径应该在原 docker volume 的 /var/opt/mssql/data/
SELECT name, type_desc, physical_name, size*8/1024 AS size_mb FROM sys.database_files;

-- 数据行数：抽查 TOP 表，跟源端数量级对得上
SELECT TOP 5 t.name, SUM(p.rows) AS rows
FROM sys.tables t JOIN sys.partitions p ON t.object_id=p.object_id AND p.index_id IN (0,1)
GROUP BY t.object_id, t.name ORDER BY 2 DESC;
```

最终两个库都落在 `/var/opt/mssql/data/`：

| 库 | mdf | ldf | 关键表行数 |
| --- | --- | --- | --- |
| maswebkit_preprod | 5,911 MB | 259 MB | oauth_access_tokens_Backup 5.12M |
| authprovidermas_preprod | 10,730 MB | 263 MB | oauth_access_tokens 5.10M |

## 关键经验

1. **"小 .bak + 巨型 LDF 元数据"模式下，目标机磁盘紧张时用临时盘做"恢复-收日志-再备份-再恢复"循环**。关键是让备份元数据里的 LDF Size 跟着收下来。
2. **容器内 LDF zero-init 不可绕过**：容器化 SQL Server 跑在普通用户下，拿不到对应特权。预估按 ~128 MB/s 算。
3. **`state_desc = ONLINE` 才算 RESTORE 真的完成**：`percent_complete = 100` 但还在 RESTORING 是常态（zero-init 期间）。轮询要等 ONLINE，不要看 percent_complete。
4. **同实例同样的"小 .bak + 巨大 LDF" pattern 多个库可以批量做**：本次 maswebkit 走通流程后，authprovidermas 一次性顺利通过，只是参数（逻辑名、目标库名）不同。
5. **二次 RESTORE 前主动清理原始 .bak**：原始 .bak 占着 docker volume 的根分区空间，不清空间可能不够装最终 mdf。
6. **临时盘挂到 docker volume 子目录是 hack 但 work**：好处是不重启容器、不影响同实例其他库；缺点是宿主 reboot 后丢挂载（临时用刚好合适）。chown 用**容器内** uid，不是宿主 uid。
7. **DatabaseVersion 跨版本对照**：869=2017、904=2022、852=2016、782=2014。**只能向高版本恢复**，反向直接拒绝。
8. **相关 shell/sqlcmd 陷阱**：见 [[../../best-practices/sqlcmd-shell-pitfalls-2026-05-13]]——这次踩到 here-doc 引号、tmpfs 不能放大文件、流式传输、fish 的 `===` 报错让任务误报 failed 等多个坑，单独成文了。
