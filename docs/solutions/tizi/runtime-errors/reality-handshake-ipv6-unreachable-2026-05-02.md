---
title: REALITY 握手因无 IPv6 出口解析 IPv6 导致 network is unreachable
date: 2026-05-02
category: docs/solutions/tizi/runtime-errors
server: tizi
module: tizi / S-UI + sing-box（REALITY 入站）
problem_type: runtime_error
component: tooling
severity: high
symptoms:
  - 客户端连接代理节点持续超时，无法建立可用隧道
  - s-ui 服务在运行、443 端口在监听，客户端请求能打到服务器
  - 日志出现 REALITY: failed to dial dest ... connect: network is unreachable
  - 握手目标域名同时有 A/AAAA 记录时会尝试 IPv6，而服务器无 IPv6 出口
root_cause: config_error
resolution_type: configuration_change
tags:
  - tizi
  - s-ui
  - sing-box
  - reality
  - vless
  - ipv6
  - domain-strategy
  - ipv4-only
  - firewalld
  - panel-localhost
---

# REALITY 握手因无 IPv6 出口解析 IPv6 导致 network is unreachable

## Problem

服务器：`tizi` / `74.211.103.83`。服务为 S-UI 面板 + sing-box 内核，用作主代理节点。

2026-05-02 客户端无法连接代理节点，一直提示超时。排查时确认：

```text
s-ui 服务在运行
443 端口在监听
客户端请求能打到服务器
```

问题不是简单的服务未启动或端口未开放，而是 REALITY 入站在握手伪装站时失败，导致整条隧道建不起来。

## Root Cause

REALITY 入站原本使用的伪装 / 握手目标是：

```text
assets-xbxweb.xbox.com
```

排查过程中曾临时改成：

```text
iosapps.itunes.apple.com
```

真正的问题不是旧 SNI 坏了，而是这台服务器没有可用 IPv6 出口。REALITY 握手去连接伪装站时解析并尝试了 IPv6 地址，日志出现：

```text
REALITY: failed to dial dest ... connect: network is unreachable
```

因此修复方向是：让 REALITY 握手目标强制走 IPv4，而不是更换或“修好”某个 SNI 本身。

## Resolution

### REALITY 配置

已恢复原来的 SNI 和握手服务器，并强制 IPv4-only：

```text
server_name: assets-xbxweb.xbox.com
handshake.server: assets-xbxweb.xbox.com
handshake.domain_strategy: ipv4_only
```

节点导出的服务器地址保持为：

```text
74.211.103.83:443
```

已修正所有客户端订阅 / 导出链接：

```text
客户端总数: 22
带 flow=xtls-rprx-vision: 22
残留 127.0.0.1:443: 0
残留 iosapps.itunes.apple.com: 0
使用 assets-xbxweb.xbox.com: 22
```

### 服务重启

修改配置后重启了 `s-ui`，并确认：

```text
s-ui.service: active (running)
sing-box started
443 由 s-ui 监听
```

### 外部验证

从服务器外部验证 `74.211.103.83:443`，使用 SNI `assets-xbxweb.xbox.com` 时能正常返回 Xbox/Microsoft 证书：

```text
Peer certificate: CN=*.xbox.com
Protocol version: TLSv1.3
```

## 配套升级

故障修复同期完成系统与面板升级，避免旧版本内核/面板遗留问题。

### 升级前

```text
Rocky Linux: 9.6
S-UI Panel: 1.3.7
Sing-Box: v1.12.8
Kernel: 5.14.0-570.58.1.el9_6.x86_64
```

### 升级后

```text
Rocky Linux: 9.7
S-UI Panel: 1.4.1
Sing-Box: v1.13.4
Kernel: 5.14.0-611.49.1.el9_7.x86_64
```

已完成系统包升级，并重启服务器让新内核生效。

重启后确认：

```text
s-ui: active
nginx: active
firewalld: active
needs-restarting -r: Reboot should not be necessary
```

## 网络和防火墙加固

已启用并配置 `firewalld`。

公网开放端口：

```text
22/tcp
80/tcp
443/tcp
8443/tcp
```

S-UI 面板和订阅端口不再暴露到公网。当前只监听本机回环地址：

```text
127.0.0.1:2095  # S-UI 面板
127.0.0.1:2096  # 订阅服务
```

S-UI 日志确认：

```text
web server run http on 127.0.0.1:2095
Sub server run http on 127.0.0.1:2096
sing-box started
```

### 面板访问方式

访问 S-UI 面板前，先在本地建立 SSH 端口转发：

```bash
ssh -L 2095:127.0.0.1:2095 -L 2096:127.0.0.1:2096 tizi
```

然后在浏览器打开：

```text
http://127.0.0.1:2095/app/
```

## 服务器上的备份

主维护快照：

```text
/root/tizi-maint-20260501-122610/
```

S-UI 数据库备份：

```text
/usr/local/s-ui/db/s-ui.db.before-ipv4-only-20260501
/usr/local/s-ui/db/s-ui.db.before-restore-xbox-sni-20260502
/usr/local/s-ui/db/s-ui.db.before-restore-client-links-sni-20260502
/usr/local/s-ui/db/s-ui.db.before-localhost-panel-20260502
```

主维护快照中包含升级前数据库、S-UI 二进制文件、systemd service、管理脚本、settings 导出和 REALITY 配置导出。

## 当前预期状态

```text
S-UI: 1.4.1
Sing-Box: v1.13.4
REALITY SNI: assets-xbxweb.xbox.com
REALITY handshake server: assets-xbxweb.xbox.com
REALITY handshake domain strategy: ipv4_only
代理入站: 443，对公网开放
面板: 127.0.0.1:2095
订阅: 127.0.0.1:2096
防火墙: 已启用
```

## Prevention / 后续维护注意事项

- 如果客户端再次超时，先看日志：`journalctl -u s-ui -n 100 --no-pager`。
- 如果日志里再次出现 IPv6 `network is unreachable`，优先确认 `domain_strategy` 是否仍为 `ipv4_only`。
- 如果浏览器打不开面板，先确认 SSH 隧道是否已建立。`2095/2096` 直接公网访问被刻意关闭。
- 如果以后再次升级 S-UI，升级后立即复查 SNI、handshake server、`domain_strategy` 和客户端导出链接。
- 不要随意更换 SNI。除非服务端和所有客户端一起迁移，否则会造成旧客户端无法连接。
- 同类无 IPv6 出口的代理节点（含备用节点）应预防性设置 `handshake.domain_strategy: ipv4_only`，不必等故障再现。

## Related

- 备用节点预防性加固：`docs/solutions/rao-tizi/best-practices/standby-proxy-node-ipv4-only-hardening-2026-05-02.md`
- 扩容节点对齐心智：`docs/solutions/tizi-ddy/best-practices/3x-ui-proxy-node-aligned-with-s-ui-2026-07-28.md`
