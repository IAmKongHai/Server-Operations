# mssql-ref 运维操作时间线

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
