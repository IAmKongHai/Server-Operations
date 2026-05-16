---
title: 将 PVE 配置为 Tailscale Subnet Router
date: 2026-05-16
category: docs/solutions/pve/best-practices
server: pve
module: pve / tailscale
problem_type: workflow_issue
component: networking
severity: low
tags: [pve, tailscale, subnet-router, vpn, mas, reference-environment]
---

# 将 PVE 配置为 Tailscale Subnet Router

## Context

需要让团队成员通过 Tailscale 访问 PVE 上的 MAS 参考环境，但不希望在每台 VM 内分别安装 Tailscale。当前只需要开放两台参考 VM：

| VM | IP | 用途 |
| --- | --- | --- |
| `mssql-ref` | `192.168.2.20` | SQL Server 参考数据库 |
| `mas-win` | `192.168.2.21` | Windows Server Core / IIS / MAS 老 C# 应用 |

## Decision

在 PVE 宿主机安装并登录 Tailscale，把 PVE 配置为 subnet router，只 advertise 两个 `/32` 地址：

```bash
tailscale up --advertise-routes=192.168.2.20/32,192.168.2.21/32
```

不 advertise 整个 `192.168.2.0/24`，避免把家庭内网其他设备暴露给团队。

## Implementation

Tailscale 状态：

| 项目 | 值 |
| --- | --- |
| Hostname | `pve` |
| Tailscale DNS | `pve.taila93443.ts.net` |
| Tailscale IPv4 | `100.95.67.55` |
| Advertised routes | `192.168.2.20/32`、`192.168.2.21/32` |

启用 Linux 转发：

```text
/etc/sysctl.d/99-tailscale-subnet-router.conf
```

内容：

```conf
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
```

Tailscale 提示 `vmbr0` 的 UDP GRO forwarding 未优化，已运行并持久化：

```bash
ethtool -K vmbr0 rx-udp-gro-forwarding on rx-gro-list off
```

持久化位置：

```text
/etc/network/interfaces
```

备份：

```text
/etc/network/interfaces.bak.tailscale-20260516-202446
```

## Remaining Admin Console Steps

需要在 Tailscale Admin Console 对 `pve` 这台机器执行：

- Approve subnet routes：`192.168.2.20/32`、`192.168.2.21/32`
- Disable key expiry，避免 subnet router key 到期后 route fail-close

在 approve 前，`tailscale status --self --json` 的 `Self.AllowedIPs` 只会显示 PVE 自己的 Tailscale IP，不会包含这两个 subnet route；这是正常状态。

## Verification

PVE 本机验证：

```text
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
AdvertiseRoutes = 192.168.2.20/32, 192.168.2.21/32
```

approve 后，从 Tailnet 客户端验证：

```bash
curl -I http://192.168.2.21:9021/
nc -zv 192.168.2.20 1433
```

预期：

- `http://192.168.2.21:9021/` 返回 MAS Web 登录页。
- `192.168.2.20:1433` 可连接 SQL Server。

## Notes

- 在家庭局域网内直接访问 `192.168.2.21` 通常走本地 LAN，不绕 Tailscale。
- 在外部网络访问同一个 `192.168.2.21` 会通过 Tailscale subnet route 进入 PVE，再转发到 VM。
- 默认保留 Tailscale subnet router SNAT 行为；VM 看到的来源可能是 PVE，而不是真实 Tailnet 客户端 IP。
