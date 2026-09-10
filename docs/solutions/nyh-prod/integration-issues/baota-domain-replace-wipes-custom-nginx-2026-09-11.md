---
title: 宝塔 Docker 反代改域名会冲掉自定义 Nginx（CORS / 静态托管）
date: 2026-09-11
category: docs/solutions/nyh-prod/integration-issues
server: nyh-prod
module: nyh-prod / 宝塔 Docker 反代 / AcquiLang
problem_type: integration_issue
component: tooling
symptoms:
  - 只在宝塔里替换 Docker 反代域名后，站点变成 502 或前端不能登录
  - vhost 文件名仍是旧域名，server_name 已是新域名，证书 SAN 也是新的
  - 自定义 CORS 白名单、静态 root/try_files 消失，变回模板里的 proxy_pass
root_cause: config_error
resolution_type: config_fix
severity: high
tags: [baota, bt-panel, docker, reverse-proxy, nginx, cors, domain-cutover, acquilang, nyh-prod]
---

# 宝塔 Docker 反代改域名会冲掉自定义 Nginx（CORS / 静态托管）

## Problem

宝塔 Docker 功能面板里「替换域名」会按反代模板重生 vhost 的 `PROXY-CONF` 段。证书和 `server_name` 会更新，但站点里后来手工加的 CORS、静态 `root`/`try_files`、`sub_filter` 都会丢。前端构建产物里的 API 域名不会跟着改。

2026-09-11 把 AcquiLang 从 `*.acquilangai.com` 临时切到 `*-al.konghai.me` 时踩中：`m-al` 502，`admin-al` 页面能开但不能登录。`api-al` 后端其实是通的。

## Symptoms

- `https://m-al.konghai.me/` 返回 502；error log 是 `connect() failed (111) ... 127.0.0.1:3002`
- 本机没有 `acquilang-mobile` 容器，也没有人监听 3002
- `https://admin-al.konghai.me/` 200，但 JS 仍是 `baseURL:"https://api.acquilangai.com"`，容器 CSP 只允许连旧 API
- 旧 API 域名 DNS 还指向本机，但已无匹配 `server_name`，SNI 落到默认站（证书 subject 为空）
- 新 API 用错误密码 POST 登录是 401（业务通），响应没有 `Access-Control-Allow-Origin`；OPTIONS 是 405

## Solution

不要指望宝塔换域名保留自定义段。换完立刻对照备份，把 CORS / 静态托管加回去，再 `nginx -t && nginx -s reload`。

本次落地：

1. **mobile** 按 `docs/deployment/MOBILE-WEB-STATIC-HOSTING.md`（AcquiLang 仓库）改回静态目录 `/www/wwwroot/python/acquilang/acquilang-mobile-web/out`，不要反代 3002。
2. **API** 在 `location ^~ /` 恢复 CORS 白名单（这次是 `https://admin-al.konghai.me` 和 `https://m-al.konghai.me`），OPTIONS 返回 204。后端 `APP_ENV=production` 自己不加 CORS。
3. **admin** 构建期 API 域名来不及重打镜像时，反代层临时 `sub_filter`，并盖掉容器 CSP 的 `connect-src`。必须 `proxy_set_header Accept-Encoding ""` 且不要 `proxy_buffering off`，否则替换不到 JS。

`sub_filter_types` 不要再写 `text/html`（默认已包含，重复会 warn）。

长期：重建 admin 镜像和 mobile `out/`，改 `VITE_API_BASE_URL` / `NEXT_PUBLIC_API_URL`。宝塔里再点保存会再次冲掉这些段，改完对照备份。

## Prevention

- 改宝塔 Docker 反代域名之前，先把 vhost 拷到 `/www/backup/nginx-vhost/`。
- 换完立即 `diff` 备份 vs 新文件，重点看 `PROXY-CONF` 和 `SERVER-BLOCK`。
- 前端 API 地址是构建期常量，只改 Nginx `server_name` 不够。
- 生产 mobile 走静态托管，不要依赖已删除的 `:3002` 容器。
