---
title: 在 PVE 上搭建 MAS 老系统参考 SQL Server VM
date: 2026-05-16
category: docs/solutions/pve/best-practices
server: pve
module: pve / mssql-ref
problem_type: workflow_issue
component: database
severity: low
tags: [pve, sql-server, mssql, full-text-search, mas, reference-environment]
---

# 在 PVE 上搭建 MAS 老系统参考 SQL Server VM

## Context

团队正在用 Go + React 重构 MAS 老系统，需要一套只供参考读取的旧数据库环境。目标不是生产可用，而是让后续 Windows Server Core + IIS 内的 `MAS-API` / `MAS-WEB` 能连接旧库，打开关键页面和 API 对照旧行为。

## Decision

先在 PVE 上创建独立 Linux VM `mssql-ref` 承载 SQL Server，再部署 Windows/IIS 应用 VM。

这样做的好处：

- SQL Server 包、数据文件和服务生命周期不污染 PVE 宿主。
- VM 可以单独快照，数据库 attach/restore 失败时容易回滚。
- SQL 层先稳定下来，后续 IIS 排障不会和数据库恢复混在一起。

## Implementation

创建 VM：

| 项目 | 值 |
| --- | --- |
| VMID | `110` |
| Name | `mssql-ref` |
| IP | `192.168.2.20/24` |
| OS | Ubuntu 22.04.5 LTS cloud image |
| CPU / Memory | 4 vCPU / 8 GiB |
| Disk | `nvme-data`，200G thin-provisioned |

安装 SQL Server：

- SQL Server 2022 Developer Edition
- SQL Server Full-Text Search：`mssql-server-fts`
- SQL tools：`mssql-tools18`
- SQL Server 版本：`16.0.4252.3` / RTM-CU24-GDR
- Full-Text Search 验证：`FULLTEXTSERVICEPROPERTY('IsFullTextInstalled') = 1`

凭据处理：

- SA 与只读账号密码只保存在 VM 内 `/root/mssql-secrets.env`
- 文件权限为 `600`
- 仓库文档只记录凭据位置，不记录明文密码

## Database Attach

首轮曾使用 iCare repo 中已有的紧凑 MDF/LDF 快速 attach，确认 SQL Server 和三库结构可运行：

| 数据库 | 来源文件 | 结果 |
| --- | --- | --- |
| `authprovidermasweb` | `backend/.local/mssql/data/authprovidermas_preprod_01_TopLogicAuthProvider.mdf` + 对应 LDF | ONLINE |
| `maswebkit` | `backend/.local/mssql/data/maswebkit_preprod_01_maswebkit.mdf` + 对应 LDF | ONLINE |
| `medicalassistance` | `backend/.local/mssql/data/medicalassistance_preprod_01_medicalassistance.mdf` + 对应 LDF | 已替换 |

VM 内数据文件落点：

```text
/var/opt/mssql/data/mas-ref/
```

挂载后特征：

| 数据库 | 大小 | 表数量 | Full-Text |
| --- | ---: | ---: | --- |
| `authprovidermasweb` | 约 8.64 MB | 9 | 无 |
| `maswebkit` | 约 30.19 MB | 66 | 无 |
| `medicalassistance`（首轮删减库） | 约 2976 MB | 419 | 1 catalog / 1 index |

首轮小库特征：

| 数据库 | 行数抽样 |
| --- | ---: |
| `authprovidermasweb` | 约 9,078 |
| `maswebkit` | 约 33,620 |
| `medicalassistance` | 约 45,750,099 |

确认它们不是全量库后，删除这些首轮小库，并从 `.bak` 恢复。

## Full Backup Restore

全量/compact 备份：

| 数据库 | iCare repo 备份 | remote | size |
| --- | --- | --- | ---: |
| `authprovidermasweb` | `backend/db-bak/authprovidermas_preprod_compact-13052026.bak` | `/restore/backups/authprovidermas_preprod_compact-13052026.bak` | 3,750,199,296 bytes |
| `maswebkit` | `backend/db-bak/maswebkit_preprod_compact-13052026.bak` | `/restore/backups/maswebkit_preprod_compact-13052026.bak` | 2,778,361,856 bytes |
| `medicalassistance` | `backend/db-bak/medicalassistance_prepro_05032026.bak` | `/restore/backups/medicalassistance_prepro_05032026.bak` | 104,610,357,248 bytes |

恢复前给 `mssql-ref` 增加独立恢复盘：

| 项目 | 值 |
| --- | --- |
| PVE disk | `nvme-data:vm-110-disk-1` |
| Size | 400G thin-provisioned |
| Guest mount | `/restore` |
| Filesystem | ext4 |

`medicalassistance` 备份元数据：

| 项目 | 值 |
| --- | --- |
| Source server | `ihc-db-uat` |
| Source database | `medicalassistance_preprod` |
| DatabaseVersion | 869（SQL Server 2017） |
| Backup date | 2026-03-05 |
| Data logical name | `medicalassistance` |
| Log logical name | `medicalassistance_log` |
| Data file size | 104,611,381,248 bytes |
| Log file size | 29,013,639,168 bytes |
| Recovery model | SIMPLE |

`authprovidermasweb` 备份元数据：

| 项目 | 值 |
| --- | --- |
| Source database | `authprovidermas_preprod` |
| DatabaseVersion | 869（SQL Server 2017） |
| Backup date | 2026-05-13 |
| Compression | `MS_XPRESS` |
| Data logical name | `TopLogicAuthProvider` |
| Log logical name | `TopLogicAuthProvider_log` |
| Data file size | 11,251,286,016 bytes |
| Log file size | 276,496,384 bytes |
| Recovery model | SIMPLE |

`maswebkit` 备份元数据：

| 项目 | 值 |
| --- | --- |
| Source database | `maswebkit_preprod` |
| DatabaseVersion | 869（SQL Server 2017） |
| Backup date | 2026-05-13 |
| Compression | `MS_XPRESS` |
| Data logical name | `maswebkit` |
| Log logical name | `maswebkit_log` |
| Data file size | 6,198,132,736 bytes |
| Log file size | 271,712,256 bytes |
| Recovery model | SIMPLE |

恢复策略：

1. 先恢复到临时库名 `<dbname>_full`，文件放在 `/restore/data/<dbname>_full/`。
2. 验证成功后删除首轮删减版正式库。
3. 将 `<dbname>_full` 改名为正式库名。
4. 重新给 `mas_ref_reader` 授予 `db_datareader`。

当前核心库：

| 数据库 | ROWS | LOG | User tables | Partition rows | Full-Text |
| --- | ---: | ---: | ---: | ---: | --- |
| `authprovidermasweb` | 约 10,731 MB | 约 264 MB | 9 | 约 6,925,933 | 无 |
| `maswebkit` | 约 5,911 MB | 约 259 MB | 66 | 约 10,474,914 | 无 |
| `medicalassistance` | 约 99,765 MB | 约 27,670 MB | 419 | 约 233,322,888 | 1 catalog / 1 index |

说明：`/restore/data/*_full/` 目录名保留恢复过程的临时名，但 SQL Server 库名已经改为正式库名。

全量备份传输期间发现 PVE 物理网口在高流量下 link flap：

- 网卡：Realtek `RTL8111/8168/8211/8411`
- 驱动：`r8169`
- 症状：`journalctl -k` 反复出现 `nic0: Link is Down`
- 处理：更换 PVE 侧网线，并关闭 EEE：`ethtool --set-eee nic0 eee off`
- 结果：4G 压测稳定，全量 `.bak` 通过 `rsync --partial --inplace` 传输完成

## Validation

已验证：

- VM 重启后 SSH 可达。
- `mssql-server` 为 `enabled` / `active`。
- SQL Server 监听 `0.0.0.0:1433`。
- UFW 为 inactive，内网 VM 可直接访问 1433。
- 三套库均为 `ONLINE`。
- `mas_ref_reader` 登录可连接 `192.168.2.20:1433`，并能从三套库做普通 `SELECT`。
- PVE 快照：`mssql-ready`、`mssql-full-ready`、`mssql-all-full-ready`。

## Operational Notes

- 只读登录：`mas_ref_reader`。
- 只读登录密码：登录 `mssql-ref` 后从 `/root/mssql-secrets.env` 读取 `MSSQL_MAS_REF_READER_PASSWORD`。
- SA 密码：同一文件中的 `MSSQL_SA_PASSWORD`。
- 如果后续应用提示缺少 `insularsalesportal`、`masprepaid` 等库，先确认是否阻塞核心页面，再决定补库或改配置降级。
- 如果需要回滚到三套核心库都从备份恢复后的状态，可在 PVE 中回到 `mssql-all-full-ready` 快照。
- 如果只需要回到仅 `medicalassistance` 全量恢复后的状态，可回到 `mssql-full-ready`。
- 如果要回到首轮小库状态，可回滚 `mssql-ready`，但这会丢失后续 `/restore` 盘上的全量恢复状态。
- PVE `nvme-data` 是 thin pool，当前保留多个快照后逻辑分配量超过物理容量；不要长期保留无用快照。

## Follow-Up

下一步创建 Windows Server Core VM，安装 IIS / .NET Framework / ASP.NET 4.x，并把 `MAS-API`、`MAS-WEB` 部署副本的连接串指向：

```text
Server=192.168.2.20,1433
User ID=mas_ref_reader
```
