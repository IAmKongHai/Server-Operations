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

## 待办 / 留意

- Tailscale 设备名仍是 `konghai`，如要改需在 Tailscale 管理后台 rename，或 `tailscale up --hostname=xiao-linux` 重新注册
- `konghai` 用户被锁但未删；如需恢复：`usermod -U konghai && usermod -s /bin/bash konghai`
- `PasswordAuthentication` 未关；只是 root 不允许密码。如要彻底禁用密码登录，需要先确保所有有效用户都已部署密钥
- 用途确定后，回来更新本文件
