---
title: 只重建 API 容器后前端 nginx 仍用旧 Docker DNS，跨服务路由 404
date: 2026-09-10
category: docs/solutions/dev-cypresso/runtime-errors
server: dev-cypresso
module: dev-cypresso / EVP compose 前后端拆分
problem_type: runtime_error
component: tooling
symptoms:
  - "页面和 /health/ready 都是 200，但 POST /api/provider/v1/auth/login 与管理端登录返回 JSON 404"
  - "docker logs evp-provider-api 里出现 /api/admin/v1/... 请求，evp-admin-api 里出现 /api/provider/v1/..."
  - "容器 inspect 显示镜像、PUBLIC_ORIGIN、网络 alias 都正确，直接 wget 本容器 /api/<自己>/v1/system 是 401 不是 404"
root_cause: config_error
resolution_type: config_fix
severity: medium
tags: [docker-compose, dns, nginx, recreate, evp, dev-cypresso]
---

# 只重建 API 容器后前端 nginx 仍用旧 Docker DNS，跨服务路由 404

## Problem

EVP 生产把医院端 / 管理端拆成 `*-api` + `*-web` 四个容器。web 镜像里的 nginx 用上游主机名 `provider-api` / `admin-api` 反代 API。只对 API 做 `docker-compose up -d --no-deps --force-recreate` 时，API 拿到新 IP，web 进程不重启，nginx 在启动时解析并缓存的 Docker DNS 仍指向旧 IP。旧 IP 上现在跑的是另一套 API（或 web 自己），于是医院端的 `/api/provider/v1/` 打进管理端二进制（或反过来），表现为登录 404，健康检查却仍然 200（`/health/` 碰巧还能打到一个听 8080 的进程）。

## Symptoms

- `https://<provider>/` 与 `/health/ready` 200，`POST /api/provider/v1/auth/login` 返回 `{"message":"Not Found"}`
- `docker logs evp-provider-api` 出现 `uri=/api/admin/v1/auth/login`，`evp-admin-api` 出现 provider 路径
- 从 API 容器本机 `wget /api/<自己>/v1/system` 是 401（路由在），`/api/<对方>/v1/system` 才是 404
- web 容器 `getent hosts provider-api` 已经是新 IP，但 nginx 工作进程仍连旧地址

## What Didn't Work

- 只看 compose `image:` / `PUBLIC_ORIGIN` / `container_name`——这些都是对的，问题不在 yaml
- 以为 404 是 Origin / CORS：错误 Origin 在本项目里是 **403**，不是 404
- 只重建 API、不碰 web：`--no-deps` 正是把 web 留在旧 DNS 缓存里的原因

## Solution

改 API 环境变量或强制 recreate API 之后，**同一 compose 项目里用主机名反代这些 API 的 web 也要 recreate 或至少 reload 到会重新解析 DNS 的状态**：

```bash
docker-compose --project-directory /home/ec2-user/stacks/evp \
  -f /home/ec2-user/stacks/evp/docker-compose.yml \
  up -d --no-build --no-deps --force-recreate \
  provider-api admin-api provider-web admin-web
```

不要对同机其它项目加 `--remove-orphans`。验证时除了 `/health/ready`，还要用**正确 Origin** POST 登录，并确认 `docker logs` 里 provider 路径只出现在 `evp-provider-api`。

## Why This Works

Docker 内嵌 DNS 会随容器 IP 变化更新。nginx `proxy_pass http://provider-api:8080;` 这种不带变量的上游在 worker 启动时解析一次，之后不再查。web 不重建就继续把流量送到 recreate 之前的 IP。health 路径两边 API 都实现了，所以只看 health 会误判“已经好了”。

## Prevention

1. 重建会换 IP 的上游时，把依赖它的反代容器列入同一条 recreate 名单，或给 nginx 配 `resolver 127.0.0.11` + 变量形式的 `proxy_pass`。
2. 验证清单不要停在 health：至少打一条带业务前缀的 API（登录或 `/api/<audience>/v1/system`）。
3. 对拆分的一对 API，看 logs 的 `uri` 前缀是否和容器名一致，能立刻发现交叉命中。
