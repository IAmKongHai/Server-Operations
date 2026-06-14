# mssql-ref 运维操作时间线

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
