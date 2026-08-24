# mssql-ref 数据库清单

- 抓取：2026-08-24 22:52 CST
- 主机：`mssql-ref`（LAN `192.168.2.20` / Tailscale `100.124.140.78`）
- 引擎：SQL Server 2022 Developer 16.0.4252.3
- 方法：`sys.databases` + `sys.master_files`；bak 用 `RESTORE HEADERONLY` / `FILELISTONLY`（只读，未 `RESTORE DATABASE`）
- 用途：定新导入 catalog 名，避免和现网库、物理文件冲突

连接：`ssh mssql-ref`；SQL 听 `1433`。密码在 VM `/root/mssql-secrets.env`，不写本文件。

## 现网 catalog（12）

系统库 4 个：`master`、`model`、`msdb`、`tempdb`。下面 8 个是用户库，**这些名字已被占用**。

| catalog | 状态 | 恢复模式 | 兼容级别 | 数据 MB | 日志 MB | 合计 | 现网谁在用 |
| --- | --- | --- | ---: | ---: | ---: | ---: | --- |
| `medicalassistance_preprod` | ONLINE | SIMPLE | 100 | 100283 | 2110 | **102 GB** | mas-go-dev api/worker/ecom/sup `DB_NAME` / `REPLICATED_DB_NAME`；mas-win；SIT |
| `medicalassistance_replicated` | ONLINE | FULL | 140 | 21704 | 10056 | **31 GB** | 本机对照库，应用不连；**不要动** |
| `maswebkit` | ONLINE | SIMPLE | 120 | 5911 | 68 | **6.0 GB** | mas-go-dev `WEBKIT_DB_NAME`；mas-win Webkit |
| `maswebkit-uat-old` | ONLINE | FULL | 120 | 24 | 379 | 0.4 GB | 遗留，无应用连 |
| `insularsalesportal` | ONLINE | SIMPLE | 120 | 9 | 16 | 25 MB | mas-go-dev / sup `SALESPORTAL_DB_NAME` |
| `masprepaid` | ONLINE | SIMPLE | 120 | 24 | 8 | 32 MB | mas-go-dev ecom `PREPAID_DB_NAME` |
| `authprovidermasweb` | ONLINE | SIMPLE | 110 | 10733 | 65 | **10.8 GB** | ecom/sup `AUTH_DB_NAME`；mas-win 认证 |
| `operations` | ONLINE | FULL | 160 | 8 | 8 | 16 MB | 本机运维库，与 MAS 无关 |

排序规则：SQL Server catalog 名在实例内唯一，大小写不敏感（`CI` collation）。`maswebkit` 和 `MasWebKit` 算同一个名字。

## 物理文件（MOVE 时不要踩）

catalog 不冲突，**数据文件路径仍可能冲突**。现网落点：

| catalog | logical（ROWS） | 物理路径 |
| --- | --- | --- |
| `medicalassistance_preprod` | `medicalassistance` | `/restore/data/medicalassistance_full/medicalassistance_full.mdf` |
| `medicalassistance_replicated` | `medicalassistance_replicated` | `/restore/data/medicalassistance_replicated.mdf` |
| `maswebkit` | `maswebkit` | `/restore/data/maswebkit_full/maswebkit_full.mdf` |
| `maswebkit-uat-old` | `maswebkit` | `/var/opt/mssql/data/mas-ref/maswebkit-uat-old/maswebkit-uat-old.mdf` |
| `insularsalesportal` | `insularsalesportal` | **`/var/opt/mssql/data/insularsalesportal_preprod.mdf`**（库名无 `_preprod`，文件名有） |
| `masprepaid` | `masprepaid` | `/restore/data/masprepaid.mdf` |
| `authprovidermasweb` | `TopLogicAuthProvider` | `/restore/data/authprovidermasweb_full/authprovidermasweb_full.mdf` |
| `operations` | `operations` | `/var/opt/mssql/data/operations.mdf` |

`insularsalesportal` 这一条最容易踩：若把新库 `RESTORE` 成 `insularsalesportal_preprod` 且 `MOVE` 到默认 `/var/opt/mssql/data/insularsalesportal_preprod.mdf`，会打到现网库的文件上。逻辑文件名可以跨库重复；物理路径不行。

## 待导入 bak（尚未还原）

路径：`/restore/backups/ihc20260824/`。源实例 `ihc-db-uat`，备份 2026-08-24 20:47–20:52 CST，`COPY_ONLY + COMPRESSION`。`RESTORE` 目标 catalog **可以和 bak 内源库名不同**。

| bak | bak 内源库名 | 逻辑 ROWS / LOG | 恢复预占（分配大小） |
| --- | --- | --- | ---: |
| `medicalassistance_preprod_20260824.bak` | `medicalassistance_preprod` | `medicalassistance` / `medicalassistance_log` | 99.4 + 2.1 = **101.5 GB** |
| `maswebkit_preprod_20260824.bak` | `maswebkit_preprod` | `maswebkit` / `maswebkit_log` | 5.8 + 8.6 = **14.4 GB** |
| `insularsalesportal_preprod_20260824.bak` | `insularsalesportal_preprod` | `insularsalesportal` / `insularsalesportal_log` | 9 MB + 379 MB |
| `masprepaid_preprod_20260824.bak` | `masprepaid_preprod` | `masprepaid` / `masprepaid_log` | 0.55 + 1.1 = **1.6 GB** |
| `authprovidermasuat_20260824.bak` | `authprovidermasuat` | `TopLogicAuthProvider` / `TopLogicAuthProvider_log` | 0.24 + **22.7** = **22.9 GB** |

`authprovidermasuat` 日志文件仍是 22.7 GB（截断后未 SHRINK）。`/restore` 剩约 206 GB，五库旁路预占约 141 GB，够，但文件必须 `MOVE` 到新目录。

## 名字冲突对照

| bak 源库名 | 本机已有同名 catalog？ | 用源库名恢复？ | 建议旁路 catalog（不碰现网） |
| --- | --- | --- | --- |
| `medicalassistance_preprod` | **有，现网主库** | 不行（除非 `REPLACE`，会踢 mas-go-dev / mas-win） | `medicalassistance_preprod_ihc20260824` |
| `maswebkit_preprod` | 无（现网叫 `maswebkit`） | 可以 | `maswebkit_preprod` |
| `insularsalesportal_preprod` | 无（现网叫 `insularsalesportal`） | 可以，但 **MOVE 路径不能用** `/var/opt/mssql/data/insularsalesportal_preprod.mdf` | `insularsalesportal_preprod` |
| `masprepaid_preprod` | 无（现网叫 `masprepaid`） | 可以 | `masprepaid_preprod` |
| `authprovidermasuat` | 无（现网叫 `authprovidermasweb`） | 可以 | `authprovidermasuat` |

不要用的名字：上表「现网 catalog」整列，外加 `maswebkit-uat-old`、`medicalassistance_replicated`、四个系统库。也不要用裸名 `medicalassistance`（历史用过，容易和文档/SP 搞混）。

## 建议的 RESTORE 落点（未执行）

统一放到 `/restore/data/ihc20260824/<slug>/`，和现网 `*_full` 目录分开：

```sql
RESTORE DATABASE [medicalassistance_preprod_ihc20260824]
  FROM DISK = N'/restore/backups/ihc20260824/medicalassistance_preprod_20260824.bak'
  WITH MOVE N'medicalassistance' TO N'/restore/data/ihc20260824/medicalassistance/medicalassistance.mdf',
       MOVE N'medicalassistance_log' TO N'/restore/data/ihc20260824/medicalassistance/medicalassistance.ldf',
       RECOVERY, STATS = 10;
```

其余四库 catalog 用源名，`MOVE` 同样进 `ihc20260824/` 子目录。逻辑名（`maswebkit`、`TopLogicAuthProvider` 等）保持 bak 内原样即可。

应用暂不改 `.env` / `Web.config`。切现网、`REPLACE`、改名等用户回来再定。
