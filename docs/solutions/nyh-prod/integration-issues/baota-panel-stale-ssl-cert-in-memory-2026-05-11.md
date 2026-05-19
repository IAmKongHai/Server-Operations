---
title: 宝塔面板加载内存中过期 SSL 证书，磁盘新证书未生效
date: 2026-05-11
category: docs/solutions/nyh-prod/integration-issues
server: nyh-prod
module: nyh-prod / 宝塔面板
problem_type: integration_issue
component: tooling
symptoms:
  - 浏览器访问面板地址 https://nyh-2025.konghai.me:10463 提示 SSL 证书过期，无法登录
  - 磁盘上的 /www/server/panel/ssl/certificate.pem 实际已自动续签，有效期未过期
  - openssl s_client 连接面板端口返回的证书与磁盘文件不一致
root_cause: config_error
resolution_type: workflow_improvement
severity: high
tags: [baota, bt-panel, ssl-cert, cert-renewal, ops, nyh-prod]
---

# 宝塔面板加载内存中过期 SSL 证书，磁盘新证书未生效

## Problem
宝塔面板（BT-Panel）的 SSL 证书已自动续签到磁盘，但面板进程一直未重启，仍在使用内存中加载的旧证书。旧证书到期后，面板 Web 界面提示"证书过期"，导致管理员无法登录管理服务器。业务网站、数据库等其它服务不受影响。

## Symptoms
- 浏览器访问 https://nyh-2025.konghai.me:10463 显示 NET::ERR_CERT_DATE_INVALID 等过期错误
- `openssl x509 -in /www/server/panel/ssl/certificate.pem -noout -dates` 返回的有效期是新的（未过期）
- `echo | openssl s_client -connect 127.0.0.1:10463 -servername <host>` 返回的证书 notBefore 与磁盘上的不一致，是更早的旧证书
- `/www/server/panel/ssl/info.json` 显示 notAfter 是新日期，与浏览器看到的过期证书冲突

## What Didn't Work
- 直接登录面板修改：登录入口本身被证书过期阻断，无法走 UI 路径
- 重新申请证书：磁盘上的证书其实是新的，重新申请只会再覆盖一次，并不能让面板进程加载

## Solution
通过 SSH 登录服务器，重启面板进程让其重新读取磁盘上的新证书：

```bash
ssh nyh-prod
bt restart        # 等价于 /etc/init.d/bt restart
```

重启耗时 1-2 秒。`bt restart` 只重启 BT-Panel 和 BT-Tasks 两个进程，不影响 nginx、MySQL、Redis 等业务服务。

验证方法：
```bash
echo | openssl s_client -connect 127.0.0.1:10463 -servername nyh-2025.konghai.me 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```
`notBefore` / `notAfter` 应与 `/www/server/panel/ssl/certificate.pem` 一致。

## Why This Works
宝塔面板进程在启动时把 SSL 证书读入内存，之后续签写到磁盘的新文件并不会被自动重新加载。重启进程让其重新从磁盘读取，自然就用上新证书。本质是续签流程与面板进程之间缺少一个 reload 钩子。

## Prevention
在服务器上加一个每日 cron，对比磁盘证书与端口返回证书的 `notBefore`，不一致时自动重启面板。脚本位置：`/www/server/cron/custom/panel-cert-reload.sh`：

```bash
#!/bin/bash
set -u
CERT=/www/server/panel/ssl/certificate.pem
PORT=10463
HOST=nyh-2025.konghai.me
LOG=/www/server/cron/custom/panel-cert-reload.log

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

DISK_START=$(openssl x509 -in "$CERT" -noout -startdate 2>/dev/null | cut -d= -f2)
LIVE_START=$(timeout 5 bash -c "echo | openssl s_client -connect 127.0.0.1:$PORT -servername $HOST 2>/dev/null" \
             | openssl x509 -noout -startdate 2>/dev/null | cut -d= -f2)

if [ "$DISK_START" != "$LIVE_START" ]; then
  log "cert mismatch -> restarting panel (disk=$DISK_START live=$LIVE_START)"
  /etc/init.d/bt restart >> "$LOG" 2>&1
else
  log "cert in sync (notBefore=$DISK_START), no action"
fi
```

crontab 入口（root）：
```
30 4 * * *  /www/server/cron/custom/panel-cert-reload.sh
```

要点：
- 用对比策略而非"无脑定时重启"，绝大多数日子不会真正打断面板会话
- 重启后再读一次端口证书，留下日志便于审计
- 不要把这个 cron 加在宝塔 UI 里——若面板挂掉，UI 里的 cron 也跟着不可见；放在系统 crontab 里更可靠
- 日志路径 `/www/server/cron/custom/panel-cert-reload.log` 建议接入日常巡检

延伸适用：任何"磁盘续签 + 长驻进程持有旧证书"的组合（自建 nginx 跑 acme.sh 自动续签、Caddy 之外的反代等）都可以套这个对比 + 重启的范式。

## Related Issues
- 当前服务器上其它由宝塔托管的站点证书走 nginx，nginx 在续签后会自动 reload，不存在此问题
- 类似根因模式：长驻进程缓存配置/证书/密钥，但配置源已变更 → 缺少 reload 钩子
- Docker 功能面板反代域名不一定进入宝塔普通“网站”模块的续期扫描；相关复盘见 `docs/solutions/nyh-prod/integration-issues/baota-ssl-acme-challenge-routing-fix-2026-05-19.md`
