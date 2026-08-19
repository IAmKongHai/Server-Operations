---
title: "SSH 上 multica setup 只转发回调口后，本机 localhost:3000/login 打不开"
date: 2026-08-19
category: docs/solutions/mac-mini/integration-issues
server: mac-mini
module: mac-mini / Multica CLI login
problem_type: integration_issue
component: tooling
symptoms:
  - "Remote SSH session detected，提示 ssh -L <callback> 后再打开 localhost:3000/login"
  - "本机浏览器打不开登录页或一直转圈"
  - "mac-mini 上的 setup 一直停在 Waiting for authentication"
root_cause: incomplete_setup
resolution_type: config_change
severity: medium
tags:
  - mac-mini
  - multica
  - ssh-tunnel
  - cli-login
---

# SSH 上 multica setup 只转发回调口后，本机 localhost:3000/login 打不开

## Problem

在 `mac-mini` 的 SSH 会话里跑 `multica setup self-host`，CLI 侦测到远程会话后打印：

```text
ssh -L 55942:127.0.0.1:55942 <user>@<remote-host>
Then open the URL above in your local browser.
```

URL 是 `http://localhost:3000/login?cli_callback=http://localhost:55942/callback&...`。本机只转发了 `55942` 就打开这条 URL，登录页打不开，setup 一直等。

## Symptoms

- 本机 `curl http://127.0.0.1:3000/login` → connection refused
- 本机 `127.0.0.1:55942` 已在听（SSH `-L`），打 `/callback` 会回到 mac-mini 上的 CLI（缺参数时 400）
- mac-mini 上 `multica setup self-host` 仍在，`127.0.0.1:55942` 由该进程监听
- 经 Tailscale 访问 `http://100.108.64.126:3000/login` 是 200，标题为 Multica

## What Didn't Work

- 只转发回调口，却打开提示里的 `http://localhost:3000/login`：3000 在 **mac-mini**，不在笔记本
- 提示文案只提 callback 端口，容易让人以为登录页也在本机

## Solution

登录页和回调是两件事，都要能从**跑浏览器的那台机器**到达：

| 地址 | 作用 | 在哪 |
| --- | --- | --- |
| `:3000/login` | 网页登录 | mac-mini 上 hon 的 Multica 前端 |
| `:55942/callback` | 登录成功后把 token 交回 CLI | `setup` 进程在 mac-mini 上监听 `127.0.0.1` |

**做法 A（当前这次、隧道已建好）：** 不要动 `setup` 和 `-L 55942`，本机浏览器打开 **mac-mini 的前端**，callback 仍用 localhost（走已有隧道）：

```text
http://100.108.64.126:3000/login?cli_callback=http%3A%2F%2Flocalhost%3A55942%2Fcallback&cli_state=<CLI 打印的 state>
```

`cli_state` 必须和这一次 `setup` 打印的完全一致。

**做法 B：** 登录页也转发到本机，再用 CLI 打印的原 URL：

```bash
ssh -L 3000:127.0.0.1:3000 -L 55942:127.0.0.1:55942 konghai@mac-mini
```

端口号以当次 `setup` 打印为准，换一次 setup 回调口会变。

**做法 C（2026-08-19 实际采用）：** 不走浏览器。本机 self-host 对 `k@cypresso.ai` 接受开发验证码 `888888`，签发 PAT 后：

```bash
multica login --token
```

默认 profile 的 `daemon start` 会把 **hon** 已在跑的进程（pid 6857）当成「本机 daemon 已存在」并拒绝启动。必须用独立 profile：

```bash
multica --profile konghai daemon start \
  --device-name mac-mini \
  --runtime-name mac-mini-konghai \
  --daemon-id mac-mini-konghai
```

日常状态：

```bash
multica --profile konghai daemon status
multica --profile konghai auth status
```

不要对默认 profile 执行 `daemon restart` / `daemon stop`，那会动到 hon 的 runtime。

## Why This Works

CLI 的 callback 只绑在 mac-mini 的 `127.0.0.1`。`-L 55942` 让本机浏览器能打回这个端口。登录页本身仍在 mac-mini `:3000`。本机没转 3000 时，`localhost:3000` 是空的。

经 Tailscale 打开 `:3000` 时 Origin 是 `http://100.108.64.126:3000`。2026-08-19 探测 backend 对这个 Origin 回了 `Access-Control-Allow-Origin`，登录 API 可以走。登录成功后页面跳到 `cli_callback`（本机 `localhost:55942`），token 经隧道回到还在等的 `setup`。

## Prevention

- SSH 远程跑 `setup` / `login` 时：转发 callback，登录页用 `http://<mac-mini Tailscale>:3000/login?...`，不要用本机 3000
- 或同时 `-L 3000` 和 `-L <callback>`
- 优先 PAT：`multica login --token`，没有 callback
- 不要停 `hon` 已有的 daemon
- 同一台机器两个账号各跑一套 daemon：用 `--profile`，不要 `daemon restart` 默认 profile
- 日常请用 `multica --profile konghai …`，不要省略 `--profile`

## Related Issues

- `docs/solutions/mac-mini/integration-issues/multica-setup-self-host-server-url-frontend-2026-08-19.md` — `--server-url` 误指前端
- `docs/operations/mac-mini.md` — 2026-08-19 排查记录
