# pve

开发测试虚拟化宿主。当前为裸机 Proxmox VE，用于承载后续开发、测试、集成类 VM。

虽然定位是测试服务器，但仍按生产习惯操作：修改配置前备份，重启、删除、改防火墙、改数据库前先确认。

## 连接

```bash
ssh pve
```

- SSH 别名：`pve`
- 地址：`192.168.2.10:22`
- PVE Web：`https://192.168.2.10:8006`
- 默认管理用户：`root`
- 主机名：`pve`
- root 登录：已部署本机 `~/.ssh/id_ed25519.pub`

## 基线信息

盘点时间：2026-05-16

| 项目 | 值 |
| --- | --- |
| OS | Debian GNU/Linux 13 (trixie) |
| Proxmox VE | `9.1.11` |
| Kernel | `7.0.2-3-pve` |
| CPU | Intel Core i5-9600，6 核 6 线程 |
| 内存 | 约 31 GiB |
| QEMU | `pve-qemu-kvm 11.0.0-2` |
| ZFS | `zfsutils-linux 2.4.2-pve1`，当前无 pool |

## VM 自启动

2026-05-16 已启用 PVE VM 开机自启动：

| VMID | VM | `onboot` | startup | 说明 |
| ---: | --- | --- | --- | --- |
| `110` | `mssql-ref` | `1` | `order=10,up=60,down=180` | 先启动数据库，给 SQL Server 预留启动时间 |
| `120` | `mas-win` | `1` | `order=20,up=90,down=180` | 后启动 IIS / C# 应用 |
| `130` | `mas-go-dev` | `1` | `order=30,up=60,down=180` | MAS Go + React 内网自动部署环境 |

`pve-guests.service` 已启用并处于 active。宿主机重启后，PVE 会按上面的顺序恢复 VM；手动启动时也建议先启动 `mssql-ref`，等 `192.168.2.20:1433` 可用后再启动或访问 `mas-win`。

## Tailscale

2026-05-16 已将 PVE 加入 Tailscale，并作为 subnet router 开放 MAS 参考环境。
2026-05-17 为 `mas-go-dev` 扩展 advertised route 到团队公共服务网段 `192.168.2.16/28`。

| 项目 | 值 |
| --- | --- |
| Tailscale DNS | `pve.taila93443.ts.net` |
| Tailscale IPv4 | `100.95.67.55` |
| Advertised routes | `192.168.2.16/28` |
| IP forwarding | `/etc/sysctl.d/99-tailscale-subnet-router.conf` |
| UDP GRO forwarding | `vmbr0` 已启用，并写入 `/etc/network/interfaces` 的 `post-up` |
| Network config backup | `/etc/network/interfaces.bak.tailscale-20260516-202446` |

Tailscale route 状态：

- `192.168.2.16/28` 已出现在 `AllowedIPs` 和 `PrimaryRoutes`。
- 仍建议关闭 `pve` 这台 Tailscale device 的 key expiry，避免半年后 subnet routes 仍显示但不可达。

外部 Tailnet 客户端 approve 后可访问：

```text
https://100.95.67.55:8006
http://192.168.2.21:9021
http://192.168.2.21:9020
http://192.168.2.22:5174
192.168.2.20:1433
```

## 网络

```text
vmbr0: 192.168.2.10/24
gateway: 192.168.2.1
bridge-ports: nic0
```

`/etc/hosts`：

```text
192.168.2.10 pve.lan pve
```

## 存储

当前 PVE 存储：

| 名称 | 类型 | 状态 | 容量 | 用途 |
| --- | --- | --- | ---: | --- |
| `local` | dir | active | 约 63G | ISO、备份、模板等 |
| `local-lvm` | lvmthin | active | 约 359G | VM/CT 磁盘 |
| `nvme-data` | lvmthin | active | 约 957G | VM/CT 磁盘 |

2026-05-16 状态：

- `nvme-data` 实际占用约 28.5%，剩余约 684G。
- `mssql-ref` 与 `mas-win` 都保留了阶段快照，thin volume 逻辑分配总量已超过 thin pool 物理容量；当前不影响运行，但不要长期保留无用快照或继续无限扩盘。

磁盘布局摘要：

| 设备 | 用途 |
| --- | --- |
| `sda` | PVE 系统盘，含 EFI、root、`local-lvm` |
| `nvme0n1` | 独立 LVM thin pool：`nvme-data` |

当前无 ZFS pool：

```text
zpool list
no pools available
```

## PVE 状态

2026-05-16 检查，系统升级并重启后：

- `proxmox-ve: 9.1.0`
- `pve-manager: 9.1.11`
- running kernel：`7.0.2-3-pve`
- `systemctl --failed`：无失败服务
- 单节点安装，未加入 cluster
- 当前 VM：
  - `110 / mssql-ref`：运行 MAS 老系统参考数据库
  - `120 / mas-win`：运行 MAS 老 C# / IIS 参考应用
  - `130 / mas-go-dev`：运行 MAS Go + React 内网自动部署环境

## 虚拟化检查

2026-05-16 检查：

- `kvm-ok`：已安装 `cpu-checker`，结果为 `KVM acceleration can be used`
- 等价检查：`/dev/kvm` 存在，CPU flags 包含 `vmx`
- IOMMU：已生效，当前有 11 个 IOMMU group
- 内核命令行：`intel_iommu=on iommu=pt` 已生效
- `dmesg` 显示 `DMAR: IOMMU enabled`
- `dmesg` 显示 `iommu: Default domain type: Passthrough (set via kernel command line)`

2026-05-16 变更：

- 备份：`/etc/default/grub.bak.20260516-110255`
- 修改：`GRUB_CMDLINE_LINUX_DEFAULT="quiet intel_iommu=on iommu=pt"`
- 已执行：`update-grub`
- 已重启并复查：`/proc/cmdline`、IOMMU group、`dmesg`

说明：当前 IOMMU 已由内核启用；显式参数用于后续 PCIe 直通和 FnOS VM 显卡硬解准备。

## 软件源

2026-05-16 已优化 APT 源：

- 备份目录：`/root/apt-sources-backup-20260516-105515`
- 禁用：`/etc/apt/sources.list.d/pve-enterprise.sources`
- 禁用：`/etc/apt/sources.list.d/ceph.sources`
- 新增：`/etc/apt/sources.list.d/proxmox-no-subscription.sources`

当前 PVE 源：

```text
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
```

`apt update` 已验证通过；`pve-manager` 候选版本来自 `trixie/pve-no-subscription`。

2026-05-16 已执行系统升级：

- `apt-get full-upgrade -y`
- 安装新内核：`7.0.2-3-pve`
- 升级 `pve-manager`：`9.1.1` -> `9.1.11`
- 升级 `pve-qemu-kvm`：`10.1.2-3` -> `11.0.0-2`
- 升级 ZFS：`2.3.4-pve1` -> `2.4.2-pve1`
- 重启后复查通过，无失败服务，无可升级包

## VM 清单

### `mas-go-dev`

MAS Go + React 重构版内网自动部署 VM。该 VM 只作为并行开发/测试部署目标，不替换 `dev-cypresso` 现有公网测试部署。

2026-05-17 创建完成：

| 项目 | 值 |
| --- | --- |
| VMID | `130` |
| IP | `192.168.2.22/24` |
| OS | Amazon Linux 2023.10.20260105 x86_64 |
| Kernel | `6.1.159-181.297.amzn2023.x86_64` |
| CPU / Memory | 4 vCPU / 16 GiB |
| Disk | `nvme-data:vm-130-disk-1`，120G thin-provisioned |
| Network | `vmbr0` |
| On boot | `onboot=1`，`startup=order=30,up=60,down=180` |
| Docker | `25.0.14` |
| Docker Compose | `v2.24.5` |
| GitHub runner | org runner `mas-go-dev`，runner group `mas-go-dev` |
| Runtime root | `/opt/mas-go-dev` |

目标用途：

- 运行 GitHub Actions self-hosted runner。
- 在 VM 内本地 checkout/build/deploy MAS Go 后端和 React 前端。
- 连接 `mssql-ref` 上的 SQL Server：`192.168.2.20:1433`。
- 通过 Tailscale subnet route 暴露给团队访问。

当前状态：

- 前端 test image 已能在 `0.0.0.0:5174` 启动并通过 `/healthz`。
- 用户确认后，已对 `mssql-ref` 执行 MAS Go 后端 `migrate + seed`；执行前已创建 VM `110` 快照 `before-mas-go-migrate-20260517` 和三库 SQL 备份。
- 后端 test image 已启动，Docker health 为 `healthy`。
- `http://192.168.2.22:5174/api/v1/health` 返回 HTTP 200。
- 后端 workflow 每次 `mas-go-dev` 部署都会先通过临时容器执行 `migrate up -> seed dry-run check -> seed apply`，执行完自动删除容器。
- VM `130` 已创建部署就绪快照：`mas-go-dev-deploy-ready-20260517`。
- PVE 配置中有一个排查 UEFI Secure Boot 时留下的 4 MiB `unused0: nvme-data:vm-130-disk-0`，待确认后可清理。

相关计划：`docs/plans/2026-05-17-001-feat-mas-go-dev-deployment-plan.md`。

### `mssql-ref`

MAS 老系统参考数据库 VM。只用于重构期间读取旧库，不作为生产数据库。

| 项目 | 值 |
| --- | --- |
| VMID | `110` |
| IP | `192.168.2.20/24` |
| OS | Ubuntu 22.04.5 LTS |
| Kernel | `5.15.0-179-generic` |
| CPU / Memory | 4 vCPU / 8 GiB |
| System disk | `nvme-data:vm-110-disk-0`，200G |
| Restore/data disk | `nvme-data:vm-110-disk-1`，400G，guest 内挂载 `/restore` |
| SSH user | `ubuntu`，已部署本机公钥 |
| Snapshots | `mssql-ready`、`mssql-full-ready`、`mssql-all-full-ready` |
| On boot | `onboot=1`，`startup=order=10,up=60,down=180` |

SQL Server：

| 项目 | 值 |
| --- | --- |
| Edition | SQL Server 2022 Developer Edition |
| Version | `16.0.4252.3` / RTM-CU24-GDR |
| Service | `mssql-server`，enabled / active |
| Listen | `0.0.0.0:1433` |
| Full-Text Search | 已安装并启用，`IsFullTextInstalled = 1` |
| Secrets | VM 内 `/root/mssql-secrets.env`，`600` 权限，不写入仓库 |

已挂载参考库：

| 数据库 | 状态 | 大小 | 表数量 | Full-Text |
| --- | --- | ---: | ---: | --- |
| `authprovidermasweb` | ONLINE | 约 11.0 GB allocated | 9 | 0 catalog / 0 index |
| `maswebkit` | ONLINE | 约 6.0 GB allocated | 66 | 0 catalog / 0 index |
| `medicalassistance` | ONLINE | 约 124.4 GB allocated | 419 | 1 catalog / 1 index |

`authprovidermasweb` 已从 compact 备份恢复：

- 本机来源：iCare repo `backend/db-bak/authprovidermas_preprod_compact-13052026.bak`
- 备份大小：`3750199296` bytes
- 备份源库名：`authprovidermas_preprod`
- 备份源版本：SQL Server 2017 (`DatabaseVersion = 869`)
- 当前库名：`authprovidermasweb`
- 当前数据文件：`/restore/data/authprovidermasweb_full/authprovidermasweb_full.mdf`，约 10,731 MB
- 当前日志文件：`/restore/data/authprovidermasweb_full/authprovidermasweb_full_log.ldf`，约 264 MB
- 行数抽样：约 6,925,933 行

`maswebkit` 已从 compact 备份恢复：

- 本机来源：iCare repo `backend/db-bak/maswebkit_preprod_compact-13052026.bak`
- 备份大小：`2778361856` bytes
- 备份源库名：`maswebkit_preprod`
- 备份源版本：SQL Server 2017 (`DatabaseVersion = 869`)
- 当前库名：`maswebkit`
- 当前数据文件：`/restore/data/maswebkit_full/maswebkit_full.mdf`，约 5,911 MB
- 当前日志文件：`/restore/data/maswebkit_full/maswebkit_full_log.ldf`，约 259 MB
- 行数抽样：约 10,474,914 行

`medicalassistance` 已从全量备份恢复：

- 本机来源：iCare repo `backend/db-bak/medicalassistance_prepro_05032026.bak`
- 备份大小：`104610357248` bytes
- 备份源库名：`medicalassistance_preprod`
- 备份源版本：SQL Server 2017 (`DatabaseVersion = 869`)
- 当前实例：SQL Server 2022，恢复后数据文件版本升级到 957
- 当前库名：`medicalassistance`
- 当前数据文件：`/restore/data/medicalassistance_full/medicalassistance_full.mdf`，约 99,765 MB
- 当前日志文件：`/restore/data/medicalassistance_full/medicalassistance_full_log.ldf`，约 27,670 MB
- 行数抽样：`sys.dm_db_partition_stats` 主索引/堆合计约 233,322,888 行
- 恢复盘剩余：`/restore` 约 128G 可用

说明：`/restore/data/*_full/` 目录名保留恢复过程的临时名，但 SQL Server 当前库名已经是正式库名；不要按目录名判断库名。

应用数据库登录：

- SQL login：`mas_ref_reader`
- 权限：三套参考库的 `db_owner`
- 说明：账号名沿用早期只读阶段的 `mas_ref_reader`，但 2026-05-16 已按测试需求提升为 `db_owner`，用于旧系统全面 CRUD 验证；不要再按只读账号理解。
- 密码位置：`/root/mssql-secrets.env` 中的 `MSSQL_MAS_REF_READER_PASSWORD`

数据来源：

- iCare repo：`backend/.local/mssql/data/*preprod*.mdf`
- iCare repo：`backend/.local/mssql/log/*preprod*.ldf`
- iCare repo：`backend/db-bak/authprovidermas_preprod_compact-13052026.bak`
- iCare repo：`backend/db-bak/maswebkit_preprod_compact-13052026.bak`
- iCare repo：`backend/db-bak/medicalassistance_prepro_05032026.bak`
- 小库 VM 内落点：`/var/opt/mssql/data/mas-ref/`
- 全量备份 VM 内落点：`/restore/backups/` 与 `/restore/data/*_full/`

### `mas-win`

MAS 老 C# 系统参考应用 VM。只用于重构期间打开旧页面、调用旧 API 和对照旧行为，不作为生产服务。

| 项目 | 值 |
| --- | --- |
| VMID | `120` |
| IP | `192.168.2.21/24` |
| OS | Windows Server 2022 Standard Evaluation / Server Core |
| CPU / Memory | 4 vCPU / 8 GiB |
| System disk | `nvme-data:vm-120-disk-0`，100G thin-provisioned |
| Network | `e1000` on `vmbr0` |
| QEMU guest agent | 已安装并运行 |
| Secrets | PVE 内 `/root/mas-win-secrets.env`，`600` 权限，不写入仓库 |
| Snapshots | `windows-core-ready`、`iis-aspnet-ready`、`mas-csharp-smoke-ready`、`mas-csharp-preprod-ready` |
| On boot | `onboot=1`，`startup=order=20,up=90,down=180` |

IIS / 应用：

| 站点 | 端口 | 路径 | 状态 |
| --- | ---: | --- | --- |
| `MAS-API` | `9020` | `C:\MAS\Apps\MAS-API` | Started |
| `MAS-WEB` | `9021` | `C:\MAS\Apps\MAS-WEB` | Started |

访问入口：

```text
http://192.168.2.21:9021/
```

部署说明：

- 应用发布包来源：iCare repo `docs/MAS-old-c#/old-C#-code/`
- VM 内部署副本：`C:\MAS\Apps\MAS-API`、`C:\MAS\Apps\MAS-WEB`
- 原始配置备份：`Web.config.orig`
- 数据库连接指向 `mssql-ref`：`192.168.2.20,1433`
- `MAS-WEB` 的 `serverlink` 指向 `http://192.168.2.21:9020/`
- 环境开关已按 NAS 旧部署对齐到 preprod / client-prod 形态：
  - `MAS-WEB`：`env=client-prod`
  - `MAS-API`：`prodEnv=true`、`uatEnv=false`
- 静态资源缓存配置与 NAS 旧部署一致：`clientCache cacheControlMode="UseMaxAge"`，`cacheControlMaxAge="7.00:00:00"`
- SMTP 和生产外部地址已在部署副本中本地化/禁用
- OAuth client 配置从 `authprovidermasweb.dbo.oauth_clients` 中的 `user` 记录同步到部署副本，文档不记录 secret

2026-05-16 smoke test：

- `MAS-WEB` 登录页：HTTP 200
- `MAS-API` 根路径：HTTP 403 directory listing denied，符合 API 根路径无默认文档的预期
- Windows VM 到 SQL Server：三库连接和表数量验证通过
- 使用测试账号登录：`ADMIN` 登录返回 HTTP 200，JSON `status=200` / `error=false`
- 登录后带 cookie 访问首页：HTTP 200，返回登录后页面内容
- 切换到 preprod / client-prod 环境开关后复测登录与首页仍通过

注意：

- `mas-win` 当前网卡使用 `e1000`，这是为了降低 Windows unattended 安装复杂度；已安装 VirtIO guest tools，后续可安排维护窗口切换为 VirtIO 网卡。
- 创建快照时 Windows 事件日志出现 VSS `8194` warnings，但快照创建成功，当前不影响 IIS / 登录 smoke。
- `mas-csharp-preprod-ready` 是当前推荐回滚点；后续如果继续改旧系统配置，先考虑是否要新建快照并清理旧快照。

## 网络备注

2026-05-16 传输 97G 全量备份时，PVE Realtek 网口曾在高流量下反复 link down/up。

- 网卡：Realtek `RTL8111/8168/8211/8411`
- 驱动：`r8169`
- 处理：更换 PVE 侧网线，并执行 `ethtool --set-eee nic0 eee off`
- 结果：4G 压测稳定，全量备份通过 `rsync --partial --inplace` 传输完成
- 注意：`ethtool --set-eee` 是运行时设置，重启后可能失效；如果再次出现大文件传输断开，优先检查 `journalctl -k` 中 `nic0: Link is Down`

## 后续配置建议

- 不要把 `mas-win` 对公网开放；当前只保留局域网访问。
- 如果要长期保留 `mas-win`，安排一次维护窗口把网卡从 `e1000` 切到 VirtIO，并清理不再需要的中间快照。
- 继续使用旧系统时，优先以只读浏览和 API 对照为目标；遇到必须写入的登录/session 类表，按对象记录授权原因。
