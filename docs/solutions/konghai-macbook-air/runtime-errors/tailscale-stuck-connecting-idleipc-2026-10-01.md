---
title: macOS Tailscale 卡在 Connecting，CLI 报 CLIError 1
date: 2026-10-01
category: docs/solutions/konghai-macbook-air/runtime-errors
server: konghai-macbook-air
module: macOS / Tailscale.app macsys
problem_type: runtime_error
component: tooling
severity: high
symptoms:
  - 菜单栏 Tailscale 一直 Connecting，接口上没有 100.x 地址
  - tailscale status / version 都报 Tailscale.CLIError error 1
  - scutil --nc status Tailscale 长期停在 Connecting，LastStatusChangeTime 不再更新
  - nesessionmanager 日志反复 cannot establish IPC because IPC is already in the process of being established
  - 控制面 HTTPS 和局域网网关都通，问题不在出口网络
root_cause: stuck_vpn_session
resolution_type: environment_setup
tags:
  - tailscale
  - macos
  - network-extension
  - nesessionmanager
  - clierror
  - idleipc
---

# macOS Tailscale 卡在 Connecting，CLI 报 CLIError 1

Tailscale.app（Standalone / macsys，不是 Homebrew `tailscaled`）的系统 VPN 会话可以卡死在 `NESMVPNSessionStateIdleIPC`。菜单栏进程还在，网络扩展进程也可能还在，但两边的 IPC 建不完，CLI 就起不来。

## Problem

2026-10-01 本机 MacBook Air，Tailscale 1.102.4。VPN 配置 UUID `707FEAAA-B346-469A-9043-6FE3F06865D5` 从 2026-09-30 15:23 起显示 Connecting。`/usr/local/bin/tailscale` 只是转到 App 里的 CLI，报：

```text
The Tailscale CLI failed to start: The operation couldn’t be completed. (Tailscale.CLIError error 1.)
```

同一时刻：

- `https://controlplane.tailscale.com/key?v=126` 返回 200
- 默认路由走 `en0` → `192.168.2.1`，ping 网关约 3ms
- 系统扩展 `io.tailscale.ipn.macsys.network-extension` 已启用，进程自 15:23 起没退出
- `nesessionmanager` 对该会话的状态是 IdleIPC。App 和 `scutil --nc stop` 的 stop 都能送到，但状态机不离开 IdleIPC

所以这不是账号掉线，也不是 UDP 41641 被墙。

## What didn't work

1. 只退出再打开 Tailscale.app。会话对象在 `nesessionmanager` 里，不在 App 进程里。
2. `scutil --nc stop "Tailscale"`。日志是 `in state NESMVPNSessionStateIdleIPC: received stop message`，随后没有状态迁移。
3. 杀掉网络扩展进程。扩展没了，`scutil` 的 LastStatusChangeTime 仍是昨天，CLI 照旧 CLIError 1。
4. `launchctl kickstart -k system/com.apple.nesessionmanager`。SIP 开着时直接拒绝：`Could not kickstart service "com.apple.nesessionmanager": 150: Operation not permitted while System Integrity Protection is engaged`。

## Fix

需要管理员权限。Azure VPN、OneXray 等其它 Network Extension 会话会被一起清掉；当时它们都是 Disconnected。

```bash
osascript -e 'tell application "Tailscale" to quit'
# 下面这条要在管理员权限下执行。kickstart -k 会被 SIP 拦住，kill 可以。
kill -9 "$(pgrep -x nesessionmanager)"
# launchd 会拉起新的 nesessionmanager
open -a Tailscale
# CLI 能回答 Tailscale is stopped. 之后再连。
# 本机非默认项只有 accept-dns=false，必须写出来，否则 tailscale up 拒绝执行。
tailscale up --accept-dns=false
```

`tailscale up` 不带 `--accept-dns=false` 时会要求显式列出全部非默认 flags，或者 `--reset`。不要用 `--reset`，那会把 2026-09-21 关掉的全局 MagicDNS 开回去。

## Verification

- `scutil --nc status Tailscale` 为 Connected
- `tailscale ip -4` 为 `100.92.181.15`，接口上能看到该地址
- `tailscale debug prefs`：`WantRunning=true`，`CorpDNS=false`，`LoggedOut=false`
- `tailscale ping mac-mini` 先走 DERP(km)，随后打到局域网直连

系统 DNS 应仍是当前局域网路由器（家里 `192.168.2.1`），`/etc/resolver/ts.net` 与 `taila93443.ts.net` 继续指向 `100.100.100.100`，只解析 tailnet 域名。

## Notes

恢复前 prefs 里 `RouteAll` 已经是 false。2026-09-21 的时间线写的是子网路由保持开启。这次只把隧道拉起来，没有改 `RouteAll`。需要接受别人通告的子网路由时再单独 `tailscale set --accept-routes=true`。
