---
title: 宝塔 Docker 反代域名 SSL 证书未自动续期
date: 2026-05-20
category: docs/solutions/nyh-prod/integration-issues
server: nyh-prod
module: nyh-prod / 宝塔 Docker 功能面板
problem_type: integration_issue
component: tooling
symptoms:
  - Docker 功能面板反代域名的 Let’s Encrypt 证书过期
  - 宝塔 renew_v2 续期任务没有覆盖这些域名
  - renew_v2 --index 对 Docker 反代域名提示域名不存在或没有可用文件验证站点
  - .well-known/acme-challenge 请求曾被业务路由吸收并返回 404 或 502
root_cause: config_error
resolution_type: workflow_improvement
severity: high
tags: [baota, bt-panel, docker, reverse-proxy, ssl-cert, cert-renewal, acme, nyh-prod]
---

# 宝塔 Docker 反代域名 SSL 证书未自动续期

## Problem

`nyh-prod` 上由宝塔 Docker 功能面板维护的反代域名没有进入宝塔普通“网站”模块的 `sites` / `domain` 映射。宝塔 `renew_v2` 默认续期流程依赖这些映射来判断域名属于哪个站点，因此会跳过 Docker 反代域名，或在指定 `--index` 时提示域名不存在。

这次还叠加了 `/.well-known/acme-challenge/` include 文件为空的问题，导致 HTTP-01 验证请求一度落入业务路由，返回应用 404/502。

## Symptoms

- `admin.acquilangai.com` 执行 `renew_v2 --index` 时提示“域名不存在 / 没有找到可用的文件验证站点”
- 宝塔 `renew_v2` 全量任务能运行，但不会把 Docker 功能面板域名放入有效续期队列
- 目标域名的 `/.well-known/acme-challenge/` 曾返回业务 404/502，而不是 ACME token
- 443 端口返回过期证书，证书到期日集中在 2026-03-22、2026-05-10、2026-05-18

## Solution

保留 Docker 功能面板作为这些反代站点的管理入口，不把它们迁入宝塔普通“网站”列表。续期改为独立脚本维护：

```text
/www/server/cron/custom/docker-panel-letsencrypt-renew.py
```

脚本每次运行时动态扫描 `/www/server/panel/vhost/nginx/*.conf`，从 vhost 中提取：

- `server_name`
- `root`
- `ssl_certificate`
- `proxy_pass`
- `well-known` include
- Docker 面板生成的 `/www/dk_project/sites/.../proxy_cache_dir` 标记

然后排除宝塔普通网站表中的域名，以及明确废弃的域名。对剩余 Docker/反代候选域名，读取当前证书 SAN 和剩余天数；只有剩余天数小于等于阈值时才调用宝塔自带 ACME 客户端显式申请：

```bash
/www/server/panel/pyenv/bin/python3 -u /www/server/panel/class/acme_v2.py \
  --domain "<domains from current certificate SAN>" \
  --type http \
  --path "<vhost root>"
```

申请成功后，脚本会执行 Nginx 配置检查，通过后 reload Nginx，并读取 443 端口证书确认新证书已加载。

## Why This Works

`renew_v2` 的默认扫描和 `--index` 续期路径会读取宝塔站点/域名映射，因此不适合 Docker 功能面板反代域名。

显式 HTTP-01 申请路径不依赖 `domain` 表，只依赖：

- 域名解析到当前服务器
- HTTP-01 token 能从指定 webroot 被访问
- Nginx vhost 引用的证书目录可被宝塔 `sub_all_cert()` 替换

`admin.acquilangai.com` 已作为试点验证成功：磁盘证书与 443 端口证书都更新到 2026-08-17。

## Verification

2026-05-20 00:37-00:39 CST 执行动态发现脚本，结果：

```text
discovered candidates=7 skipped=17 dry_run=False threshold_days=30
complete renewed=6 failed=0 dry_run=False
```

7 个目标域名的 443 端口证书到期时间：

```text
acquilangai.com       Aug 17 15:39:29 2026 GMT
admin.acquilangai.com Aug 17 15:23:57 2026 GMT
admin.ddricher.ai     Aug 17 15:39:43 2026 GMT
api.acquilangai.com   Aug 17 15:39:56 2026 GMT
api.ddricher.ai       Aug 17 15:40:12 2026 GMT
duowei.konghai.me     Aug 17 15:40:25 2026 GMT
m.acquilangai.com     Aug 17 15:40:39 2026 GMT
```

定时任务入口：

```cron
20 2 * * *  flock -xn /www/server/cron/custom/docker-panel-letsencrypt-renew.lock -c "/www/server/cron/custom/docker-panel-letsencrypt-renew.py --threshold-days 30" >> /www/server/cron/custom/docker-panel-letsencrypt-renew.log 2>&1
```

## Rollback

脚本和 crontab 回滚：

```bash
crontab /www/backup/cron/root-crontab-20260520003927.bak
rm -f /www/server/cron/custom/docker-panel-letsencrypt-renew.py
```

单域名证书回滚：

```bash
cp -a /www/backup/ssl-cert/<domain>/<timestamp>/* /www/server/panel/vhost/cert/<domain>/
nginx -t && service nginx reload
```

注意：证书备份必须放在 `/www/server/panel/vhost/cert` 之外。宝塔 `sub_all_cert()` 会扫描该目录并替换同域名旧证书；如果把备份目录放在其中，备份也会被替换成新证书。

## Prevention

- 新增 Docker 功能面板反代站点后，不需要手工加入续期清单；脚本会通过 vhost 动态发现
- 只有明确废弃或不应续期的域名需要加入脚本排除清单
- 上线或调整脚本后先执行 dry-run，确认候选、排除、跳过和计划续期域名符合预期
- 对多 SAN 证书，续期时必须使用当前证书 SAN 的完整域名集合，避免只申请主域名导致自动替换逻辑无法命中原证书目录

