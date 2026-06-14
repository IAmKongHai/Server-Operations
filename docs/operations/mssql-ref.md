# mssql-ref 运维操作时间线

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
