# mssql-ref 数据库清单

- 更新：2026-08-24 23:15 CST（ihc-db-uat 20260824 bak 已按用户命名恢复）
- 主机：`mssql-ref`（LAN `192.168.2.20` / Tailscale `100.124.140.78`）
- 引擎：SQL Server 2022 Developer 16.0.4252.3
- 方法：`sys.databases` + `sys.master_files`

连接：`ssh mssql-ref`；SQL 听 `1433`。密码在 VM `/root/mssql-secrets.env`，不写本文件。

系统库 4 个：`master`、`model`、`msdb`、`tempdb`（略）。

## 用户 catalog

| catalog | 来源 | 数据 MB | 日志 MB | 谁在用 |
| --- | --- | ---: | ---: | --- |
| **`medicalassistance_preprod`** | ihc-db-uat bak 2026-08-24 | 101799 | 2110 | mas-go-dev / mas-win / SIT 主库（切过来了） |
| **`medicalassistance_v2026.02.19`** | 原现网主库改名（适配 MAS 2026.02.19） | 100284 | 2110 | 旧参考，应用未改连它 |
| `medicalassistance_replicated` | 旧对照 | 21704 | 10056 | 不要动 |
| `maswebkit` | 原现网 | 5911 | 68 | mas-go-dev `WEBKIT_DB_NAME`；mas-win |
| **`maswebkit_preprod`** | ihc-db-uat bak | 5911 | 259 | 旁路，应用未切 |
| `maswebkit-uat-old` | 遗留 | 24 | 379 | 无应用 |
| `insularsalesportal` | 原现网 | 9 | 16 | mas-go-dev / sup `SALESPORTAL_DB_NAME` |
| **`insularsalesportal_preprod`** | ihc-db-uat bak | 9 | 68 | 旁路，应用未切 |
| `masprepaid` | 原现网 | 24 | 8 | ecom `PREPAID_DB_NAME` |
| **`masprepaid_preprod`** | ihc-db-uat bak | 548 | 133 | 旁路，应用未切 |
| `authprovidermasweb` | 原现网 | 10733 | 65 | ecom/sup `AUTH_DB_NAME`；mas-win |
| **`authprovidermasuat_preprod`** | ihc-db-uat `authprovidermasuat` bak | 245 | 264 | 旁路，应用未切 |
| `operations` | 本机运维 | 8 | 8 | 与 MAS 无关 |

加粗 = 本次从 `/restore/backups/ihc20260824/` 恢复或改名得到。数据文件在 `/restore/data/ihc20260824/<slug>/`（旧主库文件仍在 `/restore/data/medicalassistance_full/`）。

## 本次恢复对照

| bak 源库名 | 恢复成 | 现网旧名怎么处理 |
| --- | --- | --- |
| `medicalassistance_preprod` | `medicalassistance_preprod` | 旧库改名为 `[medicalassistance_v2026.02.19]`（名字含点，T-SQL 必须加方括号） |
| `maswebkit_preprod` | `maswebkit_preprod` | 旧 `maswebkit` 保留 |
| `insularsalesportal_preprod` | `insularsalesportal_preprod` | 旧 `insularsalesportal` 保留 |
| `masprepaid_preprod` | `masprepaid_preprod` | 旧 `masprepaid` 保留 |
| `authprovidermasuat` | `authprovidermasuat_preprod` | 旧 `authprovidermasweb` 保留 |

切主库前把旧库 `casbin_rule` 6344 行拷进新库（源 bak 里只有 14 行）；`schema_migrations` 两边都是 version 46 / dirty=0，未改。`mas_ref_owner` 在五个新库都是 `db_owner`。

## 回滚主库

```sql
ALTER DATABASE [medicalassistance_preprod] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [medicalassistance_preprod] MODIFY NAME = [medicalassistance_preprod_restore];
ALTER DATABASE [medicalassistance_preprod_restore] SET MULTI_USER;
ALTER DATABASE [medicalassistance_v2026.02.19] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
ALTER DATABASE [medicalassistance_v2026.02.19] MODIFY NAME = [medicalassistance_preprod];
ALTER DATABASE [medicalassistance_preprod] SET MULTI_USER;
```
