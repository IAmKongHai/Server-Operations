---
title: 宝塔面板 TrustAsia LiteSSL 被续期任务静默跳过导致过期
date: 2026-09-10
category: docs/solutions/nyh-prod/integration-issues
server: nyh-prod
module: nyh-prod / 宝塔面板
problem_type: integration_issue
component: tooling
symptoms:
  - 浏览器访问面板地址 https://nyh-2025.konghai.me:10463 提示 SSL 证书过期
  - 同域名 Nginx 443 站点证书仍然有效
  - 计划任务「更新面板SSL证书」日志每天打印 Successful，但面板证书从未被替换
root_cause: config_error
resolution_type: config_change
severity: high
tags: [baota, bt-panel, ssl-cert, cert-renewal, litessl, trustasia, nyh-prod]
---

# 宝塔面板 TrustAsia LiteSSL 被续期任务静默跳过导致过期

## Problem

宝塔面板 HTTPS（端口 10463）使用独立的证书文件，与同域名 Nginx 站点证书不是同一套。面板当时用的是 TrustAsia LiteSSL，到期后浏览器无法打开面板；站点 Let's Encrypt 仍有效。自动续期任务每天都在跑，但因为签发方不是 Let's Encrypt 而被静默跳过。

## Symptoms

- 访问 `https://nyh-2025.konghai.me:10463` 提示证书过期（`notAfter=2026-09-07`）
- 磁盘 `/www/server/panel/ssl/certificate.pem` 与 10463 端口返回的证书一致，都已过期（不是内存未 reload）
- 同域名站点证书 `/www/server/panel/vhost/cert/nyh-2025.konghai.me/fullchain.pem` 为 Let's Encrypt，到期 2026-11-18
- 每天 10:47 的「更新面板SSL证书」日志只有 OpenSSL deprecation warning 和包装脚本打印的 `★ Successful`，没有续签输出

## What Didn't Work

- 依赖 2026-05-11 加的 `panel-cert-reload.sh`：它只对比磁盘 vs 端口 `notBefore`。两边过期证书一致时记 `cert in sync, no action`，不会续签
- 依赖站点 `renew_v2`：站点续期只写 Nginx 证书目录，不会覆盖 `/www/server/panel/ssl/`
- 把任务日志里的 `★ Successful` 当成续签成功：那是 cron 包装脚本无条件打印的

## Solution

备份面板 SSL 目录，调用宝塔自带接口把站点有效 Let's Encrypt 复制到面板，再重启面板进程：

```bash
cp -a /www/server/panel/ssl/. /www/backup/ssl-cert/panel-ssl/<timestamp>/

# 从站点证书目录复制到面板 SSL（官方接口）
/www/server/panel/pyenv/bin/python3 - <<'PY'
import os, sys, json
os.chdir("/www/server/panel")
sys.path.insert(0, "class/")
import public, setPanelLets
print(setPanelLets.setPanelLets().check_cert_update("nyh-2025.konghai.me"))
info = public.get_cert_data("/www/server/panel/ssl/certificate.pem")
public.writeFile("/www/server/panel/ssl/info.json", json.dumps(info))
print(info)
PY

bt restart   # 只重启 BT-Panel / BT-Task，不影响 nginx / MySQL
```

验证磁盘与端口 fingerprint 一致，且 `issuer_O` 为 Let's Encrypt、`notAfter` 为站点证书到期日。

回滚：把备份目录里的 `certificate.pem` / `privateKey.pem` / `info.json` 拷回 `/www/server/panel/ssl/`，再 `bt restart`。

## Why This Works

`panel_ssl_task.py` 开头只认 Let's Encrypt：

```python
if cert_info and cert_info['issuer'] in ["R10", "Let's Encrypt", "R8", "R11", "R5", "R3"] \
   or cert_info.get('issuer_O', "") == "Let's Encrypt":
    ...
```

TrustAsia LiteSSL（`issuer_O=TrustAsia Technologies, Inc.`）走不到续签分支，脚本直接退出。换成 Let's Encrypt 后，该任务会在剩余天数小于总有效期约 1/3 时调用 `setPanelLets.check_cert_update`，从站点证书目录取新证写入面板。

面板进程启动时把证书读进内存，所以磁盘替换后必须 `bt restart` 才会在 10463 生效。

## Prevention

- 面板证书不要用 TrustAsia LiteSSL；与同域名站点统一走 Let's Encrypt，这样「更新面板SSL证书」才会真正续签
- 不要把任务包装日志的 `★ Successful` 当成单张证书续签成功
- `panel-cert-reload.sh` 只能解决「磁盘已新、内存仍旧」；它不能代替续签。巡检要同时看面板证书 `notAfter` 和签发方
- 站点续期成功不等于面板 HTTPS 已更新，两套路径要分开核对

## Related Issues

- `docs/solutions/nyh-prod/integration-issues/baota-panel-stale-ssl-cert-in-memory-2026-05-11.md` — 磁盘已续签但面板进程未 reload，症状相似、根因不同
- `docs/solutions/nyh-prod/integration-issues/baota-ssl-acme-challenge-routing-fix-2026-05-19.md` — Docker 反代域名不进 `renew_v2` 扫描
- `docs/operations/nyh-prod.md` — 2026-08-20 站点从 TrustAsia 换 Let's Encrypt 时未同步面板 SSL
