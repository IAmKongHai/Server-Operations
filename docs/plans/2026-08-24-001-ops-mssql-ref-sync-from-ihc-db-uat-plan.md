---
title: 把 ihc-db-uat（10.100.0.4）五库同步到 mssql-ref
server: mssql-ref
status: proposed
created: 2026-08-24
tags:
  - mssql
  - restore
  - ihc-db-uat
  - preprod
  - database-issues
---

# 把 ihc-db-uat（10.100.0.4）五库同步到 mssql-ref

## 背景

客户 preprod 正在用的库在 `10.100.0.4` / `ihc-db-uat`（SQL Server 2017 Standard 14.0.3540.1）。
内网参考库是 `mssql-ref`（Tailscale `100.124.140.78` / LAN `192.168.2.20`，SQL Server 2022 Developer 16.0.4252.3）。

要同步的 5 个 catalog（来源：`iCare/docs/handoff/ihc-db-uat-10.100.0.4-databases.md`）：

| # | 源库（10.100.0.4） | 谁连 |
| - | --- | --- |
| 1 | `medicalassistance_preprod` | MAS backend；sup 的 replicated 指回同一库 |
| 2 | `maswebkit_preprod` | MAS backend；public-backend |
| 3 | `insularsalesportal_preprod` | MAS backend；sup |
| 4 | `authprovidermasuat` | ecom / sup（只读 `oauth_clients`） |
| 5 | `masprepaid_preprod` | ecom |

**不用 2026-08-21 的 bak。** 2026-08-24 20:46–20:52 CST 已在源机打了最新 `COPY_ONLY, COMPRESSION`（先 `BACKUP LOG` 截断 FULL 库日志）。传输只搬 `F:\icare2bak\*_20260824.bak`，合计 **17.0 GB**。`.trn` 留在 `D:\icare2bak\`，不传。

## 目标终态

`mssql-ref` 上有一份与 `10.100.0.4` **2026-08-24 20:52 CST** 一致的五库数据，
可供 mas-go-dev / mas-win 对照 preprod。现网 SIT / mas-go-dev / mas-win **先不切**，
等旁路库验证通过再决定是否改名替换。

## 为什么传 bak（传输量最小）

全量、时间点一致的拷贝里，**`BACKUP DATABASE … WITH COPY_ONLY, COMPRESSION` 是线上最小的**：

| 办法 | 大约要搬 | 为什么不用 |
| --- | ---: | --- |
| 拷 MDF/LDF | ~140 GB | 按分配大小搬，还要卸库 |
| 源上夜间 COPY_ONLY（未压缩） | ~126 GB | msdb 里 `compressed_mb = backup_mb` |
| 不截断 auth 日志就打全备 | auth 一项就 ~18 GB 未压缩 / 昨晚 5.9 GB 压缩 | `authprovidermasuat` 当时日志 used **21 GB**（FULL + `LOG_BACKUP`） |
| **本次：LOG 截断 + COPY_ONLY COMPRESSION** | **17.0 GB** | 主库 14.2 GB + webkit 2.6 GB + 其余 <0.3 GB |

再压一层 zstd 最多再削 10–20%，不值得为这点多一道。BACPAC / 逐表导出更慢，主库通常更大。差异备份对不上 `mssql-ref` 上的旧库（不是同一条 LSN 链）。

`.trn` 只为截断日志，**不传到家里**。

## 调查结论（2026-08-24）

### 源 bak（ihc-db-uat `F:\icare2bak\*_20260824.bak`，已生成）

2026-08-24 20:46–20:52 CST，从 `icare-uat-runner-1` 用 `mas_ref_owner` 执行。
`BACKUP DATABASE … WITH COPY_ONLY, COMPRESSION, INIT, CHECKSUM`。未覆盖 `*_20260821.bak`。

| bak | 压缩后 | COPY_ONLY 起止（CST） |
| --- | ---: | --- |
| `medicalassistance_preprod_20260824.bak` | **14.19 GB** | 20:48:25–20:52:57 |
| `maswebkit_preprod_20260824.bak` | 2.59 GB | 20:47:44–20:48:25 |
| `masprepaid_preprod_20260824.bak` | 162 MB | 20:47:40–20:47:42 |
| `authprovidermasuat_20260824.bak` | 43 MB | 20:47:42–20:47:44 |
| `insularsalesportal_preprod_20260824.bak` | 1.2 MB | 20:47:38–20:47:40 |
| **合计（要传的）** | **17.0 GB** | |

FULL 库先打了 `BACKUP LOG`（非 COPY_ONLY，为截断；`.trn` 不传）：

| trn | 压缩后 | 说明 |
| --- | ---: | --- |
| `authprovidermasuat_20260824.trn` | 5.81 GB | 截断前日志 used 21.3 GB；不截断则全备会把这段日志打进去 |
| `masprepaid_preprod_20260824.trn` | 48 MB | |
| `maswebkit_preprod_20260824.trn` | 2 MB | |
| `insularsalesportal_preprod_20260824.trn` | 1 MB | |
| `medicalassistance_preprod` | — | SIMPLE，不能 / 不必 `BACKUP LOG` |

备份后 `F:` 空闲 240 GB，`D:` 空闲 103.5 GB。`RESTORE` 仍按源文件**分配大小**预占（auth 日志文件还是 ~23 GB，本次未 SHRINK）。旁路五库预占仍大约 130–145 GB，`/restore` 剩 206 GB，够。

### 应用连接（iCare `backend/.env.preprod`）

CYP-2250 给本机连 live preprod 用的 env。2026-08-24 从 `icare-uat-runner-1` 用该账号只读登录成功。

| 项 | 值 |
| --- | --- |
| 文件 | iCare 仓 `backend/.env.preprod`（密码不入库、不写进本 plan） |
| Host | `10.100.0.4:1433`，`ENCRYPT=disable` |
| 账号 | `mas_ref_owner`（主库角色 `db_owner`） |
| 本机直连 | 需要 iCare-2-vnet / P2S VPN；无 VPN 时走 runner `10.30.6.4` |
| 实测实例 | `ihc-db-uat` / `14.0.3540.1` |

| env | catalog |
| --- | --- |
| `DB_NAME` | `medicalassistance_preprod` |
| `WEBKIT_DB_NAME` | `maswebkit_preprod` |
| `SALESPORTAL_DB_NAME` | `insularsalesportal_preprod` |
| `AUTH_DB_NAME` | `authprovidermasuat` |
| `PREPAID_DB_*` | **文件里没有**（MAS backend 不用；ecom 才要 `masprepaid_preprod`） |

handoff 写「`mas_ref_owner` 不会在 10.100.0.4 上、老应用用 `mas_user`」已过时：我们这条链路用的就是 `mas_ref_owner`。同实例上 `authprovidermas_preprod` 也在，本方案默认仍跟 8443 那条 `authprovidermasuat`。

`db_owner` 已用来打 2026-08-24 的 LOG + COPY_ONLY。传文件走 AzCopy / SMB，不靠这个 SQL 账号。

逻辑文件名（RESTORE `MOVE` 要用）：

| 源库 | ROWS logical | LOG logical |
| --- | --- | --- |
| `medicalassistance_preprod` | `medicalassistance` | `medicalassistance_log` |
| `maswebkit_preprod` | `maswebkit` | `maswebkit_log` |
| `authprovidermasuat` | `TopLogicAuthProvider` | `TopLogicAuthProvider_log` |
| `masprepaid_preprod` | `masprepaid` | `masprepaid_log` |
| `insularsalesportal_preprod` | `insularsalesportal` | `insularsalesportal_log` |

### 目标 mssql-ref 现状

| 项目 | 值 |
| --- | --- |
| 引擎 | SQL Server 2022 Developer 16.0.4252.3（可恢复 2017 bak，升级不可逆） |
| `/` | 194G / 用 45G / 剩 150G |
| `/restore` | 393G / 用 168G / **剩 206G** → 旁路恢复 148G 后约剩 58G，够 |
| PVE thin `nvme-data` | 934G / Data% 38.6，物理余量充足 |
| VM 快照 | 无（`qm listsnapshot 110` 只有 `current`） |

现有用户库与源库**不是同名一一对应**：

| 源 catalog | 本机现名 | 本机占用 | 现网谁在用 |
| --- | --- | ---: | --- |
| `medicalassistance_preprod` | **同名** `medicalassistance_preprod` | 100G+2G | mas-go-dev api/worker/ecom/sup；mas-win；SIT |
| `maswebkit_preprod` | `maswebkit`（无 `_preprod`） | 5.9G | mas-go-dev `WEBKIT_DB_NAME`；mas-win Webkit |
| `insularsalesportal_preprod` | `insularsalesportal` | 9MB+16MB | mas-go-dev / sup `SALESPORTAL_DB_NAME` |
| `masprepaid_preprod` | `masprepaid` | 24MB | mas-go-dev ecom `PREPAID_DB_NAME` |
| `authprovidermasuat` | **没有**。本机是 `authprovidermasweb`（来自 `authprovidermas_preprod` compact，10.7G） | 10.7G | ecom/sup `AUTH_DB_NAME=authprovidermasweb` |

本机另有、**不要动**：`medicalassistance_replicated`（22G+10G）、`maswebkit-uat-old`、`operations`。

Go 重构痕迹在旧 `medicalassistance_preprod` 上：`dbo.schema_migrations` version **46**（dirty=0）、`dbo.casbin_rule`。
源 preprod 是老 C# 库，恢复后这两张表会消失或回到源状态。下一步 mas-go-dev deploy 若自动 `migrate up`，会从 0 打到现网 schema 上，有风险。

本机曾打过、**原地 REPLACE 会丢掉**的补丁：

- 2026-06-19：三库 SP 里 `medicalassistance_replicated` → `medicalassistance_preprod`（源 live preprod 的 SP 本身就该写 `_preprod`，旁路恢复后先抽查，不必预假设还要再改）
- 2026-08-20：`maswebkit.dbo.sp_getmaswebmemberdetailsv6` + `tblsubscriptionmembers` 两列（给 mas-win MemberPortal）。源库若没有，切回 `maswebkit` 前要重打

活连接（调查时）：`mas_ref_owner` 来自 mas-go-dev 容器，连着 `medicalassistance_preprod` 与 `maswebkit`。
api / worker / ecom / sup / public-hr / public-map 当时均为 healthy。

### 传输路径

|  hop | 结果 |
| --- | --- |
| 本机 → `10.100.0.4` | ICMP 不通（无直连） |
| `icare-uat-runner-1`（`10.30.6.4`）→ `10.100.0.4` | ping ~1.5ms，**1433 / 445 / 3389 开**，22 关 |
| runner → `100.124.140.78` | 不通（runner 无 Tailscale） |
| 本机 → runner / mssql-ref | SSH 均可（runner 走 utun，ICMP 可被挡） |
| `ihc-db-uat` → `icare2uaticare2st.blob.core.windows.net` | 解析到 **私网 PE `10.30.5.9`**，443 通 |
| 该 storage | `publicNetworkAccess=Disabled`，仅 PE。mssql-ref **不能**从公网拉 |
| AzCopy on ihc-db-uat | 有：`C:\Program Files\AzCopy\azcopy.exe` |

`icare2uaticare2otast` 虽对公网开放，但是 OTA 存储，**不要**把含 PII 的库备份放到那里。

## 推荐方案：旁路恢复，不碰现网 catalog

不 `REPLACE` 正在用的库。把 5 个 bak 恢复成**源库名**（只有主库要加后缀避开冲突）：

| 源库 | 恢复成 | 数据文件落点 |
| --- | --- | --- |
| `medicalassistance_preprod` | `medicalassistance_preprod_ihc20260824` | `/restore/data/ihc20260824/medicalassistance/` |
| `maswebkit_preprod` | `maswebkit_preprod` | `/restore/data/ihc20260824/maswebkit/` |
| `insularsalesportal_preprod` | `insularsalesportal_preprod` | `/restore/data/ihc20260824/insularsalesportal/` |
| `masprepaid_preprod` | `masprepaid_preprod` | `/restore/data/ihc20260824/masprepaid/` |
| `authprovidermasuat` | `authprovidermasuat` | `/restore/data/ihc20260824/authprovidermasuat/` |

然后 `SIMPLE` + `SHRINKFILE` 收 `authprovidermasuat` 的 12.8G 日志和 `maswebkit_preprod` 的 8.6G 日志。
给 `mas_ref_owner` 映射 `db_owner`（orphaned user 处理）。**先不改**任何 `.env` / `Web.config`。

验证通过后，再单独立项做「改名切换 / 重打 migrate / 重打 maswebkit v6」。未确认前现网继续用旧库。

## 传输（确认后执行）

推荐链（数据不离开 UAT VNet，直到 runner → 笔记本 → 家）：

```
ihc-db-uat F:\icare2bak\*_20260824.bak
    -- AzCopy / PE 10.30.5.9 -->
icare2uaticare2st 临时 container（短 TTL SAS，禁止公开）
    -- 同 VNet -->
icare-uat-runner-1  (~59G 空闲，够 17G)
    -- scp -->
本机
    -- scp -->
mssql-ref:/restore/backups/ihc20260824/
```

步骤：

1. 在 `icare2uaticare2st` 建临时 container，例如 `ihc-db-bak-20260824`，默认拒绝公共访问。
2. 生成有时限的 SAS（写给源 VM，读给 runner）。不要把 SAS 写入仓库。
3. 在 `ihc-db-uat` 上 `az vm run-command` 调 `C:\Program Files\AzCopy\azcopy.exe copy F:\icare2bak\*20260824.bak <sas> --overwrite=false`。只拷今日 bak，不拷 `.trn`、不拷 `*_20260821.bak`。
4. runner 上 `azcopy copy` 下到 `/home/icareadmin/ihc-bak/`，`md5sum`。
5. 本机中转 `scp` 到 `mssql-ref:/restore/backups/ihc20260824/`，属主 `mssql:mssql`，再对 md5。
6. 目标校验完成后删 runner 本地副本和 blob container。源 `F:\icare2bak` **先留着**，不删。

备选：runner 经 SMB `\\10.100.0.4\F$\icare2bak` 直拷（445 已开），可跳过 blob；需要 Windows 凭据，且不要把密码写进命令历史/仓库。

不建议：再对 live preprod 做一次 `BACKUP`（除非用户明确要比 08-21 更新的数据）。`COPY_ONLY` 虽不拆链，仍是客户正在用的库上的 IO。

## 恢复（mssql-ref，确认后执行）

每库同一套：

```sql
-- 以 maswebkit 为例；主库改目标名为 medicalassistance_preprod_ihc20260824
RESTORE FILELISTONLY FROM DISK = N'/restore/backups/ihc20260824/maswebkit_preprod_20260824.bak';
RESTORE VERIFYONLY FROM DISK = N'/restore/backups/ihc20260824/maswebkit_preprod_20260824.bak';
RESTORE DATABASE [maswebkit_preprod]
  FROM DISK = N'/restore/backups/ihc20260824/maswebkit_preprod_20260824.bak'
  WITH MOVE N'maswebkit' TO N'/restore/data/ihc20260824/maswebkit/maswebkit.mdf',
       MOVE N'maswebkit_log' TO N'/restore/data/ihc20260824/maswebkit/maswebkit.ldf',
       RECOVERY, STATS = 10;
ALTER DATABASE [maswebkit_preprod] SET RECOVERY SIMPLE;
```

顺序：先小库（insular / prepaid / auth / webkit）证明流程，最后才是 101G 的主库。

恢复后立刻：

1. `DBCC SHRINKFILE` 收 auth 12.8G、webkit 8.6G 日志（SIMPLE + CHECKPOINT 之后）。
2. 孤立用户：`ALTER USER [mas_ref_owner] WITH LOGIN = [mas_ref_owner]` 或 `CREATE USER ... FOR LOGIN` + `db_owner`。不要在旁路库上建 ecom/sup 专用 login，除非准备切换。
3. 抽查：`sys.databases` ONLINE；表数量级；`authprovidermasuat.dbo.oauth_clients` 行数 vs 本机 `authprovidermasweb`（这是切 AUTH_DB 前必须对的）。
4. 抽查 SP 是否仍写 `medicalassistance_replicated`（旁路主库名带 `_ihc20260824` 时，三段式不会自动改名——这是**切主库名之前**要修的）。

## 切现网（第二阶段，必须再确认）

旁路验证通过后才做。会中断 mas-go-dev / mas-win / 仍连着这台 SQL 的 SIT 容器。

建议切法：停应用连接 → 把旧 catalog 改名为 `*_old` → 把旁路库改成现网名字 → 重映射 login → 重打必要补丁 → 启动应用。

现网名字保持现状，**不要**把 mas-go-dev 改成源后缀（除了主库本来就叫 `_preprod`）：

| 旁路名 | 切成现网名 |
| --- | --- |
| `medicalassistance_preprod_ihc20260824` | `medicalassistance_preprod`（旧的改 `medicalassistance_preprod_old`） |
| `maswebkit_preprod` | `maswebkit` |
| `insularsalesportal_preprod` | `insularsalesportal` |
| `masprepaid_preprod` | `masprepaid` |
| `authprovidermasuat` | **不要直接改名覆盖 `authprovidermasweb`**。先比对 `oauth_clients`；要切就改 `.env.ecom` / `.env.sup` 的 `AUTH_DB_NAME`，Webkit/HR 继续用 `authprovidermasweb` |

切主库后必做：

1. 把 Go 的 `schema_migrations`（version 46）和 `casbin_rule` 从 `*_old` 拷回，或 `migrate version 46` stamp + 视差补跑。禁止放任 deploy 从 1 打到新库。
2. 三段式 SP：旁路主库改名后，其它库里写死的 `medicalassistance_preprod_ihc20260824` 必须改回 `medicalassistance_preprod`。
3. mas-win MemberPortal：若源 `maswebkit` 没有 v6 / 那两列，按 `docs/operations/mssql-ref.md` 2026-08-20 重打。
4. 旧库改名保留至少到 smoke 通过；确认后再 `DROP`（属删除，需单独确认）。

回滚：把名字改回去（`_old` ↔ 现网名），应用不用改配置。

## 空间与回滚

- `/restore` 206G 空闲，旁路 148G 后约 58G。 bak 校验完可从 mssql-ref 删，源 `F:\` 仍保留。
- 可选（需确认才删）：`/restore/backups/mas-go-dev-before-migrate-20260517-2334/` 20G 旧 bak，可多腾 20G。
- 无 PVE 快照。旁路阶段不需要 VM 快照。切现网前再 `qm snapshot 110` 或对五套旧库 `BACKUP` 到 `/restore/backups/`。
- 源 2017 → 目标 2022 升级不可逆，不能把 mssql-ref 的 bak 还原回 `10.100.0.4`。

## 明确不做

- 不 `REPLACE` 正在用的 `medicalassistance_preprod` / `maswebkit` / `insularsalesportal` / `masprepaid` / `authprovidermasweb`（第一阶段）。
- 不动 `medicalassistance_replicated`。
- 不接 `*_uat` / `*_archive` / 裸名 `medicalassistance` / `authprovidermas_preprod`（除非要比对 oauth，单独立项）。
- 不在 `10.100.0.4` 上 `SHRINK` / 改配置 / 删 bak。已做的例外：FULL 库 `BACKUP LOG`（截断，`.trn` 留源机）+ 五库 `COPY_ONLY COMPRESSION`。
- 不把 bak 或 SAS 提交进 git。
- **不传、不还原 `*_20260821.bak`。**

## 执行前需要确认

1. ~~用 2026-08-21 还是新备~~ **已决：2026-08-24 20:52 CST 的 COPY_ONLY，17.0 GB。**
2. 第一阶段只旁路恢复、不切 mas-go-dev / mas-win，可以吗？（推荐：可以）
3. 传输走「AzCopy → `icare2uaticare2st` 临时 container → runner → 本机 → mssql-ref」，可以建短 TTL SAS 吗？
4. `authprovidermasuat` 只作为新库并存，ecom/sup 暂不改 `AUTH_DB_NAME`，可以吗？
