---
title: "multica setup self-host 报 Server is not reachable：--server-url 指到了前端"
date: 2026-08-19
category: docs/solutions/mac-mini/integration-issues
server: mac-mini
module: mac-mini / Multica self-host / CLI
problem_type: integration_issue
component: tooling
symptoms:
  - "multica setup self-host --server-url http://100.108.64.126:3000 报 Server is not reachable"
  - "Your existing configuration was left unchanged"
  - "前端 :3000 能打开，后端 :8080/health 实际是 200"
root_cause: config_error
resolution_type: config_change
severity: medium
tags:
  - mac-mini
  - multica
  - self-host
  - tailscale
  - health-check
---

# multica setup self-host 报 Server is not reachable：--server-url 指到了前端

## Problem

在 `mac-mini` 上把本机加为 Multica 运行时，执行：

```bash
multica setup self-host \
  --server-url http://100.108.64.126:3000 \
  --app-url http://100.108.64.126:3000
```

CLI 报 `Server at http://100.108.64.126:3000 is not reachable`，现有配置未改。

## Symptoms

- `multica setup self-host` 立刻失败，文案是 *not reachable*
- 浏览器或 `curl http://127.0.0.1:3000/` 能拿到 Next.js 页面（200）
- `curl http://127.0.0.1:3000/health` 是 **404**（前端没有这个端点）
- `curl http://127.0.0.1:8080/health` 是 **200** `{"status":"ok"}`

## What Didn't Work

- 把 `--server-url` 和 `--app-url` 都写成 Tailscale IP 的 **3000**：3000 是 Web UI，不是 API
- 以为 3000 连不上：服务是通的，只是健康检查打错了端口
- 用 `multica daemon status` 判断 konghai 的守护进程：当前看到的是 `hon` 已经在跑的 daemon（pid 6857，`--server-url http://localhost:8080`）

## Solution

`setup self-host` 会先打 `<server-url>/health`。`--server-url` 必须是 **backend API**，`--app-url` 才是前端。

本机已经跑着 hon 的 self-host（`colima-multica` 把 `*:8080` / `*:3000` 转到容器）：

| 角色 | 默认端口 | 本机验证 |
| --- | --- | --- |
| backend / `--server-url` | 8080 | `GET /health` → 200 `{"status":"ok"}` |
| frontend / `--app-url` | 3000 | `GET /` → 200 HTML；`GET /health` → 404 |

人已经 SSH 在 `mac-mini` 上时，直接用默认 localhost，不要绕 Tailscale：

```bash
multica setup self-host
```

等价于 `--server-url http://localhost:8080 --app-url http://localhost:3000`。

如果一定要写 Tailscale IP：

```bash
multica setup self-host \
  --server-url http://100.108.64.126:8080 \
  --app-url http://100.108.64.126:3000
```

compose 默认 `FRONTEND_ORIGIN=http://localhost:3000`。用 `http://100.108.64.126:3000` 做 `--app-url` 可能撞 CORS / 登录回跳，优先 localhost。

SSH 会话里 `setup` 要开浏览器登录。没有 GUI 时用 PAT：

```bash
multica login --token
```

或 `multica login --help` 里的 tunnel hint。

不要停 `hon` 的 daemon（`/Users/hon/.local/bin/multica daemon start --foreground --server-url http://localhost:8080`）。那是他已经注册好的 runtime。

## Why This Works

CLI 把「连得上」定义成 `<server-url>/health` 返回成功。前端 Next.js 没有这个路由，于是 404 被报成 unreachable。把 `--server-url` 改到 8080 后，同一条探测会命中 backend，返回 `{"status":"ok"}`。

UI 里「Add a computer」有时会把前端 URL 填进 `--server-url`（同类问题见 [multica#3816](https://github.com/multica-ai/multica/issues/3816)）。复制命令前先对一下端口。

## Prevention

- 默认就在 server 本机：`multica setup self-host`，不要手填 URL
- 手填时：`--server-url` 必须 `curl <url>/health` 得到 JSON `{"status":"ok"}`，不是 HTML
- `100.108.64.126` 是 `mac-mini` 自己的 Tailscale IPv4，不是另一台控制面
- 改 hon 的 Multica compose / `colima-multica` 端口前先看 `docs/plans/2026-08-16-001-ops-mac-mini-sub2api-deploy-plan.md`：宿主 `*:8080` 已被 Multica 占用

## Related Issues

- 官方：<https://multica.ai/docs/self-host-quickstart>
- [multica#3816](https://github.com/multica-ai/multica/issues/3816) — Cloud「Add a computer」把 frontend 当成 `--server-url`
- `docs/operations/mac-mini.md` — 2026-08-19 排查记录
