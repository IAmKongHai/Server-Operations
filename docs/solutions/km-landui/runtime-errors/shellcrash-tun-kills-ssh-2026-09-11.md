---
title: ShellCrash 本机 Tun 透明代理启动后劫持 SSH 回程导致无法重连
date: 2026-09-11
category: docs/solutions/km-landui/runtime-errors
server: km-landui
module: km-landui / ShellCrash（sing-box Tun 本机透明代理）
problem_type: runtime_error
component: tooling
severity: high
symptoms:
  - crash 菜单选择启动服务后，当前 SSH 会话立刻断开
  - 之后 ssh km-landui 再也连不上，必须重启服务器
  - sshd 仍在监听 28285，不是 sshd 崩溃
  - 同一时刻 derper 已建立的客户端连接也被 RST
root_cause: config_error
resolution_type: configuration_change
tags:
  - km-landui
  - shellcrash
  - sing-box
  - tun
  - nftables
  - ssh
  - transparent-proxy
---

# ShellCrash 本机 Tun 透明代理启动后劫持 SSH 回程导致无法重连

## Problem

服务器：`km-landui` / `43.228.79.237`，SSH 端口 **`28285`**（不是 22）。本机还跑 `derper`（`:443`）和 RustDesk。

用户安装了 [juewuy/ShellCrash](https://github.com/juewuy/ShellCrash)（`/etc/ShellCrash`，`1.9.5beta3`，内核 `singboxr 1.13.14`）。在 SSH 会话里运行 `crash`，选启动服务后：

- 当前 SSH 立刻断开
- 新 SSH 连不上
- 必须重启机器才能再登录

`shellcrash.service` 是 `disabled`，且存在 `/etc/ShellCrash/.dis_startup`，所以**重启后不会自启**，这才表现为「重启就能连上」。

## Root Cause

这不是 sshd 挂了，而是 **本机 Tun 透明代理把 sshd 的回程包拐进 `utun`**。

当前 `configs/ShellCrash.cfg` 关键项：

```text
firewall_area=2          # 仅本机
redir_mod=Tun
common_ports=OFF         # 拦截全部 TCP/UDP，不只 80/443
local_proxy=ON
firewall_mod=nftables
crashcore=singboxr
```

启动路径：

1. CrashCore 创建 TUN 设备 `utun`（sing-box `auto_route: false`，路由由脚本接管）
2. `fw_start.sh`：`ip route add default dev utun table $table` + `ip rule add fwmark $fwmark table $table`
3. `fw_nftables.sh`：`firewall_area=2` → `local_proxy=true`，对 **OUTPUT** 链 `meta l4proto {tcp, udp} mark set $fwmark`
4. `common_ports=OFF` 时，**没有**「目的端口不在常用端口则 return」这条放行

sshd 回包的目的地址是客户端公网 IP、目的端口是客户端高位 ephemeral 端口（例如 `14839`）。这些都不在保留地址 / 本机网段里，也不是 gid `7890`（CrashCore 自己的流量才绕过）。于是回程被 mark 进 `utun`，TCP 对端看到 RST / 超时。

新建 SSH 也走同一条路：SYN 能进 `eth0:28285`，SYN-ACK 从 OUTPUT 出去时被劫持，三次握手永远完不成。

journal 对得上（两次，都是启动后约 1 秒）：

```text
# 2026-09-11 04:30:28Z Starting ShellCrash Core
# 2026-09-11 04:30:30Z utun Link UP；resolvectl domain utun ~. / default-route / dns 198.18.0.2
# 2026-09-11 04:30:31Z Started ShellCrash Core
# 2026-09-11 04:30:32Z sshd: Read error from remote host 112.117.55.212 port 14839: Connection reset by peer
```

2026-09-10 08:21 UTC 同一模式，SSH 与多条 DERP 连接一起 RST。本机没有 `systemd-resolved`，`resolvectl` 那三步失败，DNS 劫持不是主因；真正掐断会话的是 nftables OUTPUT mark + TUN 默认路由。

## Resolution

保留 `firewall_area=2` + `redir_mod=Tun` + `common_ports=OFF`（全端口本机透明代理），在 nftables OUTPUT 链的 JUMP **之前**放行入站回程：

```text
ct direction reply return
tcp sport 28285 return
```

- `ct direction reply`：所有入站连接的回包（SSH / derper / RustDesk）不进 `utun`
- `tcp sport 28285`：即使 conntrack 丢了，sshd 回包也直出 `eth0`
- 本机主动发起的 NEW 连接仍被 mark 进 Tun

落地文件：

| 路径 | 作用 |
| --- | --- |
| `/etc/ShellCrash/configs/fw_protect_inbound.sh` | 规则本体（升级一般不会覆盖 `configs/`） |
| `/etc/ShellCrash/starts/fw_nftables.sh` | 建链时 `add`（无窗口，主路径） |
| `/etc/ShellCrash/starts/afstart.sh` | `fw_start.sh` 之后立刻 `insert`（备份） |
| `/etc/ShellCrash/configs/task/afstart` | 官方钩子再 insert 一次（备份；后台跑） |

备份：`fw_nftables.sh.bak.20260911`、`afstart.sh.bak.20260911`。

回滚：

```bash
cp -a /etc/ShellCrash/starts/fw_nftables.sh.bak.20260911 /etc/ShellCrash/starts/fw_nftables.sh
cp -a /etc/ShellCrash/starts/afstart.sh.bak.20260911 /etc/ShellCrash/starts/afstart.sh
systemctl stop shellcrash
```

**不要**用「常用端口」当主方案：那会把透明代理收成只拦 `22,80,443,8080,8443`。

### 验证（2026-09-11 13:12 CST）

- `shellcrash.service` **active**，`utun` UP，OUTPUT 链里上述两条 return 在 JUMP 之前
- 原 SSH 会话还在；`ControlMaster=no` 新建 SSH 成功
- derper / hbbs / hbbr 仍在听
- systemd 保持 **disabled**（开机不自启）。升级 ShellCrash 会覆盖 `starts/*.sh`，覆盖后必须再打补丁，否则会再次锁死 SSH

### 透明代理与节点

流量劫持路径已通。当前 `Uri_group` 健康检查落到 `Compatible`（Direct），`cloudflare.com/cdn-cgi/trace` 仍显示 `ip=43.228.79.237`。这是节点/订阅问题，不是 SSH 劫持。要出国先把 VLESS 组调到可用节点。
