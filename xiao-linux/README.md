# xiao-linux

Tailscale 内网的一台 Ubuntu 小机器，2026-05-14 纳入仓库。用途暂未定，按测试 / 实验机看待，但破坏性操作仍需先备份。

## 连接

```bash
ssh xiao-linux
```

本机 `~/.ssh/config` 已配置别名，走 `id_ed25519` 密钥登录 root。

| 项               | 值                                                    |
| ---------------- | ----------------------------------------------------- |
| SSH 别名         | `xiao-linux`                                          |
| Tailscale IP     | `100.123.159.77`                                      |
| LAN IP           | `192.168.1.140/24`（DHCP，`eth0`）                    |
| Tailscale 主机名 | `konghai`（在 tailnet 里显示的名字，未改）            |
| 登录用户         | `root`（仅密钥，密码登录由系统默认 `PasswordAuthentication yes` 控制，但 root 走 `prohibit-password`） |
| 时区             | `Asia/Shanghai`                                       |

## 硬件 / 系统

- OS：Ubuntu 22.04.5 LTS（Jammy）
- Kernel：`6.8.0-111-generic`（HWE）
- 架构：x86_64
- 内存：8 GB（交换 2 GB）
- 磁盘：`/dev/sda3` 439 G，根分区占用 ~3%
- 服务：`sshd`、`tailscaled`、`cups`（本地 631）、`systemd-resolved`

## 已做的初始化（2026-05-14）

详见 `docs/solutions/xiao-linux/workflow-issues/initial-setup-2026-05-14.md`。

要点：

1. `hostname` 改为 `xiao-linux`，同步更新 `/etc/hosts`
2. 部署本机 `~/.ssh/id_ed25519.pub` 到 `/root/.ssh/authorized_keys`
3. `sshd_config` 设为 `PermitRootLogin prohibit-password`（root 仅密钥登录）
4. 原 `konghai` 用户：`usermod -L` 锁定 + shell 改 `/usr/sbin/nologin`，家目录保留
5. 本机 `~/.ssh/config` 加入 `Host xiao-linux` 别名

服务器上的备份：

- `/etc/ssh/sshd_config.bak.20260514`
- `/tmp/hostname.bak`（重启后丢失，仅供当时回滚用）

## 已部署的服务

### SQL Server 2017 + FTS（`shared-sqlserver`）

2026-05-14 部署，作为开发测试用数据库，**版本与 dev-cypresso 完全一致**：

- **Build**：`14.0.3520.4`（RTM-CU31-GDR, KB5077471, 2026-02-13）
- **Edition**：Developer Edition (64-bit)
- **特性**：FTS 全文检索已装
- **镜像**：`shared-sqlserver-fts:2017-cyp327`（本地 build，基于 `mcr.microsoft.com/mssql/server:2017-latest`）
- **端口**：`127.0.0.1:1433`（仅本机，外部需 SSH 隧道）
- **数据卷**：`sqlserver_sqlserver_data` → `/var/opt/mssql`
- **配置目录**：`/opt/stacks/sqlserver/`（Dockerfile + `docker-compose.yml` + `.env`，`.env` 权限 600）
- **凭据**：复用 dev-cypresso 的 SA 密码，见本机 `dev-cypresso/secrets.local.md`

部署过程详见 [`docs/solutions/xiao-linux/workflow-issues/install-mssql-2017-fts-2026-05-14.md`](../docs/solutions/xiao-linux/workflow-issues/install-mssql-2017-fts-2026-05-14.md)。

常用：

```bash
# 启停
ssh xiao-linux 'cd /opt/stacks/sqlserver && docker compose ps'
ssh xiao-linux 'cd /opt/stacks/sqlserver && docker compose restart'

# 查询版本
ssh xiao-linux 'docker exec shared-sqlserver /opt/mssql-tools/bin/sqlcmd \
  -S localhost -U sa -P "<密码见 dev-cypresso/secrets.local.md>" \
  -Q "SELECT @@VERSION"'

# 从本机连：通过 SSH 隧道
ssh -L 1433:127.0.0.1:1433 xiao-linux
# 然后本机 localhost:1433 即可连
```

## 已装的基础组件

- **Docker CE 29.4.3** + Compose v5.1.3（清华镜像源安装，2026-05-14）
- Tailscale（出厂自带）
- snap 版 curl（带它特有的 sandbox 限制；要 `/usr/bin/curl` 的话用 `apt install curl --reinstall` 切回）

## 网络

- **`mcr.microsoft.com`、`packages.microsoft.com` 可直连**（拉 SQL Server 镜像无问题）
- **Docker Hub（`registry-1.docker.io`）不通**——拉 redis、postgres、rabbitmq 等流行镜像会失败
- 万一以后要拉 Docker Hub 上的镜像，候选方案（按推荐顺序）：
  1. 镜像走清华/阿里 docker registry mirror（`/etc/docker/daemon.json` 加 `registry-mirrors`）
  2. mac-mini 起 HTTP 代理 + Docker daemon HTTP_PROXY
  3. mac-mini 当 Tailscale exit-node

## 待办 / 留意

- Tailscale 设备名仍是 `konghai`，如要改需在 Tailscale 管理后台 rename，或 `tailscale up --hostname=xiao-linux` 重新注册
- `konghai` 用户被锁但未删；如需恢复：`usermod -U konghai && usermod -s /bin/bash konghai`
- `PasswordAuthentication` 未关；只是 root 不允许密码。如要彻底禁用密码登录，需要先确保所有有效用户都已部署密钥
