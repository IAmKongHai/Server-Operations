---
title: xiao-linux 新机入网初始化
date: 2026-05-14
category: docs/solutions/xiao-linux/workflow-issues
server: xiao-linux
module: xiao-linux / 系统初始化
problem_type: workflow_issue
component: tooling
severity: low
tags:
  - new-server
  - ssh
  - hostname
  - user-management
  - tailscale
---

## 背景

新加入 Tailscale 内网的一台 Ubuntu 22.04 小机器，初始信息：

- Tailscale IP：`100.123.159.77`
- 出厂用户：`konghai` / `konghai`（密码登录）
- 默认 hostname：`konghai`

目标：把它纳入仓库的服务器命名 / 登录约定，统一走密钥登录 root。

## 操作步骤

下面所有操作都通过 `konghai@100.123.159.77`（sudo 密码同账号密码）执行，最后切到 root 密钥登录验证。

### 1. 改 hostname

```bash
hostnamectl set-hostname xiao-linux
sed -i 's/konghai/xiao-linux/g' /etc/hosts   # 把 127.0.1.1 一行的旧主机名替换掉
```

### 2. 部署本机公钥到 root

```bash
mkdir -p /root/.ssh && chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
echo 'ssh-ed25519 AAAA...konghai@konghai.me' >> /root/.ssh/authorized_keys
```

### 3. sshd 配置 root 仅密钥登录

清掉旧的 `PermitRootLogin` / `PubkeyAuthentication` 行后追加：

```sshd_config
PermitRootLogin prohibit-password
PubkeyAuthentication yes
```

校验 + 重启：

```bash
sshd -t && systemctl restart ssh
```

> 备份：`cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.20260514`

### 4. **关键验证**：root 密钥登录可用

```bash
ssh -i ~/.ssh/id_ed25519 root@100.123.159.77 'hostname; whoami'
# 期望输出： xiao-linux / root
```

**只有这一步成功，才能继续下一步**。否则锁定 konghai 后会被锁在门外。

### 5. 锁定 konghai 用户（家目录保留）

```bash
usermod -L konghai
usermod -s /usr/sbin/nologin konghai
passwd -S konghai          # 状态应为 L
```

### 6. 本机 `~/.ssh/config` 加别名

```sshconfig
Host xiao-linux
    HostName 100.123.159.77
    User root
    IdentityFile ~/.ssh/id_ed25519
```

## 为什么这样做

- **`prohibit-password` 而非 `yes`**：root 只能用密钥登录，避免暴力破解；但保留普通用户的密码登录开关不动，避免一刀切影响后续 setup
- **锁定 konghai 而非 `userdel -r`**：家目录里可能有出厂残留文件（云镜像 cloud-init 日志等），先留着不动；要恢复也只是 `usermod -U` 一条命令
- **改 hostname 时同步改 `/etc/hosts`**：否则 `sudo` 会因为无法解析主机名报 warning（`sudo: unable to resolve host ...`）
- **在切换登录方式的中间步骤做验证**：新机初始化最容易翻车的就是 sshd 配置错把自己锁外面，所以第 4 步必须用新通道实测通过再继续

## 回滚

如果 root 密钥登录失败，konghai 还能用密码 + sudo 登进去：

```bash
sudo cp /etc/ssh/sshd_config.bak.20260514 /etc/ssh/sshd_config
sudo systemctl restart ssh
```

如果 konghai 也锁了又登不进来（理论上不会发生），就只能上物理控制台 / 云控制台救援。

## 相关

- [仓库根 README 服务器表](../../../README.md#已纳入的服务器)
- [xiao-linux 子目录 README](../../../xiao-linux/README.md)
