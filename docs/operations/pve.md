# pve 运维操作时间线

## 2026-07-05 00:16 CST - 在线扩容 mas-go-dev 系统盘到 300G

- 服务器：`pve`（VM `130/mas-go-dev`）
- 操作人：`Codex`
- 原因：`mas-go-dev` 根盘 120G 已被 GitHub Actions runner 的 Go / Docker 缓存逼近打满；用户确认按上一条评估方案扩容到 300G，以保留 CI cache、避免频繁清理影响构建速度。
- 影响：
  - VM `130/mas-go-dev` 的 `scsi0` 从 `120G` 在线扩容到 `300G`。
  - 宿主机、VM、runner、Docker 容器均未重启。
  - `nvme-data` thin pool 实际 Data 使用率仍为 `34.19%`；`vm-130-disk-1` 逻辑大小变为 `300G`，该 thin volume Data 使用率约 `39.99%`。
- 备份：
  - `/root/mas-go-dev-disk-resize-20260705-before-disk-resize/130.conf.before`
  - `/root/mas-go-dev-disk-resize-20260705-before-disk-resize/130.status.before`
  - `/root/mas-go-dev-disk-resize-20260705-before-disk-resize/pvesm.status.before`
  - `/root/mas-go-dev-disk-resize-20260705-before-disk-resize/lvs.before`
- 变更：
  1. 在 PVE 保存 VM 配置、状态、storage 与 LVM thin 状态到上述目录。
  2. 执行 `qm resize 130 scsi0 +180G`，PVE 将 `nvme-data/vm-130-disk-1` 从 `120.00 GiB` 扩到 `300.00 GiB`。
  3. PVE 输出 thin provisioning 警告：thin volume 逻辑大小总和约 `<1000.02 GiB`，略超过 `nvme-data` thin pool 大小 `<934.67 GiB` 与 VG 大小 `<953.87 GiB`。这是预期风险，后续需监控实际 Data 使用率，避免 thin pool 真的写满。
- 验证：
  - `qm config 130`：`scsi0: nvme-data:vm-130-disk-1,discard=on,iothread=1,size=300G`。
  - `pvesm status`：`nvme-data` active，Data 使用率 `34.19%`，Available 约 `644984330 KiB`。
  - `lvs`：`nvme-data/vm-130-disk-1` `300.00g`，Data 使用率 `39.99%`。
  - guest 内已同步完成分区和 XFS 扩容，详见 `docs/operations/mas-go-dev.md` 同时间记录。
- 回滚说明：磁盘与 XFS 已向前扩容，不能直接无损缩回。若后续出现问题，应基于备份配置与当前状态排查修复，不要尝试直接缩盘。

## 2026-07-05 00:12 CST - 只读评估 mas-go-dev VM 系统盘扩容方案

- 服务器：`pve`（VM `130/mas-go-dev`）
- 操作人：`Codex`
- 原因：`mas-go-dev` 根盘因 GitHub Actions runner 的 Go / Docker 缓存接近打满；用户要求从宿主机侧查看磁盘情况并决定扩容方案。
- 影响：本次仅做只读检查，未执行 `qm resize`、未改 VM 配置、未改 guest 分区 / 文件系统、未重启 VM 或宿主机。
- 宿主机存储现状：
  - `qm list`：VM `130/mas-go-dev` running，当前 `BOOTDISK=120G`。
  - `pvesm status`：
    - `nvme-data` 为 `lvmthin`，总量约 `934.7GiB`，Data 使用率 `34.19%`，可用约 `615GiB`。
    - `local-lvm` 为 `lvmthin`，总量约 `350.8GiB`，Data 使用率 `3.45%`，但 `mas-go-dev` 当前不在该池。
  - `qm config 130`：系统盘为 `scsi0: nvme-data:vm-130-disk-1,discard=on,iothread=1,size=120G`；`agent: enabled=1` 但 guest agent 不运行（AL2023 既有限制）。
  - `lvs`：`nvme-data/vm-130-disk-1` thin volume 逻辑大小 `120G`，Data 使用率 `99.99%`，与 guest 根盘已满吻合。
- guest 只读确认：
  - `lsblk`：`/dev/sda` `120G`，`/dev/sda1` 为根分区，`xfs`，挂载 `/`；`/dev/sda128` EFI 与 `/dev/sda127` BIOS boot 位于磁盘开头，`/dev/sda1` 在后面，扩容后可继续向后增长。
  - `df -hT /`：`/dev/sda1` `120G`，已用约 `118G`，可用约 `2.5G`，使用率 `98%`。
  - guest 内已有 `/usr/bin/growpart` 与 `/usr/sbin/xfs_growfs`。
- 方案判断：
  - 建议将 VM `130` 系统盘从 `120G` 扩到 `300G`（即 `qm resize 130 scsi0 +180G`）。
  - 理由：当前要保留 Go build/test cache 来换 CI 时间，不能依赖频繁清 cache；`nvme-data` 实际仍有约 `615GiB` 可用，在线扩容不会立刻占用 180G 实体空间。
  - 风险：`nvme-data` 是 thin pool，扩到 `300G` 后各 VM 的逻辑磁盘总量会略高于池物理容量，必须以后监控 `nvme-data` Data% 实际使用率；但当前实际使用率约 34%，短期风险可控。
- 建议执行步骤（需用户确认后再做）：
  1. 在 PVE 备份 VM 配置：`qm config 130 > /root/130.conf.bak.20260705-before-disk-resize`。
  2. 在线扩容 PVE 侧磁盘：`qm resize 130 scsi0 +180G`。
  3. 在 guest 内确认内核识别到 `/dev/sda` 新大小；如未识别，再执行 SCSI rescan 或安排短维护窗口重启 VM。
  4. 在 guest 内扩分区与 XFS：`sudo growpart /dev/sda 1 && sudo xfs_growfs /`。
  5. 验证 `df -hT /`、`lsblk`、runner service / CI 状态、`pvesm status`。
- 回滚说明：磁盘扩容与 XFS 扩容基本不可无损缩回；如执行后发现问题，应按备份配置和当时状态定位修复，而不是尝试直接缩盘。执行前应确认接受“只能向前扩”的性质。

## 2026-06-19 16:20 CST - mas-win 响应慢排查：解除内存超卖，固定 6G

- 服务器：`pve`（VM `120/mas-win`、`110/mssql-ref`、`140/fnos-nas`）
- 操作人：`Claude`
- 原因：用户反馈 `mas-win`（VMID 120）上的 IIS 站点响应非常慢。排查发现根因是宿主内存超卖：宿主 31GiB 物理内存，四台 VM 静态需求合计约 32GiB；`mas-win` 是当时唯一开启 ballooning 的 VM（`balloon=2048` < `memory=4096`），宿主内存吃紧时 auto-balloon 把它压到最小 2GiB，导致 Windows 物理内存不足、疯狂走 pagefile（`info balloon` 显示 `mem_swapped_in` 累计约 13.3GiB），站点响应极慢。
- 影响：
  - `mas-win` 内存从被压的 2GiB 恢复到固定 6GiB，ballooning 彻底关闭，不再被宿主回收；Windows 停止换页。
  - `mssql-ref`(110) 内存上限从 20480 永久下调到 18432（实测 SQL Server `max server memory` 已设 14336MB，VM 内仍余约 4GiB，未挤压 SQL）。
  - `fnos-nas`(140) 优雅关机（用户决定），腾出 2GiB 给 `mas-win`；`onboot=0`，宿主重启不会自动拉起。
  - `mas-win` 重启过程站点中断约 1~2 分钟；`mas-go-dev`(130) 全程未受影响。
  - 重启后宿主空闲内存偏紧（约 292MiB，swap 用约 316MiB）；用户计划后续给 PVE 加物理内存，再重新开 `fnos-nas`。
- 回滚：
  - 恢复内存超卖前状态：`ssh pve "qm set 120 --balloon 2048 --memory 4096 && qm set 110 --memory 20480"`。
  - 或从配置备份恢复：`/root/120.conf.bak.20260619`、`/root/110.conf.bak.20260619`。
  - 重新开机 NAS：`ssh pve "qm start 140"`。
- 变更：
  - 在线放气：`qm monitor 110` 执行 `balloon 18432`（腾 2GiB 给宿主）；`qm monitor 120` 执行 `balloon 4096`（mas-win 当场恢复，`free_mem` 670MiB→2714MiB，换页停止）。
  - 备份 VM 配置到 `/root/120.conf.bak.20260619`、`/root/110.conf.bak.20260619`。
  - `qm set 120 --balloon 0`（关闭 ballooning）。
  - `qm set 110 --memory 18432`（mssql-ref 内存永久降到 18GiB）。
  - `qm shutdown 140 --timeout 60`（关闭 fnos-nas）。
  - `qm set 120 --memory 6144`（mas-win 内存改 6GiB）。
  - `qm reboot 120 --timeout 120`（重启固化配置）。
- 验证：
  - 重启后 QEMU 进程 `VmRSS` 约 6.0GiB，`mas-win` 实拿满 6GiB。
  - `qm monitor 120` 执行 `info balloon` 返回 `No balloon device has been activated`，确认 ballooning 已彻底关闭、6GiB 永久固定。
  - `mssql-ref` 在线降内存后 VM 内 `free -h` 仍有富余、swap 未动；SQL Server `max server memory=14336MB`，不受影响。
  - `qm list`：120 running（6144）、110 running、130 running、140 stopped。
- 后续（用户负责）：
  - 给 PVE 增加物理内存，缓解宿主内存紧张（当前布局 18+6+8≈32GiB 仍略超 31GiB 物理量，靠页缓存弹性支撑）。
  - 加完内存后 `ssh pve "qm start 140"` 重新开 `fnos-nas`。

## 2026-06-19 10:48 CST - mas-win MAS-API 连接串库名切到 medicalassistance_preprod（配合 mssql-ref 库改名）

- 服务器：`pve`（VM `120/mas-win`，`192.168.2.21`）
- 操作人：`Claude`
- 原因：`mssql-ref` 上库 `medicalassistance` 改名为 `medicalassistance_preprod`（详见 `docs/operations/mssql-ref.md` 2026-06-19）。MAS 老 C# 系统的 `C:\MAS\Apps\MAS-API\Web.config` 把库名硬编码在约 30 个连接串里，需同步改名，否则 MAS-WEB（9021）登录与 API 连库失败（同 2026-06-15 那次故障的连库层）。
- 影响：
  - 修改活动 `Web.config`：21 处 `initial catalog=medicalassistance` + 1 处 appSettings `CATALOG_A` 值，统一改为 `medicalassistance_preprod`（共 22 处）。
  - **未误伤**：`maswebkit` / `insularsalesportal` / `masprepaid` / `authprovidermasweb` 等其它 catalog 不动；`pvLinkedServerMAS=medicalassistance_replicated` 这种带后缀的值不动（用负向断言精确匹配）。`Config - Copy` 副本目录未处理（非活动配置）。
  - 回收 `MAS-API` 应用池使新配置生效。未动 MAS-WEB（它不直连库）。
- 回滚：用备份 `C:\MAS\Apps\MAS-API\Web.config.bak.20260619` 覆盖后回收 MAS-API 应用池。
- 变更：
  1. `copy /Y` 备份 Web.config 到 `.bak.20260619`。
  2. 全程走 PVE guest agent（`qm guest exec 120 -- powershell.exe -EncodedCommand`，UTF-16LE base64），本地 `.ps1` 整文件正则替换、UTF-8 无 BOM 写回（同 2026-06-15 的转义解法）。正则用断言 `(?=[;&'"\s])` / `(?![a-z_])` 保护带后缀的值。
  3. `appcmd recycle apppool /apppool.name:MAS-API`。
- 验证：
  - 替换后核对：`initial catalog` 仅 `medicalassistance_preprod`（+其它库名）、`CATALOG_A=medicalassistance_preprod`；`medicalassistance_replicated` 完好（1）、无遗留裸 `medicalassistance`（0）、`_preprod` 共 22 处。
  - ADO.NET 连库测试：`OK login=mas_ref_owner db=medicalassistance_preprod`。
  - `http://192.168.2.21:9021/` 返回 HTTP 200。
- 相关：直接延续 `docs/solutions/pve/runtime-errors/mas-web-login-fail-stale-mssql-user-in-mas-api-2026-06-15.md`（同一份 Web.config、同一套 EncodedCommand 改法），那次改的是账号名，这次改库名。

## 2026-06-19 00:18 CST - 新增 fnOS NAS VM

- 服务器：`pve`（VM `140/fnos-nas`）
- 操作人：`Codex` + 用户图形界面安装 fnOS
- 原因：在 PVE 内新增一台轻量 NAS VM 运行飞牛 fnOS，用于存放可重新下载的影视资源；计划容量不超过 300G，不承载重要数据。
- 影响：
  - 新增 VM `140/fnos-nas`，占用 2 vCPU / 2 GiB 内存。
  - 在 `local-lvm` 新增 3 个 thin volumes：4 MiB EFI 盘、32G 系统盘、300G 数据盘；`local-lvm` Data% 当前约 3.66%。
  - 上传 fnOS ISO 到 PVE `local` ISO 存储，`local` 使用率约 32.90%。
  - 现有 VM `110/mssql-ref`、`120/mas-win`、`130/mas-go-dev` 全程保持 running；未重启宿主机，未改网络、防火墙、Tailscale route、数据库或现有 VM 配置。
- 回滚：
  - 如需删除该 NAS VM，先确认不需要保留影视数据，然后关闭 VM `140`，执行 `qm destroy 140 --destroy-unreferenced-disks 1 --purge` 删除 VM 配置和 `local-lvm` 磁盘。
  - 如需清理安装镜像，可删除 `/var/lib/vz/template/iso/fnos_Mainland-PE_x86_1.1.3107_1809.iso`。
  - 本机 SSH 快捷别名可从 `~/.ssh/config` 删除 `Host fnos-nas` 段；fnOS 内公钥可从 `/home/konghai/.ssh/authorized_keys` 删除对应行。
- 变更：
  - 从本地仓库根目录上传 `fnos_Mainland-PE_x86_1.1.3107_1809.iso` 到 PVE `/var/lib/vz/template/iso/`；上传后 SHA256 校验一致：`8175479731186edbc65ac7d5f33718a8dc8cd2f47907c4527ca44aa3a8391c7e`。
  - 创建 VM `140/fnos-nas`：`q35`、OVMF、2 cores、2 GiB memory、VirtIO 网卡、`vmbr0`、`onboot=0`。
  - 在 `local-lvm` 创建 `scsi0` 32G 系统盘、`scsi1` 300G 数据盘，均开启 `discard=on`、`iothread=1`、`ssd=1`。
  - 用户通过 PVE Console 完成 fnOS 安装：系统分区 32G、Swap 2G；安装完成后卸载 ISO，启动顺序改为 `scsi0` 优先。
  - 用户在 fnOS 内设置固定 IP `192.168.2.9/24`，启用 SSH，并将 300G 数据盘初始化为 `ext4` Basic 存储空间，挂载为 `/vol1`。
  - 因 fnOS 用户 `konghai` 的 home 目录缺失，手动创建 `/home/konghai/.ssh`、设置权限并写入本机 `~/.ssh/id_ed25519.pub`；本机 `~/.ssh/config` 追加别名 `fnos-nas`（不属于仓库文件）。
- 验证：
  - PVE `qm list` 显示 `140/fnos-nas` 为 `running`，`onboot=0`，`boot: order=scsi0`，`ide2: none,media=cdrom`。
  - `pvesm status` 显示 `local`、`local-lvm`、`nvme-data` 均为 active；`nvme-data` 未新增 fnOS 磁盘。
  - fnOS 内 `hostname` 为 `kh-nas-in-pve`，`enp6s18` 为 `192.168.2.9/24`。
  - fnOS 内系统盘为 32G ext4，根分区已用约 9.2G；Swap 为 2.0G；数据盘经 md/LVM 后以 ext4 挂载到 `/vol1`，可用约 298G。
  - `ssh fnos-nas 'hostname; whoami; pwd'` 免密成功，返回 `kh-nas-in-pve`、`konghai`、`/home/konghai`。
- 后续：
  - 暂不启用 `onboot`，避免宿主机重启后新 NAS VM 与 MAS 相关 VM 抢资源；稳定使用后如需要自动恢复，再单独确认。
  - 该 VM 数据为可重新下载影视资源，暂不设计备份或快照保留策略；不要长期保留该 VM 快照。

## 2026-06-14 22:50 CST - 清理三台 VM 的 9 个搭建期快照

- 服务器：`pve`（VM `110/mssql-ref`、`120/mas-csharp`、`130/mas-go-dev`）
- 操作人：`Claude`
- 原因：排查 NVMe（`nvme-data` thin pool）占用时发现三台 VM 共留有 9 个快照，均为 2026-05-16~17 一次性搭建/迁移的里程碑检查点（装系统→装中间件→恢复库→迁移），距今约一个月。确认 PVE 无任何自动清理快照的机制（`jobs.cfg`/`vzdump.cron` 空、无 cron/timer/脚本），这些快照只会随原卷写入持续增长，故清理。
- 影响：
  - 删除全部 9 个快照（删的仅是回滚能力，三台 VM 当前 `current` 运行状态与数据不受影响）：
    - VM110：`mssql-ready` / `mssql-full-ready` / `mssql-all-full-ready` / `before-mas-go-migrate-20260517`
    - VM120：`windows-core-ready` / `iis-aspnet-ready` / `mas-csharp-smoke-ready` / `mas-csharp-preprod-ready`
    - VM130：`mas-go-dev-deploy-ready-20260517`
  - `nvme-data` thin pool 物理占用 42.79% → 40.98%（回收约 17G）。回收量不大，因快照创建后原卷写入有限、CoW 差异块本就不多；清理的主要价值是消除其持续增长隐患（尤其 VM110 数据库一直在写）。
  - 三台 VM 全程 `running`，未重启、未动数据。
- 回滚：快照删除不可逆，无法回滚（如需还原点须重新 `qm snapshot` 创建）。但当前运行状态完好，无回滚需求。
- 变更：
  1. 只读核查：`qm listsnapshot 110/120/130` 列出快照树与创建时间、描述；确认无自动清理机制。
  2. 确认三台 `qm status` 均 `running`（停在 `current`，非某快照）。
  3. 逐个 `qm delsnapshot <vmid> <snapname>`，每条链从最旧开始删。
- 验证：
  - 三台 `qm listsnapshot` 均只剩 `current`；`lvs nvme-data` 无残留 `snap_` LV。
  - thin pool Data% 40.98%；三台 VM 仍 `running`。
- 备注：PVE 的 vzdump 保留策略只管「备份文件」，不管「VM 快照」；快照清理在 PVE 里始终是手动的。后续若再打搭建/迁移检查点，用完应手动删，避免再次堆积。

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
