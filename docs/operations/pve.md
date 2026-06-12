# pve 运维操作时间线

## 2026-06-12 14:42 CST - 验证并补齐部分 VM 的 QEMU guest agent

- 服务器：`pve`、`mssql-ref`、`mas-go-dev`
- 操作人：`Codex`
- 原因：PVE 升级与重启后发现 VM `110/mssql-ref`、`130/mas-go-dev` 均配置了 `agent: enabled=1`，但 PVE 侧 `qm agent <vmid> ping` 返回 `QEMU guest agent is not running`。用户确认立即安装并记录。
- 影响：在 `mssql-ref` guest 内新增 `qemu-guest-agent` 与依赖包 `liburing2`，启动 `qemu-guest-agent.service`；未重启 VM，未重启 SQL Server。`mas-go-dev` 因 Amazon Linux 2023 官方仓库不提供 `qemu-guest-agent`，未安装包、未启用服务、未引入第三方 RPM。
- 回滚：
  - `mssql-ref`：`sudo systemctl stop qemu-guest-agent && sudo apt-get purge -y qemu-guest-agent liburing2`，如需保留依赖则只 purge `qemu-guest-agent`。
  - `mas-go-dev`：无功能性变更需要回滚；仅保留安装尝试记录目录 `/home/ec2-user/qemu-guest-agent-install-20260612-064212`。
- 变更：
  - `mssql-ref` 安装前状态保存到 `/home/ubuntu/qemu-guest-agent-install-20260612-064134/precheck.txt`，安装后状态保存到同目录 `postcheck.txt`。
  - 在 `mssql-ref` 执行 `sudo apt-get update && sudo apt-get install -y qemu-guest-agent`，随后 `sudo systemctl enable --now qemu-guest-agent`。该 unit 在 Ubuntu 22.04 中是 `static`，但已 active running。
  - 在 `mas-go-dev` 执行 `sudo dnf install -y qemu-guest-agent`，返回 `No match for argument: qemu-guest-agent` / `Unable to find a match`；`dnf provides '*/qemu-ga' '*/qemu-guest-agent'` 也无结果。
  - 查阅 AWS 官方 AL2023 KVM 文档，确认 AL2023 当前不打包也不支持 KVM guest agent；因此未从非官方来源安装。
- 验证：
  - PVE 侧 `qm agent 110 ping` 成功，`qm agent 110 get-osinfo` 返回 Ubuntu 22.04.5 LTS 与 kernel `5.15.0-181-generic`。
  - `mssql-ref` 内 `qemu-guest-agent` 为 `active`，SQL Server `mssql-server` 仍为 `active`，`1433` 端口仍在监听。
  - PVE 侧 `qm agent 130 ping` 仍返回 `QEMU guest agent is not running`，符合 AL2023 官方限制与当前仓库状态。
  - `mas-go-dev` 内 Docker 与 GitHub Actions runner 均为 `active`，`icare-backend-api-1` 仍为 `healthy`，`http://127.0.0.1:5174/healthz` 返回 `ok`。
- 后续：
  - `mas-go-dev` 不建议为了 guest agent 引入第三方 QEMU RPM；如果强依赖 PVE guest agent 能力，应优先考虑换用官方支持 qemu guest agent 的发行版，或接受当前 AL2023 限制。

## 2026-06-12 14:24 CST - 重启 PVE 宿主机使 9.2 新内核生效

- 服务器：`pve`
- 操作人：`Codex`
- 原因：PVE 9.2 升级已安装新内核 `7.0.6-2-pve`，用户确认立即重启宿主机，使新内核生效。
- 影响：PVE 管理面与三台 VM 随宿主机重启短暂停机；未修改 VM 配置、storage、网络、防火墙、数据库或应用部署目录。
- 回滚：如新内核启动异常，可在宿主机控制台/启动菜单选择旧内核 `7.0.2-3-pve` 启动，再根据 `/root/pve-reboot-after-9.2-20260612-141818/pre-reboot.txt` 与系统日志排查。当前未发生回滚。
- 变更：
  - 重启前保存状态到 `/root/pve-reboot-after-9.2-20260612-141818/pre-reboot.txt`。
  - 执行 `systemctl reboot`。
  - 宿主机约 14:20 恢复 SSH，并进入新内核 `7.0.6-2-pve`。
  - `pve-guests` 按自启动顺序拉起 VM：14:20 启动 `110/mssql-ref`，14:21 启动 `120/mas-win`，14:22 启动 `130/mas-go-dev`，14:23 完成 `startall`。
- 验证：
  - `pveversion` 显示 `pve-manager/9.2.3`，running kernel 为 `7.0.6-2-pve`。
  - `pveproxy`、`pvedaemon`、`pvestatd`、`pve-cluster`、`rrdcached.service`、`ssh`、`pve-guests` 均为 `active`；`systemctl --failed` 无失败服务。
  - `qm list` 显示 `mssql-ref`、`mas-win`、`mas-go-dev` 均为 `running`；`pvesm status` 显示 `local`、`local-lvm`、`nvme-data` 均为 `active`。
  - 节点 RRD、VM `110` RRD、storage `local` RRD API 均能返回 JSON 数据；14:20 之后 `journalctl -p warning` 无新日志。
  - 从 PVE 验证 `192.168.2.20:1433`、`192.168.2.21:9020`、`192.168.2.21:9021` 可达；`http://192.168.2.22:5174/healthz` 返回 `ok`。
  - `mas-go-dev` 内 Docker 与 GitHub Actions runner 为 `active`，`icare-backend-api-1` 为 `healthy`，`mas-icare-portal` 已启动。
- 附带发现：
  - VM `110` 与 `130` 的 PVE 配置中有 `agent: enabled=1`，但 guest 内未安装 `qemu-guest-agent`，所以 `qm agent <vmid> ping` 返回 `QEMU guest agent is not running`。本次未修复该既有不一致；业务连通性验证正常。

## 2026-06-12 14:10 CST - 升级 Proxmox VE 到 9.2

- 服务器：`pve`
- 操作人：`Codex`
- 原因：节点级 RRD 最小修复已完成并验证稳定后，按计划将 PVE 从 9.1 系升级到 9.2 系，以获得后续 PVE 9 修复与更新。
- 影响：升级 PVE 管理面、QEMU、内核、OpenSSH、glibc 等系统包；PVE Web UI/API、SSH 与管理服务可能短暂波动。未重启宿主机，未重启 VM，未修改 VM 配置、storage、网络、防火墙、数据库或应用部署目录。新内核 `7.0.6-2-pve` 已安装，但当前运行内核仍为 `7.0.2-3-pve`，需后续单独维护窗口重启后才会生效。
- 回滚：PVE 包升级不适合做简单一键回滚；如出现异常，应先依据升级日志 `/root/pve-upgrade-9.2-20260612-140236/upgrade.log`、升级前快照目录 `/root/pve-upgrade-9.2-20260612-140236/`、`/var/log/apt/` 与 `/var/log/dpkg.log` 定位失败点，再按具体包或服务处理。不要直接删除包、清理备份或重启宿主机。
- 变更：
  - 用户确认后执行升级。
  - 升级前保存状态到 `/root/pve-upgrade-9.2-20260612-140236/`，包括 `precheck.txt`、`dpkg-packages.txt`、`etc-apt.tgz` 与 `upgrade.log`。
  - 执行 `apt-get update`。
  - 执行 `DEBIAN_FRONTEND=noninteractive apt-get -o Dpkg::Options::="--force-confold" dist-upgrade -y`，保留本地配置文件。
  - 升级结果为 `107 upgraded, 4 newly installed, 0 to remove`；新装包包括 `proxmox-kernel-7.0.6-2-pve-signed`、`proxmox-kernel-6.17.13-13-pve-signed`、`proxmox-enterprise-support-keyring`、`wireguard-tools`。
  - APT 在收尾阶段反复输出 `W: Tried to start delayed item ... python3.13 ... but failed` 警告；命令最终退出码为 0，后续 `dpkg --audit`、`apt-get check`、待升级包检查均正常。
- 验证：
  - `pveversion -v` 显示 `proxmox-ve: 9.2.0`、`pve-manager: 9.2.3`、`pve-qemu-kvm: 11.0.0-4`、`qemu-server: 9.1.16`、`proxmox-kernel-7.0: 7.0.6-2`。
  - 当前运行内核仍为 `7.0.2-3-pve`；`/boot/vmlinuz-7.0.6-2-pve` 已存在。
  - `dpkg --audit` 无输出；`apt-get check` 正常；`apt list --upgradable` 无待升级包。
  - `pveproxy`、`pvedaemon`、`pvestatd`、`pve-cluster`、`rrdcached.service`、`ssh` 均为 `active`；`systemctl --failed` 无失败服务。
  - `qm list` 显示 `mssql-ref`、`mas-win`、`mas-go-dev` 仍为 `running`；`pvesm status` 显示 `local`、`local-lvm`、`nvme-data` 均为 `active`。
  - 节点 RRD、VM `110` RRD、storage `local` RRD API 均能返回 JSON 数据；14:10 之后 `journalctl -p warning` 无新日志。
- 后续：
  - 不在本次操作中重启宿主机。若要让新内核 `7.0.6-2-pve` 生效，需要另行确认维护窗口并安排宿主机重启。
  - 升级日志包含大量重复 APT delayed item warning，保留在服务器侧用于审计，不写入仓库。

## 2026-06-12 13:50 CST - 最小修复 PVE 节点级 RRD 损坏

- 服务器：`pve`
- 操作人：`Codex`
- 原因：PVE 节点级 RRD 文件 `/var/lib/rrdcached/db/pve-node-9.0/pve` 为 0 字节，`pmxcfs` 每 10 秒持续报 `RRDC/RRD update error` 与 `mmaping file ... Invalid argument`，导致 `pvesh get /nodes/pve/rrddata --timeframe hour` 失败，Web UI 节点图表可能不显示。VM 级与 storage 级 RRD 正常。
- 影响：短暂停止并启动 `pvestatd`、`rrdcached.socket`、`rrdcached.service`，PVE 管理面状态采集/图表短暂波动；未重启 VM，未改动 VM 配置、storage、网络、防火墙、数据库或应用部署目录。节点级 RRD 历史从修复后重新开始；VM/storage RRD 历史保留。
- 回滚：如需回滚，可先停止 `pvestatd` 与 `rrdcached`，再把保留的坏文件 `/var/lib/rrdcached/db/pve-node-9.0/pve.bad.20260612-134546` 或备份 `/root/pve-node-rrd-pve.20260612-134546.bak` 放回 `/var/lib/rrdcached/db/pve-node-9.0/pve`，然后启动 `rrdcached` 与 `pvestatd`。该回滚只会恢复原损坏状态，主要用于保留现场，不是功能性恢复方案。
- 变更：
  - 用户确认后执行最小修复。
  - 修复前确认 `pve-node-9.0/pve` 为 `0` bytes，mtime 为 `2026-05-16 10:02`。
  - 停止 `pvestatd`、`rrdcached.socket`、`rrdcached.service`。
  - 复制坏文件到 `/root/pve-node-rrd-pve.20260612-134546.bak`。
  - 将原坏文件改名为 `/var/lib/rrdcached/db/pve-node-9.0/pve.bad.20260612-134546`。
  - 启动 `rrdcached.socket`、`rrdcached.service`、`pvestatd`。
- 验证：
  - 新 `/var/lib/rrdcached/db/pve-node-9.0/pve` 已重新生成，大小 `1504296` bytes。
  - `rrdcached.socket`、`rrdcached.service`、`pvestatd`、`pve-cluster` 均为 `active`。
  - `pvesh get /nodes/pve/rrddata --timeframe hour --cf AVERAGE --output-format json` 已能返回节点 RRD 数据，不再报 `rrd_fetch_r failed`。
  - VM `110`、`120`、`130` 的 RRD API 均能返回数据；`pve-storage-9.0/pve/local` RRD API 能返回数据。
  - 13:46 之后 `journalctl` 未再出现新的 `RRD/RRDC/rrdcached/pve-node` 错误。
  - `qm list` 显示 `mssql-ref`、`mas-win`、`mas-go-dev` 仍为 `running`；`pvesm status` 显示 `local`、`local-lvm`、`nvme-data` 均为 `active`。
- 后续：
  - PVE 9.2 升级仍待用户另行确认；本次未升级 PVE，也未重启宿主机。
  - 已沉淀复用方案：`docs/solutions/pve/runtime-errors/pve-node-rrd-corruption-2026-06-12.md`。

## 2026-05-28 09:45 CST - 添加同事 SSH 公钥到 mas-go-dev

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Codex`
- 原因：允许同事通过 SSH 登录 `ec2-user@192.168.2.22`，便于协作处理 MAS Go + React 内网自动部署环境。
- 影响：`hon-2026` 对应私钥持有人可以登录 `ec2-user` 用户；未重启服务，未改动 Docker、GitHub Actions runner、数据库、网络或防火墙。
- 回滚：用备份 `/home/ec2-user/.ssh/authorized_keys.bak.20260528-0945-hon-2026` 覆盖 `/home/ec2-user/.ssh/authorized_keys`，或删除注释为 `hon-2026` 的公钥行。
- 变更：
  - 备份 `/home/ec2-user/.ssh/authorized_keys` 到 `/home/ec2-user/.ssh/authorized_keys.bak.20260528-0945-hon-2026`。
  - 向 `/home/ec2-user/.ssh/authorized_keys` 追加一条 `ssh-ed25519` 公钥，注释为 `hon-2026`。
  - 保持 `/home/ec2-user/.ssh` 权限为 `700`，`authorized_keys` 权限为 `600`。
- 验证：
  - `authorized_keys` 中已能精确匹配 `hon-2026` 公钥。
  - `/home/ec2-user/.ssh/authorized_keys` 权限为 `600`，共 2 行。

## 2026-05-20 16:03 CST - 修复 mas-go-dev 前端本地 Docker build OOM

- 服务器：`pve`
- 操作人：`Codex` + 用户手动重启 VM
- 原因：`iCare-frontend-mas` 的 `Deploy to mas-go-dev` job 在 `docker build` 阶段执行 `npm run build`，Node 报 `JavaScript heap out of memory`。排查发现 VM `130/mas-go-dev` 配置为 `memory=8192`，但 `balloon=2048`，guest 实际只看到约 `2.1GiB` 内存，导致 Vite/TypeScript 构建堆空间不足。
- 影响：将 `mas-go-dev` 的 balloon 下限提高到 8 GiB，并由用户重启 VM 使配置生效；重启期间 `mas-go-dev` 后端、前端和 GitHub Actions runner 短暂中断。未修改数据库、网络、防火墙或应用代码。
- 回滚：
  - 快速回滚：`qm set 130 --balloon 2048`，然后在维护窗口重启 VM 130。
  - 配置文件回滚：参考备份 `/etc/pve/qemu-server/130.conf.bak.20260520-oom`。
- 变更：
  - 备份 `/etc/pve/qemu-server/130.conf` 到 `/etc/pve/qemu-server/130.conf.bak.20260520-oom`。
  - 执行 `qm set 130 --balloon 8192`，使 VM 130 配置变为 `memory=8192`、`balloon=8192`。
  - 尝试 QMP 热调整运行态 balloon，未能让 guest 立即释放到 8 GiB；随后用户手动重启 VM 130。
- 验证：
  - PVE 运行态显示 `balloon=8589934592`、`balloon_min=8589934592`、`maxmem=8589934592`。
  - `mas-go-dev` guest 可见内存约 `7.7GiB`，无 swap。
  - `actions.runner.cypressoai.mas-go-dev.service` 为 `active running`，并已连接 GitHub。
  - Docker 服务为 `active`，`icare-backend-api-1` 为 `healthy`，`mas-icare-portal` 已启动。
  - `http://127.0.0.1:5174/healthz` 返回 `ok`。
  - `http://127.0.0.1:5174/api/v1/health` 返回 `code=200`、database `up`。
  - 重新运行 GitHub Actions failed job 后，`iCare-frontend-mas` run `26147661747` 变为 `success`，新的 `Deploy to mas-go-dev` job `76913376725` 成功完成。
- 后续：
  - 暂不启用 swap；8 GiB 固定内存已解决本次 Node build OOM。若后续仍出现偶发 OOM，再考虑在 guest 内添加 4 GiB swap 作为兜底。
  - 观察 PVE 宿主机 available memory，避免多台 VM 高峰期同时吃满物理内存。

## 2026-05-20 12:00 CST - 验证 MAS 参考环境 VM 内存调整

- 服务器：`pve`
- 操作人：`Codex`
- 原因：用户已手动调整并重启 MAS 参考环境三台 VM，需要确认 PVE 配置、guest 可见内存和关键服务状态。
- 影响：本次仅检查和记录；实际资源调整由用户已完成。当前配置提高了 `mssql-ref` 的数据库缓存空间，并压缩 `mas-win`、`mas-go-dev` 的内存上限。
- 回滚：如调整后出现内存压力或应用异常，可在维护窗口内把 VM 内存恢复到调整前配置：`mssql-ref=8192 MiB`、`mas-win=8192 MiB`、`mas-go-dev=16384 MiB`，并按 `mssql-ref -> mas-win -> mas-go-dev` 顺序重启验证。
- 变更：
  - `mssql-ref`：`memory=20480`，6 vCPU，无 balloon 配置。
  - `mas-win`：`memory=4096`，`balloon=2048`，4 vCPU。
  - `mas-go-dev`：`memory=8192`，`balloon=2048`，4 vCPU。
  - 三台 VM 均处于 `running`，并保留原有 `onboot` 与 `startup` 顺序。
- 验证：
  - PVE 宿主机内存：总计约 `31GiB`，available 约 `12GiB`，swap 使用 `0B`。
  - `mssql-ref` guest 可见内存约 `19GiB`，`mssql-server` 为 `active`，本地 SQL Server 查询返回版本 `16.0.4252.3`。
  - `mas-win` QEMU guest agent ping 正常，`192.168.2.21:9020` 和 `192.168.2.21:9021` 端口开放。
  - `mas-go-dev` guest 当前可见内存约 `5.8GiB`，Docker 容器 `icare-backend-api-1` 为 `healthy`，`mas-icare-portal` 已启动；GitHub Actions runner 服务 `actions.runner.cypressoai.mas-go-dev.service` 为 `active running`。
- 后续：
  - 观察 SQL 查询高峰时 PVE 宿主机 available memory、swap、`mssql-ref` 内 `vmstat` 的 `wa/st` 是否下降。
  - 如 `mas-go-dev` 后续 Docker build 内存不足，再考虑把其上限从 8 GiB 调回 10-12 GiB，或清理构建缓存。

## 2026-05-20 11:04 CST - 添加同事 SSH 公钥

- 服务器：`pve`
- 操作人：`Codex`
- 原因：允许同事通过 SSH 登录 PVE 宿主机，便于后续协作处理虚拟化与 MAS 参考环境相关工作。
- 影响：`hon-2026` 对应私钥持有人可以登录 PVE 宿主机的 `root` 用户；未重启服务，未改动 VM、网络、防火墙或数据库。
- 回滚：用备份 `/root/.ssh/authorized_keys.bak.20260520-110405` 覆盖 `/root/.ssh/authorized_keys` 当前目标文件，或删除注释为 `hon-2026` 的公钥行。
- 变更：
  - 确认 `ssh pve` 登录用户为 `root`，`/root/.ssh/authorized_keys` 指向 `/etc/pve/priv/authorized_keys`。
  - 备份当前 `authorized_keys` 内容到 `/root/.ssh/authorized_keys.bak.20260520-110405`。
  - 向 `/root/.ssh/authorized_keys` 追加一条 `ssh-ed25519` 公钥，注释为 `hon-2026`。
  - 保持 `/root/.ssh` 权限为 `700`，`authorized_keys` 实际目标权限为 `600`。
- 验证：
  - `authorized_keys` 中已能精确匹配 `hon-2026` 公钥。
  - `/root/.ssh/authorized_keys` 仍是指向 `/etc/pve/priv/authorized_keys` 的符号链接。
  - `/root/.ssh` owner 为 `root:root`，权限 `700`；`authorized_keys` 实际目标 owner 为 `root:www-data`，权限 `600`，共 2 行。
- 后续：
  - 如需撤销访问，删除 `hon-2026` 对应公钥行，或恢复本次备份。
