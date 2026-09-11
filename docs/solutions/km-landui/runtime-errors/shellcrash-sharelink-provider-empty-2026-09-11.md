---
title: ShellCrash 分享链接 provider 未被官方 sing-box 加载导致全程直连
date: 2026-09-11
category: docs/solutions/km-landui/runtime-errors
server: km-landui
module: km-landui / ShellCrash（sing-box 1.13 provider）
problem_type: runtime_error
component: tooling
severity: high
symptoms:
  - curl https://www.google.com 报 SSL Connection reset by peer
  - www.google.com 解析到 Facebook/Twitter IP（157.240.x / 104.244.x）
  - Clash API 里 Uri_group 只有 Compatible（Direct）
root_cause: config_error
resolution_type: configuration_change
tags:
  - km-landui
  - shellcrash
  - sing-box
  - vless
  - reality
  - dns-poison
---

# ShellCrash 分享链接 provider 未被官方 sing-box 加载导致全程直连

## Problem

`km-landui` 上 ShellCrash 本机 Tun 已经跑起来（SSH 回程已放行），但访问 Google 仍然失败：

```text
curl: (35) OpenSSL SSL_connect: Connection reset by peer
http=000 ip=157.240.7.20
```

`157.240.7.20` 是 Facebook，不是 Google。这是 GFW DNS 污染 + 流量直出昆明。

## Root Cause

`ShellCrash.cfg` 写着 `crashcore=singboxr`，运行中的内核是官方 **sing-box 1.13.14**。

导入节点时脚本把 `vless://...#kh-tizi` 写进 `providers/uri_group`，再配 `type: local` 的 provider。这套格式是 ShellCrash / 部分 fork 用的；官方 1.13 **不会**把分享链接展开成 outbound。

结果：

- URLTest 组 `Uri_group` 的 `all` 只有 `Compatible`（内核塞的 Direct 占位）
- `dns_proxy` 的 detour 也是这个空组 → `8.8.8.8` 从国内直出 → Google 被污染
- TCP 443 同样直出 → TLS RST

`tz.skysms.xyz:443`（tizi）从这台机 TCP 是通的，节点本身没挂。

## Resolution

把分享链接转成原生 `vless` outbound（REALITY + `xtls-rprx-vision`），写入 `/etc/ShellCrash/jsons/config.json`：

- tag `kh-tizi`
- selector / `Uri_group` urltest 的 `outbounds` 指向它
- 删除无效 `providers` 块

备份：`/etc/ShellCrash/jsons/config.json.bak.20260911`

不要在文档或 git 里写 UUID / pbk / sid。

## 验证

- API：`kh-tizi` 为 VLESS，urltest delay ~173ms
- `getent ahostsv4 www.google.com` 为 `142.251.x`（Google）
- 透明代理 `curl https://www.google.com` → HTTP 200
- `https://www.cloudflare.com/cdn-cgi/trace` → `ip=74.211.103.83` `loc=US`

## 以后导入节点

官方 sing-box 1.13 不要依赖 `providers/uri_group` 分享链接。要么写 JSON outbound，要么换确实支持该 provider 格式的内核。
