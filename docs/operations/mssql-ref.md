# mssql-ref 运维操作时间线

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`mssql-ref`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN。ioc=0。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-07-21 14:15 CST - 链路决议：继续经 tizi-cyp 跳板；不修家宽 UPnP

- 服务器：`mssql-ref`（及家宽 underlay）
- 操作人：`Grok` / 用户确认
- 原因：评估 TS direct / Peer Relay 后维持现状。
- 影响：**无变更**。入站仍 `0.0.0.0:1433`；SIT 经 `tizi-cyp` `100.88.178.78` 跳板访问。
- 网络结论（只读）：
  - 本机 TS：`MappingVariesByDestIP: true`，`PortMapping` 空；到 `tizi-cyp` 为 DERP。
  - 家宽 OpenWrt `miniupnpd` **未运行**（用户决定 **不修**）；WAN CGNAT `100.65.11.174`，STUN 外层 `112.117.237.237`。
  - **备选**：`km-landui` Peer Relay（未部署），见 `docs/operations/dev-cypresso.md` 2026-07-21 14:15。
- 回滚：无。

## 2026-07-21 13:08 CST - 只读确认与 dev-cypresso 的 Tailscale 路径为 DERP 中继

- 服务器：`mssql-ref`（LAN `192.168.2.20` / TS `100.124.140.78`）
- 操作人：`Grok`
- 原因：配合排查 `dev-cypresso` → 本机高延迟。
- 影响：**只读**。跑 `tailscale netcheck` / `status`，未改服务或网络。
- 验证：
  - 本机 Nearest DERP：**Kunming**（~4.5ms）；`MappingVariesByDestIP: true`。
  - 到 `dev-cypresso`：`active; relay "iad"`，`CurAddr` 空（无 direct）。
  - 到 `mas-go-dev`：`active; direct 192.168.2.22:41641`（同 LAN 正常）。
- 结论：跨洋 peer（美东 AWS ↔ 国内家宽）未打洞成功，流量经 DERP，RTT ~250ms+ 属预期；**已在 Tailscale 内**，不是公网裸连。
- 回滚：无。
- 详见：`docs/operations/dev-cypresso.md` 同日条目。

## 2026-07-18 09:30 CST - 只读确认 preprod 迁移状态与双路径并发 migrate

- 服务器：`mssql-ref`（LAN `192.168.2.20` / TS `100.124.140.78`）
- 操作人：`Grok`
- 原因：配合排查 iCare-backend `Deploy to mas-go-dev` migrate applock 失败（run `29587500204`）。
- 影响：**只读**。用 `mas_ref_owner` + `sqlcmd` 查 `medicalassistance_preprod`；未重启 `mssql-server`、未改数据。
- 验证：
  - 本机同时监听 LAN 与 Tailscale；SIT Server 的 `DB_HOST=100.124.140.78` 与 mas-go-dev 的 `192.168.2.20` 指向同一实例。
  - `dbo.schema_migrations`：`version=26`，`dirty=0`。
  - `mas_ref_owner` 无 `VIEW SERVER PERFORMANCE STATE`，`sys.dm_tran_locks` / sessions 查询被拒（不影响根因判断）。
  - SQL Server 服务自 2026-07-14 起持续 active。
- 根因摘要：Deploy to Server 与 Deploy to mas-go-dev 并发 `migrate up` 争用 golang-migrate 的 Session applock。
- 回滚：无。
- 详见：`docs/solutions/mas-go-dev/workflow-issues/concurrent-migrate-applock-with-server-deploy-2026-07-18.md`

## 2026-07-16 14:51 CST - 清空两张 oauth 历史/备份大表以省开发环境空间

- 服务器：`mssql-ref`（`192.168.2.20`）
- 操作人：`Grok`
- 原因：用户要求清空以下两张大体量表，节省开发/参考环境存储：
  - `authprovidermasweb.dbo.oauth_access_tokens_old`（约 510 万行历史）
  - `maswebkit.dbo.oauth_access_tokens_Backup`（约 512 万行备份）
- 影响：
  - 上述两表数据已全部删除（`TRUNCATE`），行数归零。
  - **未动** `authprovidermasweb.dbo.oauth_access_tokens`（当前表，清空前/后均为 4 行）。
  - 无 FK 引用这两张表；未重启 SQL Server；未 shrink 数据文件。
  - 注意：`TRUNCATE` 释放的是库内页，**磁盘上 .mdf 文件尺寸不会自动变小**；`authprovidermasweb` data 仍约 10.7 GB，`maswebkit` data 仍约 5.9 GB。若要真正回收宿主机磁盘，需另做 `DBCC SHRINKFILE`（本次未做）。
- 备份：参考/测试库上的历史 token 备份表；用户明确要求清空。未另做 .bak（原 Backup 表本身即快照副本，且 `oauth_access_tokens` 当前表保留）。
- 回滚方式：
  - 无法从本机自动恢复已截断行；若仍需要历史 token，须从外部 `.bak` / 其它环境恢复。
  - 表结构仍在，应用若只依赖当前 `oauth_access_tokens` 不受影响。
- 变更时序：
  1. 清空前行数：`_old` = 5,104,639；`Backup` = 5,122,679；当前 `oauth_access_tokens` = 4。
  2. 确认无 FK 引用这两张表。
  3. `TRUNCATE TABLE authprovidermasweb.dbo.oauth_access_tokens_old;`
  4. `TRUNCATE TABLE maswebkit.dbo.oauth_access_tokens_Backup;`
- 验证：
  - 两表 `COUNT(*)` 均为 **0**。
  - `authprovidermasweb.dbo.oauth_access_tokens` 仍为 **4** 行。

## 2026-07-16 14:19 CST - 只读溯源 oauth_access_tokens_Backup 原表与同构表

- 服务器：`mssql-ref`（`192.168.2.20`）
- 操作人：`Grok`
- 原因：用户询问是否有与 `maswebkit.dbo.oauth_access_tokens_Backup` 字段完全相同的表，以及“Backup”原表在哪里。
- 影响：仅只读比对 `sys.columns` / 行数 / id 交集，未改 schema / 数据 / 服务。
- 备份：无变更，无需备份。
- 回滚方式：无变更，无需回滚。
- 结论：
  1. **字段完全一致**（列名、类型、max_length、precision、scale、nullable、顺序）的表有 2 张，均在 `authprovidermasweb`：
     - `authprovidermasweb.dbo.oauth_access_tokens`
     - `authprovidermasweb.dbo.oauth_access_tokens_old`
  2. `maswebkit` 库内除 Backup 本身外，**没有**同构表；全实例也只有上述三张相关表。
  3. **原表在 auth 库**：`authprovidermasweb.dbo.oauth_access_tokens`（现表几乎空，大历史在 `_old`）。
  4. 行数：Backup `5,122,679`；`_old` `5,104,639`；当前 `oauth_access_tokens` `4`。
  5. Backup 中 `5,104,417` 个 id 落在 `_old`，`18,262` 个 id 不在 `_old`；与当前表 id 交集为 `0`。
  6. 存储特征：Backup 为 **HEAP**（无 PK/索引，创建于 `2025-12-02`，像 `SELECT INTO` 跨库备份）；`_old` 保留原 PK 名 `PK_oauth_access_tokens` 与业务索引名；当前表为 `2026-05-20` 重建，索引名带 `_copy1`。
  7. `created_on` 范围：Backup `2023-07-01`～`2025-11-28`；`_old` 同起点到 `2026-05-20`；当前 `2026-07-11`～`2026-07-16`。
- 推断时间线（只读证据）：
  - 约 2025-12-02：从 auth 的 oauth 表拷贝到 `maswebkit.dbo.oauth_access_tokens_Backup`。
  - 约 2026-05-20：auth 侧把大表改名为 `oauth_access_tokens_old`，并重建空的 `oauth_access_tokens` 继续承接新登录。

## 2026-07-16 13:48 CST - 只读检查 maswebkit 是否存在 dbo.oauth_access_tokens

- 服务器：`mssql-ref`（`192.168.2.20`）
- 操作人：`Grok`
- 原因：用户询问 `maswebkit` 库内是否存在表 `dbo.oauth_access_tokens`。
- 影响：仅只读查询 `sys.tables`，未改 schema / 数据 / 服务。
- 备份：无变更，无需备份。
- 回滚方式：无变更，无需回滚。
- 验证：
  - `sys.tables` 精确匹配 `oauth_access_tokens`：**不存在**。
  - 名称含 `oauth_access_token` 的表仅有：`dbo.oauth_access_tokens_Backup`。

## 2026-07-16 13:45 CST - 只读查询 maswebkit.dbo.oauth_access_tokens_Backup 行数

- 服务器：`mssql-ref`（`192.168.2.20`）
- 操作人：`Grok`
- 原因：用户要求确认库 `maswebkit` 表 `dbo.oauth_access_tokens_Backup` 当前有多少行。
- 影响：仅只读 `COUNT_BIG(*)`，未改 schema / 数据 / 服务 / 网络。
- 备份：无变更，无需备份。
- 回滚方式：无变更，无需回滚。
- 变更时序：
  1. `ssh mssql-ref`，用 `sa` + `/opt/mssql-tools18/bin/sqlcmd -C` 连接本地 SQL Server。
  2. 在库 `maswebkit` 执行：`SELECT COUNT_BIG(*) FROM dbo.oauth_access_tokens_Backup;`
- 验证：查询成功返回 **5,122,679** 行。

## 2026-07-14 11:40 CST - CYP-1302：主机时区改 Asia/Manila 并重启 SQL Server

- 服务器：`mssql-ref`（`192.168.2.20` / TS `100.124.140.78`）
- 操作人：`Grok`（对应 Jira `CYP-1302` 第 1 项，用户明确要求改时区并重启 SQL Server）
- 原因：iCare 参考库与老 MAS 对齐，库内 `datetime` 一律存菲律宾本地墙钟（PHT）。原先 OS 时区 `Etc/UTC`，`GETDATE()` 写 UTC，与 17k 历史审计行的 PHT 语义混在同一列。
- 影响：
  - OS 时区：`Etc/UTC` → `Asia/Manila`（PST, +0800）。
  - `mssql-server` 短暂重启（约数秒～十几秒）；1433 重新监听后业务可连。
  - 未改 schema / 数据 / 防火墙 / Tailscale。
- 备份：时区为可逆 `timedatectl` 配置，无需文件备份；改前状态已记录（`Time zone: Etc/UTC`，本地时间与 UTC 一致）。
- 变更时序：
  1. 改前只读：`timedatectl` = `Etc/UTC`，`mssql-server` active。
  2. `sudo timedatectl set-timezone Asia/Manila`。
  3. `sudo systemctl restart mssql-server`（ticket 明确要求重启后 OS 时区才对 `GETDATE()` 生效）。
  4. 确认 `ss` 上 `0.0.0.0:1433` / `*:1433` 重新监听，errorlog 显示引擎完成启动。
- 验证：
  - `timedatectl`：`Time zone: Asia/Manila (PST, +0800)`；本地约 `11:40`，UTC 约 `03:40`。
  - `/etc/localtime` → `/usr/share/zoneinfo/Asia/Manila`；`/etc/timezone` = `Asia/Manila`。
  - 经 `mas-go-dev` 上 `sqlcmd` 连 `192.168.2.20:1433`：
    - `CURRENT_TIMEZONE()` = `(UTC+08:00) Kuala Lumpur, Singapore`（Linux `Asia/Manila` 映射到 Windows 等价 UTC+8 时区名，与 ticket 所述 `Singapore Standard Time` 同偏移；菲律宾无夏令时）。
    - `GETDATE()` ≈ `2026-07-14 11:40`（PHT 墙钟）。
    - `GETUTCDATE()` ≈ `2026-07-14 03:40`（UTC）。
- 回滚：
  ```bash
  ssh mssql-ref 'sudo timedatectl set-timezone Etc/UTC && sudo systemctl restart mssql-server'
  ```
  回滚后新写入的 `GETDATE()` 会再变回 UTC 墙钟；已写入的 PHT 行不会自动回退。
- 备注：本条只完成 CYP-1302 运维侧第 1 项。后端容器 `TZ` 见 `dev-cypresso.md` / `mas-go-dev.md` 同日条目；代码口径（GORM `NowFunc`、读写 Format 等）仍待应用仓库改动。

## 2026-07-11 15:32 CST - 协助排查 dev-cypresso 到 MSSQL 的短暂 Tailnet 单向断联（只读）

- 服务器：`mssql-ref`（TS `100.124.140.78` / LAN `192.168.2.20`）
- 操作人：`Codex`
- 原因：`dev-cypresso` 的 iCare backend GitHub Actions 部署在 migrate 阶段连接本机 SQL Server `100.124.140.78:1433` 超时。
- 影响：仅只读检查，未改 Tailscale、SQL Server、网络或防火墙，也未重启任何服务。
- 检查结果：`tailscaled` active；SQL Server 进程正常，监听 `0.0.0.0:1433` 与 `*:1433`；本机到 `127.0.0.1:1433`、自身 Tailnet IP `100.124.140.78:1433` 均可连接；内存可用约 4.5Gi、根分区使用 12%。因此排除 SQL Server 停止、端口未监听和资源耗尽。
- 链路现象：异常期间 `mssql-ref -> dev-cypresso` 的 Tailscale ping 第二次可经 `32.192.186.193:41641` 响应，而 `dev-cypresso -> mssql-ref` 初始持续超时，呈单向性。随后 `dev-cypresso` 侧自行恢复到 direct `89.208.242.203:50249`，1433 TCP 恢复可达；推断为短暂 Tailscale/NAT 数据路径异常。
- 回滚：无变更，无需回滚。
- 后续：如复发，先在两端保存 `tailscale ping`、`tailscale status`、`journalctl -u tailscaled` 证据；在用户确认后，优先尝试仅重启本机 `tailscaled`，SQL Server 不需重启。

## 2026-07-10 11:00 CST - 修复 Tailscale 未直连：独立 UDP 端口 41642 后建立 direct

- 服务器：`mssql-ref`（TS `100.124.140.78` / LAN `192.168.2.20`）
- 操作人：`Grok`（用户授权直接修复）
- 原因：办公室客户端访问 MSSQL 极慢；根因是 Tailscale 未打洞成功、全程 DERP(km)，RTT 数百毫秒～1s+。
- 根因细化：
  - 家里多台节点（`pve` / `mssql-ref` 等）原先都绑定默认 `PORT=41641`，同公网出口 `112.117.237.252` 下对称 NAT（`MappingVariesByDestIP`）时容易打洞失败。
  - 对照：同网的 `mac-mini` 已能与办公室客户端 **direct**，证明链路本身可打通。
  - `km-landui`（`43.228.79.237`）上已有 `derper`（`:443` + STUN `3478`，hostname `derp.local`）；ACL 虽有 derpMap，但 **证书不合格导致未生效**（见 `docs/operations/km-landui.md`）。本次未依赖它，靠独立 UDP 端口打洞完成修复。
- 变更：
  1. 重启 `mssql-ref` / `pve` / 本机 `tailscaled` 尝试恢复（单独重启不够）。
  2. 将 `mssql-ref` 的 `/etc/default/tailscaled` 中 `PORT` 改为 **`41642`**，并 `systemctl restart tailscaled`。
  3. 将 `pve` 的 `PORT` 改为 **`41643`**（避免继续与默认 41641 类节点冲突；见 `docs/operations/pve.md`）。
- 影响：
  - `tailscaled` 短暂重连（数秒）；SQL Server 进程未重启，LAN 访问不受影响。
  - 办公室 → `100.124.140.78` 建立 **direct**（`via 112.117.237.252:41364`）。
- 验证（修复后，办公室 MacBook Air）：
  - `tailscale status`：`mssql-ref ... active; direct 112.117.237.252:41364`
  - `tailscale ping mssql-ref`：`via 112.117.237.252:41364 in 8ms`（不再是 `via DERP(km)`）
  - `ping 100.124.140.78`：稳定约 **8–10 ms**
  - TCP `100.124.140.78:1433` 建连平均约 **9–16 ms**（修复前常 500ms–1s+）
  - 经子网路由的 `192.168.2.20:1433` 仍依赖 `pve`（当时仍偏 DERP），建连约 **70–100 ms**，已比修复前明显好转；**连库优先用 TS IP `100.124.140.78` 或 MagicDNS `mssql-ref` 以走 direct**。
- 回滚：
  ```bash
  ssh mssql-ref 'sudo sed -i "s/^PORT=.*/PORT=\"41641\"/" /etc/default/tailscaled && sudo systemctl restart tailscaled'
  ```
- 后续可选：
  - 若仍需 `km-landui` 自定义 DERP：域名 + Let's Encrypt（不要 `derp.local` 自签），见 `docs/operations/km-landui.md`。
  - 给 `mas-go-dev` 等家宽节点也分配互不冲突的 `PORT`，减少再踩坑。

## 2026-07-10 10:48 CST - 客户端感觉库极慢：SQL 本体正常，问题在 Tailscale DERP

- 服务器：`mssql-ref`（`192.168.2.20` / TS `100.124.140.78`）
- 操作人：`Grok` + 用户确认
- 原因：用户反馈内网 MSSQL 极慢；从 PVE 宿主机起做只读排查后，用户确认是 Tailscale 未直连。
- 影响：只读排查，未改 SQL / 系统 / 网络配置，未重启。
- 验证（guest 侧正常）：
  - `mssql-server` active，进程 `sqlservr` RSS 约 13Gi，guest 内存 12/17Gi used、swap 0，load ~0。
  - 磁盘 `/` 12%、`/restore` 45%；无 guest memory/io pressure 异常。
  - 活跃 1433 连接多数来自 Tailscale 客户端；局域网侧仅见 `mas-go-dev`（`192.168.2.22`）。
- 根因与完整证据链见 `docs/operations/pve.md` 与 `docs/operations/konghai-macbook-air.md` 同时间条目。
- 回滚：无变更。

## 2026-06-30 17:00 CST - 设置一次性定时重启以加载新内核

- 服务器：`mssql-ref`（`192.168.2.20`）。
- 操作人：`Codex`
- 原因：安装 Tailscale 时 apt 提示 VM 已安装新内核但当前仍运行旧内核；用户确认在明天凌晨 3 点执行一次性重启。
- 计划重启时间：
  - `2026-07-01 03:00 CST`
  - VM 本地时间：`2026-06-30 19:00 UTC`（VM 时区为 `Etc/UTC`）
- 影响：
  - VM 会短暂离线。
  - SQL Server、SSH、Tailscale 会随 VM 重启中断。
  - 未设置 crontab 或循环任务，仅登记一次性 systemd shutdown。
- 回滚 / 取消：
  - 在重启执行前运行 `sudo shutdown -c` 可取消本次定时重启。
- 重启前预检：
  - 当前 VM 时间：`Tue Jun 30 09:00:05 AM UTC 2026`
  - 当前运行内核：`5.15.0-181-generic`
  - 已安装新内核：`5.15.0-185-generic`
  - `/run/reboot-required` 存在。
  - `mssql-server`：`active`
  - `tailscaled`：`active`
  - Tailscale IP：`100.124.140.78`
  - SQL Server 监听：`0.0.0.0:1433` 与 `*:1433`
  - 从本机测试 `100.124.140.78:1433` TCP 连接成功。
  - 根分区 `/` 使用率约 `10%`。
- 做了什么：
  1. 执行一次性定时重启：
     ```bash
     sudo shutdown -r 19:00 "Scheduled one-time reboot to load kernel 5.15.0-185-generic; target time 2026-07-01 03:00 CST"
     ```
  2. 命令返回：`Reboot scheduled for Tue 2026-06-30 19:00:00 UTC, use 'shutdown -c' to cancel.`
  3. 读取 `/run/systemd/shutdown/scheduled`，确认：
     - `MODE=reboot`
     - `WALL_MESSAGE=Scheduled one-time reboot to load kernel 5.15.0-185-generic; target time 2026-07-01 03:00 CST`
- 后续验证计划：重启窗口后确认 `uname -r` 是否变为 `5.15.0-185-generic`，并验证 `mssql-server`、`tailscaled`、`100.124.140.78:1433` 是否恢复。

## 2026-06-30 16:41 CST - 记录 Tailscale IP 并验证 MSSQL 端口可达

- 服务器：`mssql-ref`（`192.168.2.20`）。
- 操作人：`Codex`
- 原因：用户已完成 Tailscale 登录，需要记录该 VM 的 Tailscale IP，并确认是否可通过该 IP 访问 VM 内 MSSQL 服务。
- 影响：只读查询与连通性测试，未改 Tailscale、SQL Server、防火墙或数据库配置。
- 当前 Tailscale IP：`100.124.140.78`
- 做了什么：
  1. 在 VM 上执行 `tailscale ip -4`，确认 IP 为 `100.124.140.78`。
  2. 检查 SQL Server 监听：`sqlservr` 正在监听 `0.0.0.0:1433` 与 `*:1433`。
  3. 检查 `ufw`：状态为 `inactive`。
  4. 从本机执行 `nc -vz -w 3 100.124.140.78 1433`。
- 验证结果：
  - `100.124.140.78:1433` TCP 连接成功。
  - 可使用 `100.124.140.78,1433` 作为 SQL Server 地址，前提是访问端也在同一 Tailnet 且 ACL 允许访问。
- 回滚：无配置变更，无需回滚。

## 2026-06-30 16:35 CST - 安装 Tailscale 客户端（未加入 Tailnet）

- 服务器：`mssql-ref`（`192.168.2.20`），参考/测试数据库 VM，改系统包前仍按需记录。
- 操作人：`Codex`
- 原因：用户要求检查并安装 Tailscale，便于后续把该 VM 纳入 Tailscale 网络管理。
- 影响：
  - 新增 Tailscale 官方 apt 源与 keyring：
    - `/etc/apt/sources.list.d/tailscale.list`
    - `/usr/share/keyrings/tailscale-archive-keyring.gpg`
  - 安装 `tailscale` 与 `tailscale-archive-keyring` 包；`tailscaled.service` 被 systemd 启用并启动。
  - 未执行 `tailscale up`，因此该 VM 尚未加入任何 Tailnet，状态仍为 `Logged out`。
  - 未重启 VM，未改防火墙，未改数据库。
- 回滚：
  - 卸载包：`sudo apt purge tailscale tailscale-archive-keyring`
  - 删除源文件：`sudo rm /etc/apt/sources.list.d/tailscale.list`
  - 需要彻底清理状态时再删除 `/var/lib/tailscale/`（当前未登录，通常无有效节点状态）。
- 做了什么：
  1. 预检查确认 `tailscale` / `tailscaled` 命令不存在，`tailscaled` systemd unit 不存在，`dpkg-query` 无已安装包记录。
  2. 读取 `/etc/os-release` 确认 Ubuntu codename 为 `jammy`。
  3. 从 Tailscale 官方源写入 `jammy` 对应 keyring 与 apt source。
  4. 执行 `sudo apt-get update` 与 `sudo DEBIAN_FRONTEND=noninteractive apt-get install -y tailscale`。
- 验证结果：
  - `tailscale version`：`1.98.8`
  - `systemctl is-enabled tailscaled`：`enabled`
  - `systemctl is-active tailscaled`：`active`
  - `tailscale status`：`Logged out.`
- 备注：安装过程中 apt 提示当前运行内核 `5.15.0-181-generic` 不是已安装的期望版本 `5.15.0-185-generic`，并提示可考虑重启加载新内核；本次未执行任何重启。

## 2026-06-22 09:38 CST - 补充：对比存储过程，生成把 _preprod 缺的 146 个 SP 补全的脚本（语法验证通过，未执行）

- 服务器：`mssql-ref`（`192.168.2.20`），按生产对待。
- 操作人：`Claude`
- 原因：上一条只补了表/字段，遗漏了可编程对象。继续让 `_preprod` 成超集，补存储过程。
- 做了什么（只读对比 + PARSEONLY 校验，preprod 零改动）：
  1. **对象计数**：完整库 sql 含 1618 SP / 13 函数 / 2 视图；preprod 线上 1512 SP / 14 函数 / 2 视图。注意 preprod 的 SP 反而更多（Go 重构 + 06-19 改名工程新增）。
  2. **按对象名差集**（不按内容，因 06-19 改名后同名 SP 内容已不同）：full 有、preprod 缺 = **146 个，全部是存储过程**；函数/视图无缺失。preprod 独有 41 个。
     - 踩坑：sqlcmd `LOWER(type)` 对 'P' 返回 `'p '`（char(2) 带尾空格），首次差集因分隔符错位误报"全缺"；改为只按对象名（去空白）比对才正确。
  3. **提取 DDL**：从 full.sql 抠出 146 个 SP 的完整定义（含 SET 包裹），生成 `import_sp_into_preprod_20260622.sql`（460KB）+ 清单 `import_sp_checklist_20260622.tsv`。
  4. **核验**：146 个 SP 定义内**无 medicalassistance_replicated 跨库引用**（不会重新引入断链）；全部通过 `SET PARSEONLY` 语法校验。
- 影响：仅生成脚本，未执行。preprod 对象数不变。
- 执行顺序：**必须先跑 import_into_preprod（表/列）再跑本 SP 脚本**——多个 SP 引用第一步新建的表（如 tblbatchloamappingdetails / tbldoctorewtjournal）。已写进 SP 脚本头部注释。
- 其中 80 个 SP 带 v2~v7 版本号后缀（老系统功能迭代版），按用户决策全补。
- 回滚：脚本未执行，无需回滚；执行前须备份 preprod。
- 验证结果：PARSEONLY 全过；无 _replicated 引用；preprod 未改动。

## 2026-06-22 08:50 CST - 对比三份 medicalassistance 结构，生成把缺失表/字段补进 _preprod 的导入脚本（已事务验证，未执行）

- 服务器：`mssql-ref`（`192.168.2.20`），按生产对待。
- 操作人：`Claude`
- 原因：目标是让 `medicalassistance_preprod`（Go 重构版使用中的库）成为结构最完整的超集，把完整库 `medicalassistance`（432 表，仅存在于结构 sql 文件，本机未恢复）有、但 `_preprod` 缺的表和字段补齐。
- 对比来源（三份，均在 `mssql-ref/sql/`）：
  - `medicalassistance_20260620_sql.sql`（完整库 full，432 表，UTF-16，SSMS 导出）
  - `medicalassistance_replicated`（线上库，388 表）与 `medicalassistance_preprod`（线上库，428 表），直连查询。
- 做了什么（全程只读 + 事务回滚，preprod 零改动）：
  1. **统一口径对比**：完整库走 sql 解析，两个线上库走 `INFORMATION_SCHEMA.COLUMNS` 直连查询，归一化类型表达（去 identity/default、`numeric(n)`→`numeric(n,0)`）后逐表逐字段比对。结果落 `schema_diff_replicated_vs_preprod_20260620.tsv`、两库列清单 `columns_*_20260621.tsv`。
  2. **full→preprod 差集**：完整库有、preprod 缺 = 13 表 + 40 列（21 张共有表）；另有 20 处同名列类型不一致（preprod 多为主动改宽，非缺失，不动）。
  3. **生成导入脚本** `import_into_preprod_20260622.sql`：
     - 第一部分新建 **11 张表**（排除 2 张脱敏临时表 `tblcompany_maskingbackup`/`tblmembers_maskingbackup`），DDL 直接抠自完整库 sql（含主键、`IF OBJECT_ID IS NULL` 保护、去掉块内 GO）。
     - 第二部分补 **40 个字段**，缺失的 NOT NULL 列一律加 DEFAULT（数值 `0`、字符 `''`、日期 `'1900-01-01'`），避免对已有数据 ADD 失败。
  4. **真机验证**：用 `BEGIN TRAN ... ROLLBACK` 在 preprod 上实际执行全脚本（11 建表 + 40 加列）无报错后回滚；复查 preprod 表数仍 428、`tblbatchloamapping` OBJECT_ID 仍 -1，确认零改动。
- 影响：**仅生成脚本与对比产物，未对任何库执行 DDL**。preprod 结构未变。
- 关联遗留待办：本次补全清单**正好覆盖** 2026-06-19 SP 改名工程遗留的缺表/缺列例外——缺表 `tblprovidertemplate` 不在本次 13 表内（完整库也无此表，需另查来源），但缺列 `tblagents.franchisecode`、`tblproductlines.iorta`、`tblbenefitsa.iorta`、`tblcompanyclasses.cancellationdays` **均已包含在 40 列补全脚本中**，执行后可解锁对应 SP 改名。
- 回滚：脚本尚未执行，无需回滚；将来执行前须先备份 preprod（改库守则）。脚本只增不删、可重复执行。
- 验证结果：PARSEONLY 语法校验通过；事务执行+回滚通过；preprod 表数 428 不变。
- 踩坑：`mssql-scripter` 对 `medicalassistance_preprod` 稳定卡死（0 字节挂起、CPU 0%、进程睡眠），replicated 正常；已改用 `INFORMATION_SCHEMA` 直连查询替代。详见 `docs/solutions/mssql-ref/workflow-issues/`。

## 2026-06-19 15:10 CST - insularsalesportal 66 个 SP 跨库引用 _replicated 改名 _preprod（全三库工程收口，5 例外遗留）

- 服务器：`mssql-ref`（`192.168.2.20`），按生产对待，已先备份（见 13:30 记录）。
- 操作人：`Claude`
- 原因：接上一会话，完成三库 SP 跨库引用 `medicalassistance_replicated` → `medicalassistance_preprod` 改名的最后一库 `insularsalesportal`（70 个对象）。上一会话因 `masprepaid` 撞上缺列、担心 insular 引用面更广藏更多缺表/缺列而停下，本次先全量预检再改。
- 做了什么：
  1. **全量试编译预检**（只读、零改动）：游标取 insular 70 个 SP 的 `OBJECT_DEFINITION`，`_replicated`→`_preprod` 替换后，在事务里 `DROP PROCEDURE` + 用改名定义 `CREATE`、捕获错误后 `ROLLBACK`。预检后复查 `_replicated` 计数仍 70、SP 总数仍 147，确认库未被破坏。
  2. **补缺表核对**：发现试编译走延迟名称解析，**缺表不报错、只有缺列报 Msg 207**。故另把 insular 70 SP 引用的 29 张去重表与目标库逐一比对，确认只 `tblprovidertemplate` 1 张缺失。
  3. **执行改名**：从 13:30 的备份 `.sql` 经 `sed`（首个 `CREATE PROC`→`ALTER PROC` + 库名子串替换）生成 66 个 ALTER 脚本（跳过 1 B 类 + 3 C 类例外），逐个 `sqlcmd -b` 执行。
- 影响：
  - `insularsalesportal` **66 个 A 类 SP 全部 ALTER 成功**，跨库引用改指 `medicalassistance_preprod`，断链消除。
  - 残留引用 `_replicated` 的对象 = **4**（insular 本库的 1 缺表 + 3 缺列例外，按用户决策跳过保持原样）。
  - 未动表结构与数据，仅改 SP 定义。
- 全三库累计结果：maswebkit 14/14、masprepaid 13/14、insular 66/70，共 **93 个 ALTER 成功**；遗留 **5 个例外**（B 缺表 1 + C 缺列 4，含 masprepaid 1）。
- 验证结果：
  - insular `_replicated` 残留对象 = 4（即 5 例外里属于 insular 的 4 个），`_preprod` 对象 = 74。
  - 只读 SP `sp_getmasagents @agentcode=''` 实测执行返回 agent 数据、exit=0，跨库取数不再断链。
- 回滚：任一 SP 改坏，用 `/restore/backup/sp-replicated-fix-20260619/insularsalesportal/<对象>.sql`（原始 `_replicated` 定义）`ALTER` 还原。
- 遗留待办（按用户决策暂跳过，待补表/补列或确认废弃后再改）：
  - B·缺表：`insularsalesportal.sp_getretailfranchisingdetails` → `tblprovidertemplate`
  - C·缺列：`insularsalesportal.sp_getiortapayordetails`(`tblagents.franchisecode`)、`sp_getproducttypes`(`tblproductlines.iorta`)、`sp_getroomaccommodation`(`tblbenefitsa.iorta`)、`masprepaid.sp_checkprepaidcancellationdate`(`tblcompanyclasses.cancellationdays`)
  - 详见 plan `docs/plans/2026-06-19-001-fix-mssql-ref-sp-replicated-to-preprod-plan.md` 末尾「遗留待办例外清单」。

## 2026-06-19 13:30 CST - 备份各库 SP/函数定义，准备把跨库引用 medicalassistance_replicated 改名为 _preprod

- 服务器：`mssql-ref`（`192.168.2.20`）
- 操作人：`Claude`
- 原因：核查发现 `insularsalesportal`/`masprepaid`/`maswebkit` 三库的存储过程及函数里，仍以三段式 `medicalassistance_replicated.dbo.<表>` 跨库引用了一个本机不存在的库 `medicalassistance_replicated`，会断链。计划统一改指向 `medicalassistance_preprod`（与 10:45 改名工程的同步范围一致，当时遗漏了 `_replicated` 引用）。详见 plan `docs/plans/2026-06-19-001-fix-mssql-ref-sp-replicated-to-preprod-plan.md`。
- 本次只做备份（阶段 0），尚未改任何对象。
- 影响：
  - 仅只读导出对象定义，未改库/表/SP/数据。
  - 待改对象共 **98 个**：`insularsalesportal` 70 SP、`masprepaid` 14 SP、`maswebkit` 13 SP + 标量函数 `GetTotalIBNR`。
  - 其中 `insularsalesportal.sp_getretailfranchisingdetails` 引用了目标库 `medicalassistance_preprod` 中**不存在**的表 `tblprovidertemplate`（B 类）；按用户决定仍随大批改库名，缺表问题单独留待后续补表。
- 备份位置：`/restore/backup/sp-replicated-fix-20260619/<db>/<schema>_<对象名>.sql`，逐对象一个文件，共 98 个，已校验全部含原始 `medicalassistance_replicated` 定义，可作回滚源。
- 回滚：用对应 `.sql` 重新 `ALTER`/`CREATE` 还原该对象定义。
- 验证结果：文件数 70/14/14=98，无空文件，98/98 含原始 `_replicated` 字样。

## 2026-06-19 10:45 CST - 库 medicalassistance 改名为 medicalassistance_preprod 并同步两个使用方

- 服务器：`mssql-ref`（`192.168.2.20`）
- 操作人：`Claude`
- 原因：用户要求把参考库 `medicalassistance` 统一改名为 `medicalassistance_preprod`（带 preprod 后缀）。核查现状发现：当前库名是 `medicalassistance`，两个使用方（mas-win 老 C# 系统、mas-go-dev Go 后端）都硬编码连 `medicalassistance`、工作正常，没有任何使用方在连 `medicalassistance_preprod`。与用户最初「老系统硬编码了 preprod」的表述不符，已用 AskUserQuestion 澄清，确认意图是「改库名 + 同步改所有连接串」。
- 影响：
  - `mssql-ref`：库逻辑名 `medicalassistance → medicalassistance_preprod`。仅改逻辑库名，逻辑文件名与物理文件（`/restore/data/medicalassistance_full/*.mdf|.ldf`，见 [[mssql-ref-db-files-on-restore-disk]]）、数据、权限、恢复模式（SIMPLE）均不动。
  - 改名瞬间到两边使用方改完之间有几分钟连库不可用窗口（已先停 mas-go-dev 容器、mas-win 此刻无活动连接）。
  - 同步改两个使用方（详见各自时间线）：mas-go-dev `.env.docker` 的 `DB_NAME`、mas-win `MAS-API\Web.config` 的 21 个 `initial catalog` + 1 个 `CATALOG_A`。
  - 未动其它库（`maswebkit`/`authprovidermasweb`/`insularsalesportal`/`masprepaid`），未重启 SQL Server。
  - **额外发现**：改名前查 `sys.dm_exec_sessions`，除 mas-go-dev 容器（host `c11ebb8a7926`）外，还有来自 **`Mac.lan`** 的 `go-mssqldb` 连接——即某台 Mac（疑似开发者本地）也直连此库。`SINGLE_USER WITH ROLLBACK IMMEDIATE` 会一并强杀，本地那份后端需自行把库名改到 `medicalassistance_preprod` 才能重连（不在本仓三台服务器范围，未处理）。
- 回滚：
  - 库名：`ALTER DATABASE [medicalassistance_preprod] MODIFY NAME = [medicalassistance];`
  - mas-win：用备份 `C:\MAS\Apps\MAS-API\Web.config.bak.20260619` 覆盖后回收 MAS-API 应用池。
  - mas-go-dev：用备份 `/opt/mas-go-dev/backend/.env.docker.bak.20260619` 覆盖后重建 api/worker。
- 变更：
  1. 只读核查：`sys.databases`（`medicalassistance` ONLINE/SIMPLE，目标名不存在）、`sys.dm_exec_sessions`（8~9 个 go-mssqldb 活动会话）。
  2. 先停 mas-go-dev `api`/`worker` 释放连接；仍有 `Mac.lan` 残连接挡住，普通 `MODIFY NAME` 报 `Msg 5030 could not be exclusively locked`。
  3. 用 sa 执行：`ALTER DATABASE [medicalassistance] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;` → `MODIFY NAME = [medicalassistance_preprod];` → `SET MULTI_USER;`（sa 密码从 `/root/mssql-secrets.env` 读，仅 SSH 会话内用，不落盘不进 commit）。
- 验证：
  - `sys.databases`：`medicalassistance_preprod` = `ONLINE` / `MULTI_USER`，旧名已不存在。
  - mas-go-dev：api/worker 启动日志 `database connected ... database=medicalassistance_preprod` + `maswebkit`，无 login failed，api `healthy`。
  - mas-win：ADO.NET 连库测试 `OK login=mas_ref_owner db=medicalassistance_preprod`，`http://192.168.2.21:9021/` 返回 HTTP 200。
- 相关：[[mssql-ref-mas-ref-reader-is-db-owner]]（连库账号 `mas_ref_owner`）。本次延续 2026-06-15「改库账号前先全量 grep 所有连接串」的教训——改库名同理，先摸清所有硬编码使用方再动手。

## 2026-06-17 10:20 CST - 恢复 masprepaid 参考库并授权 mas_ref_owner

- 服务器：`mssql-ref`（`192.168.2.20`）
- 操作人：`Claude`
- 原因：MAS-WEB 前端报错，排查发现代码连的 `masprepaid` 库在本实例上**根本不存在**（不是权限问题）。该库尚未从备份恢复进来。本机备份文件：`/Users/konghai/Code_local/Project/iCare/backend/db-bak/masprepaiduat-17-06-2026.bak`（8.2M，UAT 数据）。
- 影响：
  - 新建 `masprepaid` 库（从备份恢复），数据文件落在第二块盘 `/restore/data/`（`masprepaid.mdf` / `masprepaid_log.ldf`），与其它老库一致。
  - 备份来自旧版本（兼容级别 869），恢复时 SQL Server 自动升级到当前 957。
  - 给 `mas_ref_owner` 在 masprepaid 建用户并授 `db_owner` + `db_datareader`，与其它参考库对齐（见 [mssql-ref-mas-ref-reader-is-db-owner]）。
  - 恢复模式由默认 `FULL` 改为 `SIMPLE`，并收缩日志 146MB → 8.2MB（参考库无需时间点恢复，避免日志无限增长，做法同 6-14 几次收缩）。
  - 删除 VM 内备份文件 `/restore/backup/masprepaiduat-17-06-2026.bak`（本机已有备份，不在多处冗余）。
  - 未动其它库，未重启 SQL Server。
- 回滚：删除该库即可 `DROP DATABASE [masprepaid];`（本机仍有 .bak 可随时重恢复）。
- 变更：
  1. `scp` 上传 bak 到 VM，移到 `/restore/backup/` 并 `chown mssql:mssql`。
  2. `RESTORE FILELISTONLY` 确认逻辑文件名 `masprepaid` / `masprepaid_log`。
  3. `RESTORE DATABASE [masprepaid] ... WITH MOVE ... TO /restore/data/...`。
  4. `CREATE USER [mas_ref_owner] FOR LOGIN [mas_ref_owner];` + 加入 `db_owner`、`db_datareader`。
  5. `ALTER DATABASE [masprepaid] SET RECOVERY SIMPLE;` + `DBCC SHRINKFILE (N'masprepaid_log', 8);`。
  6. `rm /restore/backup/masprepaiduat-17-06-2026.bak`。
- 验证：
  - `sys.databases`：`masprepaid` = `ONLINE` / `SIMPLE`。
  - 角色核查：`mas_ref_owner` 在 masprepaid 为 `db_owner` + `db_datareader`。
  - 用 `mas_ref_owner` 账号实际登录 masprepaid 成功，`SELECT` 到 2 张表（库本身数据量很小）。
  - 收缩后 `masprepaid_log` size 8.19MB；数据文件 24MB 未动。
- 备注：库只有 2 张表，符合 UAT 参考库特征。前端报错根因是「目标库缺失」而非权限，恢复后即可连。

## 2026-06-14 22:25 CST - 收缩另三个库日志，/restore 盘回收 ~27GB

- 服务器：`mssql-ref`（`192.168.2.20`）
- 操作人：`Claude`
- 原因：承接上一条收缩 insularsalesportal 日志，检查其余用户库是否同样可清。发现 `medicalassistance` / `authprovidermasweb` / `maswebkit` **本就是 SIMPLE 模式**（无需改模式），但日志文件物理膨胀、几乎全空，尤其 `medicalassistance_log` 占 28GB（实际只用 80MB）。
- 重要发现（与既有认知差异）：这三个老库的数据/日志文件**不在系统盘**，而在第二块盘 `/dev/sdb` 挂载点 `/restore/data/<db>_full/`。系统盘 `/var/opt/mssql/data/` 只放了新导入的 `insularsalesportal`。`/restore` 盘收缩前 265G/393G（72%），是真正有空间压力的盘；系统盘则仅 7%。
- 影响：
  - 收缩三个库的日志文件（均 SIMPLE，日志重用空间充足，收缩仅回收物理空闲、不动数据、不锁表、在线操作）：
    - `medicalassistance_log`：28GB → 260MB
    - `authprovidermasweb` 日志：264MB → 65MB
    - `maswebkit` 日志：260MB → 69MB
  - `/restore` 盘占用 265G → 238G（72% → 64%），回收约 27GB。
  - 所有 `.mdf` 数据文件未动；未改恢复模式（本就 SIMPLE）；未重启 SQL Server。`medicalassistance` 是后端在连的活跃库，收缩期间不影响读写。
- 回滚：无需回滚（仅回收空闲空间）。日志会随后续事务自然回升到工作集大小，属正常，不会再涨回 28GB（那是历史一次性膨胀）。
- 变更：
  1. 只读核查：`sys.databases`（三库均 SIMPLE / NOTHING）、`sys.master_files`（真实物理路径在 `/restore/data/`）、`du` 确认 `medicalassistance_log` 实占 28G（非稀疏）、无任何日志备份历史。
  2. `DBCC SHRINKFILE (N'TopLogicAuthProvider_log', 64);`（authprovidermasweb）
  3. `DBCC SHRINKFILE (N'maswebkit_log', 64);`
  4. `DBCC SHRINKFILE (N'medicalassistance_log', 256);`
- 验证：
  - `du`：三库日志合计 ~28.5GB → 392MB（medicalassistance 260M / authprovidermasweb 65M / maswebkit 69M）。
  - `df -h /restore`：238G / 64%（原 265G / 72%）。

## 2026-06-14 22:11 CST - insularsalesportal 改 SIMPLE 并收缩日志，回收 ~362MB

- 服务器：`mssql-ref`（`192.168.2.20`）
- 操作人：`Claude`
- 原因：`insularsalesportal` 日志文件 `.ldf` 占 379MB，但实际只用了 21MB（其余空置）。该库恢复模式为 `FULL` 且无人做日志备份，`log_reuse_wait_desc=LOG_BACKUP`，日志只涨不收。作为参考/测试库，改 `SIMPLE` 更合适。
- 影响：
  - 恢复模式 `FULL → SIMPLE`：日志自动重用、不再无限增长；代价是失去时间点恢复能力（该只读参考库本就没做日志备份，无实际损失）。
  - 日志文件物理大小 379MB → 16MB，回收约 362MB 磁盘。
  - 数据文件 `.mdf` 未动（仍 9MB / 用 8.5MB），数据无变化。未重启 SQL Server，未动其它库。
- 回滚：`ALTER DATABASE [insularsalesportal] SET RECOVERY FULL;`（如需恢复 FULL 模式）。日志文件会随使用自然重新增长，无需手动扩。
- 变更：
  1. 只读核查：`sys.database_files`（log size 379MB / used 21MB）、`sys.databases`（FULL / LOG_BACKUP）。
  2. `ALTER DATABASE [insularsalesportal] SET RECOVERY SIMPLE;`
  3. `DBCC SHRINKFILE (N'insularsalesportal_log', 16);`（目标 16MB）。
- 验证：
  - `sys.database_files`：日志 size 16.2MB / used 1.1MB；数据文件不变。
  - `sys.databases`：`recovery_model_desc=SIMPLE`，`log_reuse_wait_desc=NOTHING`（健康）。
  - 物理文件 `insularsalesportal_preprod_log.ldf` 实际 17M（文件名仍含旧的 preprod，是 restore 时的物理名，不影响库名 `insularsalesportal`）。
- 备注：磁盘本不紧张（`/var/opt/mssql` 所在盘 182G 可用、占用 7%），本次主要是消除 FULL 模式下日志无限增长的隐患，顺带回收空间。

## 2026-06-14 21:12 CST - 用 mas_ref_owner 替换误导性账号 mas_ref_reader

- 服务器：`mssql-ref`（`192.168.2.20`）
- 操作人：`Claude`
- 原因：`mas_ref_reader` 这个账号名带 "reader" 但实际在各库是 `db_owner`（读写），名字误导。新建 `mas_ref_owner` 继承其全部权限，停用旧账号。
- 影响：
  - 新建服务器登录名 `mas_ref_owner`，密码沿用旧 `mas_ref_reader`（`CHECK_POLICY = OFF`，避免历史密码不合当前策略导致建号失败）。
  - 在 `mas_ref_reader` 有用户映射的 4 个库里给 `mas_ref_owner` 建用户并复制相同角色：
    - `authprovidermasweb` / `maswebkit` / `insularsalesportal`：`db_owner` + `db_datareader`
    - `medicalassistance`：`db_owner` + `db_datareader` + `icare_pii_reader`
  - 旧登录名 `mas_ref_reader` 已 `DISABLE`（仅禁用登录，未删除，库内用户映射保留）。
  - `/root/mssql-secrets.env` 新增 `MSSQL_MAS_REF_OWNER_PASSWORD`（值同旧 reader 密码），保留旧 `MSSQL_MAS_REF_READER_PASSWORD` 键作历史参考。原文件备份到 `/root/mssql-secrets.env.bak.20260614`。
  - 未删除任何库/用户，未重启 SQL Server。
- 回滚：
  - 重新启用旧账号：`ALTER LOGIN [mas_ref_reader] ENABLE;`
  - 移除新账号（如需）：各库 `DROP USER [mas_ref_owner];` 后 `DROP LOGIN [mas_ref_owner];`
  - 凭据文件：用 `/root/mssql-secrets.env.bak.20260614` 覆盖。
- 变更：
  1. `CREATE LOGIN [mas_ref_owner] WITH PASSWORD = <旧 reader 密码>, CHECK_POLICY = OFF;`（密码从 env 读，全程在 VM 内，不进 commit）。
  2. 逐库 `CREATE USER [mas_ref_owner] FOR LOGIN [mas_ref_owner];` + `ALTER ROLE [...] ADD MEMBER [mas_ref_owner];`，角色按 `mas_ref_reader` 实际映射逐一复制。
  3. `ALTER LOGIN [mas_ref_reader] DISABLE;`
  4. 在 `/root/mssql-secrets.env` 追加 owner 密码键（备份后改）。
- 验证：
  - 逐库逐角色并排对比 `mas_ref_owner` 与 `mas_ref_reader`，4 个库角色一一对应、完全一致。
  - 用 `mas_ref_owner` 实测登录成功（`SUSER_NAME()` 正确），在 `insularsalesportal` 建表/插入/删表成功。
  - 用 `mas_ref_reader` 实测登录被拒：`Login failed ... The account is disabled.`。
- 后续：
  - 若有应用/工具仍配 `mas_ref_reader` 连接，需改用 `mas_ref_owner`（密码不变）。AGENTS.md 未记录具体使用方，需用户侧确认。
  - 确认无遗留使用方且观察一段时间后，可考虑彻底 `DROP LOGIN [mas_ref_reader]` 及各库 `DROP USER`，并从 env 删除旧键。
  - **已发现的遗留使用方**：`mas-go-dev` 后端 `icare-backend-api` / `worker` 用 `mas_ref_reader` 连 `medicalassistance` / `maswebkit`，禁用后即报 500。已于 21:25 改其 `.env.docker` 切到 `mas_ref_owner` 并重建容器恢复，详见 `docs/operations/mas-go-dev.md`。该 `.env.docker` 在 VM 上手工维护、CI 不覆盖（已核查 iCare 仓库，密码不在仓库/secrets），故修改持久生效、仓库侧无需改。

## 2026-06-14 20:55 CST - 修正 mas_ref_reader 在 insularsalesportal 的权限为 db_owner

- 服务器：`mssql-ref`（`192.168.2.20`）
- 操作人：`Claude`
- 原因：上一条（20:42）按账号名字面把 `mas_ref_reader` 在 `insularsalesportal` 库只授予了 `db_datareader`（只读），是误判。核对发现该账号在本实例其它库的惯例是 `db_owner`，用户需要对 `insularsalesportal` 的写权限。
- 核对发现（`mas_ref_reader` 各处实际权限）：
  - 服务器级：无角色（非 sysadmin）。
  - `authprovidermasweb`：`db_owner` + `db_datareader`
  - `maswebkit`：`db_owner` + `db_datareader`
  - `medicalassistance`：`db_owner` + `db_datareader` + `icare_pii_reader`
  - `insularsalesportal`：（修正前）仅 `db_datareader`
- 影响：在 `insularsalesportal` 库把 `mas_ref_reader` 加入 `db_owner` 角色，使其拥有库级完全读写权限（读写数据、改 schema 等），与其它三个库的惯例一致。`db_datareader` 保留（其它库也都同时有）。未改其它库，未重启 SQL Server。
- 回滚：`ALTER ROLE [db_owner] DROP MEMBER [mas_ref_reader];`（保留 `db_datareader` 即回到只读状态）。
- 变更：`ALTER ROLE [db_owner] ADD MEMBER [mas_ref_reader];`（在 `insularsalesportal` 库内，sa 执行）。
- 验证：
  - 该库内 `mas_ref_reader` 角色为 `db_datareader` + `db_owner`。
  - 用 `mas_ref_reader` 账号实测：`CREATE TABLE` → `INSERT` → `SELECT`（1 行）→ `DROP TABLE` 全部成功，测试表已清理。
- 备注：账号名虽叫 “reader”，但在本实例的实际定位是各业务库的 `db_owner`，名字有误导性，后续不要按字面当只读账号用。

## 2026-06-14 20:42 CST - 重命名 insularsalesportal 库并授予只读账号权限

- 服务器：`mssql-ref`（`192.168.2.20`）
- 操作人：`Claude`
- 原因：把上一条导入的 `insularsalesportal_preprod` 改名为 `insularsalesportal`（去掉 preprod 后缀），并把该库的只读权限授予参考库专用账号 `mas_ref_reader`。
- 影响：
  - 数据库逻辑名 `insularsalesportal_preprod → insularsalesportal`（仅改库名，逻辑文件名与物理文件 `.mdf`/`.ldf` 路径不变，数据不动）。
  - 在该库内新建数据库用户 `mas_ref_reader`（映射到已存在的服务器登录名 `mas_ref_reader`），加入 `db_datareader` 角色——只读全表，无写权限。
  - 未改其它库，未重启 SQL Server。
- 回滚：
  - 库名：`ALTER DATABASE [insularsalesportal] MODIFY NAME = [insularsalesportal_preprod];`
  - 权限：`ALTER ROLE [db_datareader] DROP MEMBER [mas_ref_reader];` 及 `DROP USER [mas_ref_reader];`（按需）。
- 变更：
  1. 改名前检查：目标名 `insularsalesportal` 不存在、库无活动连接（`sys.dm_exec_sessions` 计数为 0），可安全 rename。
  2. `ALTER DATABASE [insularsalesportal_preprod] MODIFY NAME = [insularsalesportal];`
  3. 在 `insularsalesportal` 库内 `CREATE USER [mas_ref_reader] FOR LOGIN [mas_ref_reader];`（已存在则跳过）+ `ALTER ROLE [db_datareader] ADD MEMBER [mas_ref_reader];`。SA 密码与 reader 密码均从 `/root/mssql-secrets.env` 读取，仅用于本次 `sqlcmd`，不落盘不进 commit。
- 验证：
  - `sys.databases`：`insularsalesportal` 状态 `ONLINE`、兼容级别 `120`。
  - `mas_ref_reader` 确认属于 `db_datareader` 角色。
  - 用 `mas_ref_reader` 账号实测：可读 `dbo.tblfranchising`（1143 行）；执行 `CREATE TABLE` 被拒（`Msg 262 ... permission denied`），确认纯只读。
- 备注：库内另有 4 个从源库带来的孤立 SQL 用户（`kaseya` / `mrparnala` / `noventiq` / `eegocon`），本次未处理；它们的登录名在本实例不存在，处于孤立状态，不影响 reader 使用。

## 2026-06-14 20:27 CST - 导入 insularsalesportal_preprod 参考库

- 服务器：`mssql-ref`（`192.168.2.20`，SQL Server 2022 Developer Edition，systemd 服务）
- 操作人：`Claude`
- 原因：把 iCare 的 `insularsalesportal_preprod` 备份导入参考库 VM，供开发/集成测试使用。源备份来自本机 `iCare/backend/db-bak/insularsalesportal_preprod.bak`（8.4M）。
- 影响：
  - 新建数据库 `insularsalesportal_preprod`（之前不存在，无覆盖）。数据文件落 `/var/opt/mssql/data/insularsalesportal_preprod.mdf`（9 MB）、日志 `..._log.ldf`（379 MB）。
  - 源库版本 869（SQL 2017 级）由 SQL Server 自动升级到当前版本 957（SQL 2022），兼容级别保持 120。
  - 未改动其它现有库（`authprovidermasweb`、`maswebkit`、`medicalassistance` 等），未重启 SQL Server。
- 回滚：`DROP DATABASE [insularsalesportal_preprod];`（删除后会一并移除 `.mdf` / `.ldf`）。本机仍保留原始 `.bak`。
- 变更：
  1. 新建备份目录 `/var/opt/mssql/backup`（`mssql:mssql 770`）。
  2. `scp` 备份到 VM `/tmp`，两端 `md5` 校验一致（`3069d7a6da1f71829e9f0c62d3d41ca9`），再 `sudo mv` 到备份目录并改属主 `mssql:mssql`。
  3. 从 `/root/mssql-secrets.env` 读 `MSSQL_SA_PASSWORD`（仅在 SSH 会话内用于 `sqlcmd`，不落盘、不进 commit）。
  4. 只读验证：`RESTORE HEADERONLY`（`BackupType=1` 完整备份、`IsDamaged=0`、`HasIncompleteMetaData=0`、`Compressed=0`）、`RESTORE FILELISTONLY`（取逻辑文件名 `insularsalesportal` / `insularsalesportal_log`）、`RESTORE VERIFYONLY`（valid）。
  5. `RESTORE DATABASE [insularsalesportal_preprod] ... WITH MOVE ..., RECOVERY`，把源 Windows 路径 `F:\data` / `F:\log` 改到 Linux 的 `/var/opt/mssql/data/`。
  6. 导入完成后删除 VM 上的 `.bak`（本机已有原件，不重复存）；删除前再次 `md5` 比对确认是同一份。
- 验证：
  - `sys.databases`：`insularsalesportal_preprod` 状态 `ONLINE`、`FULL`、兼容级别 `120`。
  - 19 张用户表，数据齐全（`tblfranchising` 1143 行、`tblagentjournals` 890 行、`tblagentattachments` 842 行等）。
  - `RESTORE DATABASE successfully processed 1058 pages`，无报错。
- 关于「300MB+ 库备份只有 8MB」的疑问：正常。`FILELISTONLY` 显示数据文件实际只有 ~9 MB，所谓 300MB+ 几乎全是事务日志文件（`.ldf` 预分配 379 MB）。完整备份只存数据页 + 活动日志，不会把整个日志文件搬进 `.bak`，所以 `.bak` 远小于数据库占用，数据未丢失。
- 后续：
  - 应用/工具连这个参考库时，建议用 `/root/mssql-secrets.env` 里的只读账号（`MSSQL_MAS_REF_READER_PASSWORD` 对应账号）而非 `sa`。

## 2026-06-12 14:42 CST - 安装并启用 qemu-guest-agent

- 服务器：`mssql-ref`（PVE VM `110`，`192.168.2.20`）
- 操作人：`Codex`
- 原因：PVE 侧 VM 配置已有 `agent: enabled=1`，但 guest 内未安装 `qemu-guest-agent`，导致 `qm agent 110 ping` 返回 `QEMU guest agent is not running`。
- 影响：新增 Ubuntu 包 `qemu-guest-agent` 与依赖 `liburing2`，启动 `qemu-guest-agent.service`；未重启 VM，未重启 SQL Server，未改数据库 schema/data。
- 回滚：`sudo systemctl stop qemu-guest-agent && sudo apt-get purge -y qemu-guest-agent liburing2`。如后续发现 `liburing2` 被其他包依赖，则只 purge `qemu-guest-agent`。
- 变更：
  - 安装前状态保存到 `/home/ubuntu/qemu-guest-agent-install-20260612-064134/precheck.txt`。
  - 执行 `sudo apt-get update && sudo apt-get install -y qemu-guest-agent`。
  - 执行 `sudo systemctl enable --now qemu-guest-agent`；Ubuntu 22.04 中该 unit 为 `static`，但服务已启动。
  - 安装后状态保存到 `/home/ubuntu/qemu-guest-agent-install-20260612-064134/postcheck.txt`。
- 验证：
  - guest 内 `qemu-guest-agent` 为 `active`，包版本为 `1:6.2+dfsg-2ubuntu6.30`。
  - PVE 侧 `qm agent 110 ping` 成功，`qm agent 110 get-osinfo` 返回 Ubuntu 22.04.5 LTS 与 kernel `5.15.0-181-generic`。
  - `mssql-server` 仍为 `active`，`1433` 端口仍在监听。

## 2026-05-28 13:45 CST - 给 SQL Server 配 max server memory 上限并加 4 GB swap

- 服务器：`mssql-ref`
- 操作人：`Claude`
- 原因：承接 12:14 那条画像记录留下的隐患——SQL Server 在 Linux 上默认贪婪占内存，`max server memory = 2147483647 MB`（即未限制），RSS 已经到 14.2 GB，可用内存仅 4.8 GB，且 swap 为 0；一旦 OS 侧瞬时吃内存就会直接 OOM kill `sqlservr`。本次给 SQL Server 显式封顶并加一个安全网式的小 swap。
- 影响：
  - SQL Server 可用内存被限制为 14 GiB（原先无限制）。当前 RSS 14.2 GB 略高于上限，working set 会在后续运行中由 SQLOS 缓慢收敛，不会立即整块释放，这是正常行为。
  - 系统新增 4 GiB swap 文件 `/swapfile`，`vm.swappiness=10`（默认 60）——只在真正有内存压力时才会落盘，平时不会抖动；这台是 PVE 上的 VM，swap 写到虚拟盘，对 SSD 寿命的影响远小于裸机直接拿 swap 当 RAM 扩展。
  - 未重启任何服务，未改 schema/data。
- 回滚：
  - SQL Server 内存：`EXEC sp_configure 'max server memory (MB)', 2147483647; RECONFIGURE;`（立即生效，不需重启）。
  - swap：`sudo swapoff /swapfile && sudo rm /swapfile`，并从 `/etc/fstab` 删除 `/swapfile none swap sw 0 0` 那行（已备份到 `/etc/fstab.bak.20260528`）。
  - swappiness：`sudo rm /etc/sysctl.d/99-swappiness.conf && sudo sysctl -w vm.swappiness=60`。
- 变更：
  1. SSH `ubuntu@192.168.2.20`，从 `/root/mssql-secrets.env` 读出 `MSSQL_SA_PASSWORD`（仅在 SSH 会话中使用，不落盘也不进 commit）。
  2. 用 `/opt/mssql-tools18/bin/sqlcmd` 以 `sa` 登入本地实例：
     ```sql
     EXEC sp_configure 'show advanced options', 1; RECONFIGURE;
     EXEC sp_configure 'max server memory (MB)', 14336; RECONFIGURE;
     ```
     `sys.configurations` 中 `max server memory (MB)` 由 `2147483647 → 14336`。
  3. 备份 `/etc/fstab` → `/etc/fstab.bak.20260528`。
  4. `sudo fallocate -l 4G /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile`。
  5. 追加 `/swapfile none swap sw 0 0` 到 `/etc/fstab`，确保重启后自动挂载。
  6. 写入 `/etc/sysctl.d/99-swappiness.conf`，内容 `vm.swappiness=10`，并 `sudo sysctl -p /etc/sysctl.d/99-swappiness.conf` 即时生效。
- 验证：
  - `sqlcmd` 查 `sys.configurations`：`max server memory (MB) = 14336`，`min server memory (MB) = 16`（未改）。
  - `free -h`：`Swap: 4.0Gi / 0B / 4.0Gi`（启用且未使用）。
  - `swapon --show`：`/swapfile file 4G 0B -2`。
  - `cat /proc/sys/vm/swappiness`：`10`。
  - `ls -lh /swapfile`：`-rw------- root root 4.0G`，权限正确。
  - `tail -3 /etc/fstab` 已含 `/swapfile` 行。
  - 进程 `sqlservr` 仍 `active (running)`，未重启。
- 关于 0 swap 的早期决策：之前在 NAS/裸机上选 0 swap，前提是"内存充足、避免 SSD 无谓写入"。这台 VM 的差异是：(a) 内存前提不再成立（封顶后 OS 只剩 ~5 GB，没安全网就只能 OOM kill）；(b) 写入落在 PVE 虚拟盘而非裸 SSD，amplification 已被宿主层吸收。加 4 GB 小 swap + 低 swappiness 是性价比最高的兜底，不与原决策的精神冲突。
- 后续：
  - 观察一两天 `free -h` 和 `sar -B` 等，确认 `sqlservr` RSS 是否如预期收敛到 14 GB 以内、swap 是否始终 `Used=0`。
  - 文档维护：`docs/solutions/pve/best-practices/mas-legacy-reference-sql-vm-2026-05-16.md` 仍待更新（VM 现况 `6 vCPU / 19 GiB`，且已显式封顶 `max server memory = 14336 MB`、加了 4 GB swap）。

## 2026-05-28 12:14 CST - 校验运行时画像（容量规划用）

- 服务器：`mssql-ref`
- 操作人：`Claude`
- 原因：评估能否把 iCare 项目的 Azurite / Redis 等基础服务共栖到这台 VM 上时，需要先把"它当前是什么"摸清楚。
- 影响：纯只读 SSH 查询（`free`、`df`、`ps`、`systemctl list-units`、`which docker`），未改动任何配置或服务。
- 回滚：N/A（无写操作）。
- 关键事实（与既有文档差异要注意）：
  - **SQL Server 是宿主机 systemd 服务，不是 Docker 容器**。`systemctl` 中可见 `mssql-server.service (loaded active running)`；`which docker` / `/usr/bin/docker*` / `/snap/bin/docker*` 全部未找到，机器上**没有安装 Docker 引擎**。
  - VM 已扩容：`nproc=6`、`free -h` 显示总内存 `19Gi`。`docs/solutions/pve/best-practices/mas-legacy-reference-sql-vm-2026-05-16.md` 写的"4 vCPU / 8 GiB"已过期。
  - **内存紧张**：`sqlservr` 进程 RSS ≈ 14.2 GB（`ps -eo pid,rss,comm`），可用内存仅 `4.8Gi`。
  - **无 swap**：`Swap: 0B / 0B / 0B`。一旦内存吃满将直接 OOM kill，没有缓冲。
  - SQL Server 没有配置 `max server memory` 上限（未直接登入数据库确认，但从内存占用与 14GB 持续居高可推断）。SQL Server 在 Linux 上默认会贪婪占用，不显式封顶是潜在隐患。
  - CPU 与磁盘有富余：`load 0.09`、根分区 `/dev/sda1 194G / 13G used / 181G avail (7%)`。瓶颈仅在内存。
- 结论 / 后续：
  - **iCare 的 Azurite + Redis 不放 mssql-ref**。理由：需新装 Docker、内存只剩 4.8GB 且无 swap、SQL Server 是关键路径不宜与其他服务争内存、跨 VM 网络复杂度上升。改走 mas-go-dev 上的 `infra.compose.yaml` 方案。
  - 待处理（独立任务，在其他 session 跟进）：给 SQL Server 显式配置 `max server memory`（建议 12 GB 左右，留 7 GB 给 OS）；评估是否需要加 swap 文件。
  - 待处理（文档维护）：把 `mas-legacy-reference-sql-vm-2026-05-16.md` 的"4 vCPU / 8 GiB"更新为现况 `6 vCPU / 19 GiB`，并补一句"SQL Server 当前裸跑、未限制 max server memory"。

## 2026-05-20 11:19 CST - 修正本机 known_hosts 中的旧主机指纹

- 服务器：`mssql-ref`
- 操作人：`Codex`
- 原因：本机执行 `ssh ubuntu@192.168.2.20` 时提示 `REMOTE HOST IDENTIFICATION HAS CHANGED`，`/Users/konghai/.ssh/known_hosts` 中保存的旧 `192.168.2.20` 主机 key 与当前 VM 返回的 key 不一致。
- 影响：仅修改本机 `/Users/konghai/.ssh/known_hosts` 中 `192.168.2.20` 的主机 key 记录；未改动 VM、SQL Server、PVE 网络或 SSH 服务端配置。
- 回滚：恢复本机备份 `/Users/konghai/.ssh/known_hosts.bak.20260520-111913`，或使用 `ssh-keygen -R 192.168.2.20 -f /Users/konghai/.ssh/known_hosts` 后重新按可信指纹录入。
- 变更：
  - 从 PVE 宿主机确认 VM `110 / mssql-ref` 的网卡 MAC 为 `BC:24:11:CC:BE:98`。
  - 从 PVE 宿主机 `ip neigh show 192.168.2.20` 确认该 IP 对应 MAC 为 `bc:24:11:cc:be:98`。
  - 从 PVE 宿主机 `ssh-keyscan` 获取当前 `192.168.2.20` 的 ECDSA、RSA、ED25519 host keys。
  - 备份本机 `/Users/konghai/.ssh/known_hosts` 到 `/Users/konghai/.ssh/known_hosts.bak.20260520-111913`。
  - 删除本机旧的 `192.168.2.20` 三条 host key 记录，并写入 PVE 侧扫描到的新记录。
- 验证：
  - 新 ED25519 指纹为 `SHA256:FxesIaPzL0z1U3ZtG7HyUXTqbuhz7i04mw3QdLxxgHc`，与 SSH 报错中远端返回的指纹一致。
  - 新 ECDSA 指纹为 `SHA256:lt/NiNQ1Rct+A90rerWG1g90S9KmCgQiwu2fQ0yuumU`。
  - 新 RSA 指纹为 `SHA256:OrUZU7zsRfBovUnl7XwoBSv73M5+MRZtb/37xhJSmls`。
  - 使用 `StrictHostKeyChecking=yes` 重新执行 `ssh ubuntu@192.168.2.20` 成功，返回 `login-ok user=ubuntu host=mssql-ref`。
- 后续：
  - 如果其它机器也遇到同样报错，应先用 PVE 宿主机侧 MAC 和 host key 指纹交叉确认，再更新对应客户端的 `known_hosts`。

## 2026-05-20 10:52 CST - 添加同事 SSH 公钥

- 服务器：`mssql-ref`
- 操作人：`Codex`
- 原因：允许两位同事通过 SSH 登录 `ubuntu@192.168.2.20`，便于访问 PVE 上的 MAS 老系统 MSSQL 参考数据库 VM。
- 影响：`hon-2026` 和 `m@cypresso.ai` 对应私钥持有人可以登录 `ubuntu` 用户；未改动 SQL Server、VM、网络或系统服务。
- 回滚：用备份 `/home/ubuntu/.ssh/authorized_keys.bak.20260520-025140` 覆盖 `/home/ubuntu/.ssh/authorized_keys`，并保持权限 `600`。
- 变更：
  - 备份 `/home/ubuntu/.ssh/authorized_keys` 到 `/home/ubuntu/.ssh/authorized_keys.bak.20260520-025140`。
  - 向 `/home/ubuntu/.ssh/authorized_keys` 追加两条 `ssh-ed25519` 公钥，注释分别为 `hon-2026` 和 `m@cypresso.ai`。
  - 保持 `/home/ubuntu/.ssh` 权限为 `700`，`authorized_keys` 权限为 `600`。
- 验证：
  - `authorized_keys` 中已能精确匹配 `hon-2026` 和 `m@cypresso.ai` 两条公钥。
  - `/home/ubuntu/.ssh` owner 为 `ubuntu:ubuntu`，权限 `700`。
  - `/home/ubuntu/.ssh/authorized_keys` owner 为 `ubuntu:ubuntu`，权限 `600`，共 3 行。
- 后续：
  - 如需撤销访问，删除对应注释的公钥行，或直接恢复本次备份。
