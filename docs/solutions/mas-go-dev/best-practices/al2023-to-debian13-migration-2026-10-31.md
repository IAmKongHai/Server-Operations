---
title: SIT 合部署 VM 从 Amazon Linux 2023 迁到 Debian 13（mas-go-dev → mas-sit）
date: 2026-10-31
category: docs/solutions/mas-go-dev/best-practices
server: mas-go-dev
module: pve / mas-go-dev
problem_type: best_practice
component: infrastructure
severity: medium
applies_when:
  - 把跑着 Docker compose 服务和 self-hosted runner 的 VM 换操作系统，同时要求地址、数据、runner 对使用方透明
  - PVE 宿主内存不够新旧 VM 并行，只能先关旧机
  - 新机是 Debian 13 genericcloud 镜像，需要沿用旧机的 UID/GID、Tailscale 节点身份和 SSH 主机密钥
  - compose 项目的镜像 tag、端口绑定由 CI 部署时注入，不能在新机上直接 compose up
tags: [pve, debian-13, al2023, migration, docker, tailscale, nsswitch, github-actions-runner]
---

# SIT 合部署 VM 从 Amazon Linux 2023 迁到 Debian 13（mas-go-dev → mas-sit）

## Context

`mas-go-dev`（PVE VM 130，AL2023）承载 iCare / EVP SIT、共享 PostgreSQL / Garage / Redis 和 6 个 self-hosted runner。shared-sit 租户的连接串、EVP 的 `PUBLIC_ORIGIN`、nyh-prod 反代都写死了它的 Tailscale IP，所以换系统必须做到地址、数据和 runner 都不变。2026-10-31 迁到 Debian 13 的 VM 160，并按用户要求改名 `mas-sit`。计划：`docs/plans/2026-10-31-1418-ops-mas-go-dev-debian13-migration-plan.md`；完整时序：`docs/operations/mas-go-dev.md` 同日条目。

下面这些坑在计划阶段都没预料到，换任何一台类似 VM 都会再遇到。

## Guidance

### 1. 宿主内存不够并行时：先关旧机，用 thin 快照作数据源

原计划新旧机并行搭建，但宿主 MemAvailable 只有约 5.6 GiB（mssql-ref 刚重启，内存还会继续涨）。改为：先在旧机上停 runner、停 compose、采基准、`docker save`、停 `tailscaled`，然后关机；再对旧盘做 LVM thin 快照，只读挂到新 VM：

```bash
# PVE 宿主：-kn 去掉 activation skip，名字用新 VM 的盘号，PVE 才能直接挂
lvcreate -s -kn -n vm-160-disk-1 nvme-data/vm-130-disk-1
qm set 160 --scsi1 nvme-data:vm-160-disk-1,ro=1,iothread=1
# 新 VM 内（旧盘是 XFS）
mount -o ro,norecovery,nouuid /dev/sdX1 /mnt/old
```

原盘全程没动，回滚就是关新机、开旧机。迁完后 `qm set 160 --delete scsi1` + `qm disk unlink --force` 删掉快照。旧机停服前在旧盘上留好 `docker save` 的 tar，新机从快照里直接 `docker load`。

**磁盘名会变**：第二次重启后快照盘变成了 `sda`、根盘变成 `sdb`。挂载和摘盘都按 scsi 编号 / PARTUUID 认盘，不要用 `/dev/sdX`。

### 2. 先挪开 Debian 占用的 GID，再按旧号建用户组

Debian 13 cloud 镜像的系统组从 999 往下分配：`clock` 993、`kvm` 992、`render` 991、`systemd-resolve` 990，正好撞上旧机的 `docker` 993、`actions-runner` 992、`tk-flywheel-ci` 991、`acquilang-ci` 990。必须在装 Docker CE 之前处理，因为它会自己建 `docker` 组：

```bash
groupmod -g 987 clock   # 再 find / -xdev -gid 993 -exec chgrp -h 987 {} +
# kvm→986、render→985、systemd-resolve→984 同理；groupmod 会同步改 passwd 里的主组
# 复用这些号之前先核对没有账号的主组仍是旧号：getent passwd | awk -F: '$4>=990 && $4<=993'
groupadd -g 993 docker; groupadd -g 992 actions-runner   # …
useradd -u 993 -g 992 -m actions-runner                   # …
```

之后所有拷贝都用 `rsync -aHAS --numeric-ids`。容器内用户的文件（如 FCM 凭据 `10001:999`）按数字原样保留。不要带 `-X`，AL2023 的 SELinux 标签用不上。

### 3. Debian 的 nsswitch 让 MagicDNS 短名失效

旧机和新机的 resolved 配置完全相同（`DNS=100.100.100.100`、`Domains=~taila93443.ts.net`，`/etc/resolv.conf` 都链到 `/run/systemd/resolve/resolv.conf`），但新机上 `getent hosts mac-mini` 解析不出来，CI 里的 `http://mac-mini:9000`（SonarQube）会挂。原因在 nsswitch：

- AL2023：`hosts: files dns myhostname`。glibc 读 resolv.conf 的 `search taila93443.ts.net` 补全短名。
- Debian 13 cloud：`hosts: files myhostname resolve [!UNAVAIL=return] dns`。查询走 nss-resolve，而 resolved 不会拿 `~` 开头的路由域去补全单标签名，`[!UNAVAIL=return]` 又不让查询落到 `dns`。

修复：`apt-get remove libnss-resolve`。它的 postrm 会把 nsswitch 改成 `files myhostname dns`，以后升级也不会再加回来。之后宿主和 `--network host` 容器里都能解析 `mac-mini`。

### 4. Docker 29：先写 daemon.json，再装、再 load

Docker 29 新装默认启用 containerd image store。镜像的存放方式和旧机的 overlay2 经典存储不同，`docker save` / `load` 后的 ID 对比也会受影响。所以 `/etc/docker/daemon.json` 要在装包**之前**写好：

```json
{ "log-driver": "local", "features": { "containerd-snapshotter": false },
  "default-ulimits": { "nofile": { "Name": "nofile", "Soft": 32768, "Hard": 65536 } } }
```

`nofile` 对应 AL2023 `/etc/sysconfig/docker` 里的 `OPTIONS`，那个文件在 Debian 上不存在，容易漏。load 后 20 个镜像 ID 与旧机全部一致。compose 文件里用 digest 钉死的镜像（postgres、garage）在旧机上 `RepoTags` 为空，save 时按 ID 导出，新机按 digest 重新拉取，ID 相同。

### 5. Tailscale：装包会自动起一次，放旧 state 前先清空

Debian 的 tailscale 包在 postinst 里会启动一次 `tailscaled`，生成空 state（`{}`）和新的 `tailscaled.log.conf`。装完立刻 `systemctl disable --now tailscaled`，等旧机停掉 `tailscaled` 后，先 `find /var/lib/tailscale -mindepth 1 -delete`，再拷入旧 state，然后首次启动。节点身份和 IP 都会沿用。改名用 `tailscale set --hostname=<新名>`（旧 prefs 里有显式 `Hostname`），MagicDNS 名会随之变化。

SSH 主机密钥也要沿用：AL2023 的私钥是 `root:ssh_keys 640`，放到 Debian 要改回 `root:root 600`。Debian 13 的 OpenSSH 不再支持 DSA，不用带过去。另外写 `/etc/cloud/cloud.cfg.d/99-*.cfg`（`ssh_deletekeys: false`、`ssh_genkeytypes: []`、`preserve_hostname: true`、`manage_etc_hosts: false`），防止以后 cloud-init 实例 ID 变化时重建密钥。

### 6. 不能直接 `docker compose up`：按旧容器配置重建，再逐个比对

iCare 的 compose 文件把镜像 tag（`BACKEND_IMAGE`、`MAS_IMAGE`…）、端口绑定（`MAS_PORT_BIND`、`VTM_BIND_ADDR`…）和 env 文件路径都留给部署 workflow 注入。ecom / sup 的 Tailscale 端口来自 `deploy_external_api.sh` 生成后就删掉的 `/tmp` override。直接 `up` 会用 `:local` 镜像、只绑 `127.0.0.1`。

做法是从旧盘快照的 `/var/lib/docker/containers/*/config.v2.json` + `hostconfig.json` 取出每个容器的镜像、端口和挂载，写一个启动脚本把变量补齐。起来之后，用同一个解析脚本对新机 `docker inspect` 再输出一遍规格（镜像、Env 值的 sha256、端口、挂载、网络、restart、资源限制），和旧机逐个 diff，这次 24 个容器全部一致。

另外两个坑：

- `api` 对一次性 `seed` 服务有 `depends_on`，`up api worker` 会顺带跑 migrate + seed，打到 `mssql-ref`。这次是幂等的（`no change`），但应该加 `--no-deps`，和 CI 的做法一样。
- 旧机上还有 compose 文件里已经删掉的孤儿容器（`icare-backend-gotenberg-1`）。只照 compose 文件重建会漏掉它；要以 `docker ps` 为准盘点。

### 7. 补上 Docker 等 Tailscale IP 的开机顺序

很多 SIT 端口只绑 `100.109.223.53`。旧机上没有任何机制保证 Docker 晚于 `tailscaled` 拿到 IP，只是碰巧晚了约 10 秒。新机加了一个 drop-in：

```ini
# /etc/systemd/system/docker.service.d/10-after-tailscale.conf
[Unit]
Wants=tailscaled.service
After=tailscaled.service
[Service]
ExecStartPre=-/usr/local/sbin/wait-tailscale-ip.sh   # 等 tailscale0 出现该 IP，最多 90 秒，超时也放行
TimeoutStartSec=180
```

两次 `qm reboot` 后，Docker 都是在 tailscaled Running 之后才启动，24 个容器无人干预全部起来。

### 8. 盘点宿主工具，而不只是 workflow 里的 `dnf`

workflow 里 grep `dnf` / `yum` 只抓到了带 `apt-get` 兜底的安装步骤。真正的隐性依赖是宿主上的 AWS CLI v2：AL2023 预装了 `awscli-2`，`mas-go-dev-ci-1` 上的 prod 部署 job 直接调用 `aws ecr` / `aws eks`。另外 AcquiLang runner 的 `.env` 里写着 `LANG=en_US.UTF-8`，Debian cloud 镜像默认没生成这个 locale。新机要装 AWS CLI v2 官方包、`locales`，以及 `build-essential`、`zip`、`dirmngr` 等。

## Why This Matters

每一项对应一种「迁过去看起来正常、过后才出问题」的故障：GID 冲突会让 runner 用不了 Docker；短名解析失败会让 Sonar 步骤挂掉；compose 直接 up 会让 SIT 端口在 tailnet 上消失；开机顺序靠运气，某次重启后容器 bind 失败。先盘点、按旧配置重建、再逐项比对，切换才能一次通过。

## When to Apply

- 迁移任何同时跑 compose 服务和 self-hosted runner 的 Linux VM，尤其是换发行版
- 目标是 Debian 13 genericcloud，并且要用 Tailscale MagicDNS 短名
- 旧机上的容器由 CI 部署、配置不完全在 compose 文件里

## Examples

数据核对用 `scripts/mas-go-dev-data-baseline.sh`：在旧机停应用层、数据层还在跑时采一次，新机只起数据层时再采一次，两次结果 `diff` 必须为空（每张表的精确行数、Garage 对象数、Redis 各 DB 的 key 数、azurite 容器 / blob 数）。

## Related

- `docs/operations/mas-go-dev.md`、`docs/operations/pve.md`（2026-10-31 条目）
- `docs/solutions/pve/best-practices/mas-go-dev-deployment-2026-05-17.md`（这台 VM 最初的建机过程）
- `docs/solutions/mas-go-dev/integration-issues/sonar-scan-fails-no-dirmngr-on-x86-runner-2026-06-10.md`
- Tailscale state 迁移先例：`docs/operations/tizi-kh.md`
