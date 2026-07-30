---
title: 备用代理节点预防性 IPv4-only 与暴露面加固
date: 2026-05-02
category: docs/solutions/rao-tizi/best-practices
server: rao-tizi
module: rao-tizi / S-UI + sing-box（备用代理）
problem_type: best_practice
component: tooling
severity: medium
applies_when:
  - 备用代理节点仍可连，但日志已出现 REALITY IPv6 network is unreachable
  - 服务器无可用 IPv6 出口，REALITY 握手域名同时有 A/AAAA 记录
  - 面板/订阅仍监听公网、firewalld 未启用、导出链接写成 127.0.0.1
  - 巡检主节点同类故障后，需要对备用节点做对齐加固
tags:
  - rao-tizi
  - s-ui
  - sing-box
  - reality
  - vless
  - ipv6
  - domain-strategy
  - ipv4-only
  - firewalld
  - panel-localhost
  - standby-proxy
---

# 备用代理节点预防性 IPv4-only 与暴露面加固

## Context

服务器：`rao-tizi` / `64.64.253.141`。服务为 S-UI 面板 + sing-box 内核，用作**备用**代理节点。

2026-05-02 该节点当时没有明显不可用现象，客户端仍可连接。巡检发现：

```text
s-ui 服务在运行
443 端口在监听
2095/2096 面板和订阅端口公网监听
firewalld 未运行
S-UI 版本为 1.3.7
Sing-Box 版本为 v1.12.8
```

同时日志里已经出现了和主节点 `tizi` 相同类型的 REALITY IPv6 握手错误：

```text
REALITY: failed to dial dest ...
dial tcp [IPv6]:443: connect: network is unreachable
```

服务器对当前伪装站 `iosapps.itunes.apple.com` 的 IPv4 访问正常，但 IPv6 不通：

```text
iosapps.itunes.apple.com IPv4 可通
iosapps.itunes.apple.com IPv6 不通
```

因此该节点存在同样的隐患：REALITY handshake 在某些情况下解析并尝试 IPv6，会因服务器无 IPv6 出口而失败。应在故障爆发前做预防性修复，并顺手收敛暴露面。

主节点故障复盘见：`docs/solutions/tizi/runtime-errors/reality-handshake-ipv6-unreachable-2026-05-02.md`。

## Guidance

### 1. 维护前关键配置（便于对照）

```text
SNI: iosapps.itunes.apple.com
handshake.server: iosapps.itunes.apple.com
handshake.domain_strategy: 未设置
导出节点地址: 127.0.0.1:443
日志级别: info
面板监听: 公网 2095
订阅监听: 公网 2096
防火墙: 未启用
```

客户端链接统计：

```text
客户端数: 7
带 flow=xtls-rprx-vision: 7
链接中含 127.0.0.1: 7
```

### 2. REALITY：保留现有 SNI，强制 IPv4-only

备用节点已有客户端绑定现有 SNI，**不要为了对齐主节点而随意换 SNI**，除非服务端和所有客户端一起迁移。

保留：

```text
server_name: iosapps.itunes.apple.com
handshake.server: iosapps.itunes.apple.com
```

新增：

```text
handshake.domain_strategy: ipv4_only
```

这样 handshake 只解析/拨打 IPv4，避开无 IPv6 出口时的 `network is unreachable`。

### 3. 导出链接：从 127.0.0.1 改为公网 IP

将导出节点地址从本机地址改为公网 IP：

```text
64.64.253.141:443
```

修复后客户端链接统计：

```text
客户端数: 7
带 flow=xtls-rprx-vision: 7
残留 127.0.0.1: 0
使用 64.64.253.141:443: 7
```

`127.0.0.1` 写进导出串只在本机有意义，分发后客户端会连到自己本机而非代理节点。

### 4. 日志级别：info → warn

将 S-UI/sing-box 日志级别从 `info` 降为：

```text
warn
```

减少对用户访问目标的详细记录，降低日志体积与隐私面。

### 5. 面板与订阅收回环

将面板和订阅服务改为仅监听本机回环：

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

访问面板前先建 SSH 隧道：

```bash
ssh -L 2095:127.0.0.1:2095 -L 2096:127.0.0.1:2096 rao-tizi
```

浏览器打开：

```text
http://127.0.0.1:2095/app/
```

### 6. 升级对齐主节点栈版本

#### 升级前

```text
Rocky Linux: 9.7
S-UI Panel: 1.3.7
Sing-Box: v1.12.8
Kernel: 5.14.0-611.16.1.el9_7.x86_64
```

#### 升级后

```text
Rocky Linux: 9.7
S-UI Panel: 1.4.1
Sing-Box: v1.13.4
Kernel: 5.14.0-611.49.1.el9_7.x86_64
```

升级完成后已重启服务器，新内核已生效。

重启后确认：

```text
s-ui: active
firewalld: active
needs-restarting -r: Reboot should not be necessary
```

安装脚本过程中出现过一次提示：

```text
duplicate column name: delay_start
```

后续验证显示 S-UI 服务、数据库配置、入站监听和客户端链接均正常。该提示可视为升级脚本对已有库的幂等告警，不单独阻断；以服务与配置验收为准。

### 7. 防火墙：启用并收紧公网

已启用并设置 `firewalld` 开机自启。

公网开放端口：

```text
22/tcp
443/tcp
```

`2095/2096` 不再公网开放，并且服务本身也只监听 `127.0.0.1`（双重收敛：监听地址 + 防火墙）。

备用节点相对主节点更“纯代理”，公网不必额外开 `80`/`8443`（主节点 `tizi` 因其它业务保留了这些端口）。

## Why This Matters

- **同类故障可预防**：主节点已因 IPv6 握手失败导致客户端超时；备用节点日志已出现同类错误，不处理会在握手走 AAAA 时间歇或完全不可用。
- **导出地址错误是静默炸弹**：链接里写 `127.0.0.1` 时，面板侧可能“看起来正常”，用户端却永远连不到节点。
- **面板公网暴露**：`2095/2096` 对公网监听 + 无防火墙，把管理面直接交给扫描；收回环 + firewalld 是最低成本加固。
- **日志 info 过细**：代理节点会记录访问目标相关信息，生产/长期运行宜降到 `warn`。
- **版本对齐**：备用节点与主节点同用 S-UI 1.4.1 / Sing-Box v1.13.4，减少“只修一台”带来的行为差异。

## When to Apply

- 无 IPv6 出口的 S-UI/sing-box REALITY 节点（主备均可）
- 巡检发现 REALITY 日志含 IPv6 `network is unreachable`，即使客户端仍能连
- 面板/订阅仍绑公网、firewalld 未开、导出串含 `127.0.0.1`
- 主节点刚修完同类问题，需要对备用节点做对齐加固

不适用：已有稳定 IPv6 出口且业务明确依赖 AAAA 的握手场景（本仓库代理节点族当前均无此需求）。

## Verification

### 外部 TLS / 证书

从服务器外部验证 `64.64.253.141:443`，使用 SNI `iosapps.itunes.apple.com` 时能正常返回 Apple 证书：

```text
Peer certificate: CN=itunes-ssl.itunes.apple.com
Protocol version: TLSv1.3
```

### 面板暴露面

公网访问 `2095/2096` 已不可达，服务器本机访问正常：

```text
http://127.0.0.1:2095/app/ -> 307 跳转到 /app/login
http://127.0.0.1:2096/sub/ -> 404，服务可达但路径无 token
```

### 服务器上的备份

主维护快照：

```text
/root/rao-tizi-maint-20260502-125312/
```

快照中包含：

```text
s-ui.db.before-maintenance
sui.before-maintenance
s-ui.sh.before-maintenance
s-ui.service.before-maintenance
version.before-maintenance.txt
settings-cli.before-maintenance.txt
db-summary.before-maintenance.txt
```

## 当前预期状态

```text
S-UI: 1.4.1
Sing-Box: v1.13.4
REALITY SNI: iosapps.itunes.apple.com
REALITY handshake server: iosapps.itunes.apple.com
REALITY handshake domain strategy: ipv4_only
代理入站: 443，对公网开放
面板: 127.0.0.1:2095
订阅: 127.0.0.1:2096
防火墙: 已启用
公网开放: 22/tcp, 443/tcp
```

## 后续维护注意事项

- 如果客户端再次超时，先看日志：`journalctl -u s-ui -n 100 --no-pager`。
- 如果日志里出现 IPv6 `network is unreachable`，优先确认 `domain_strategy` 是否仍为 `ipv4_only`。
- 如果浏览器打不开面板，先确认 SSH 隧道是否已建立。`2095/2096` 直接公网访问被刻意关闭。
- 如果以后再次升级 S-UI，升级后立即复查 SNI、handshake server、`domain_strategy` 和客户端导出链接。
- 该节点保留 `iosapps.itunes.apple.com` 作为 SNI，避免影响已有客户端。不要随意更换 SNI，除非服务端和所有客户端一起迁移。

## Related

- 主节点故障与修复：`docs/solutions/tizi/runtime-errors/reality-handshake-ipv6-unreachable-2026-05-02.md`
- 扩容节点对齐心智：`docs/solutions/tizi-ddy/best-practices/3x-ui-proxy-node-aligned-with-s-ui-2026-07-28.md`
