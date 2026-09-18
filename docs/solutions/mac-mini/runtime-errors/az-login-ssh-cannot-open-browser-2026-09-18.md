---
title: "SSH 上 az login 打不开浏览器（osascript -10810）"
date: 2026-09-18
category: docs/solutions/mac-mini/runtime-errors
server: mac-mini
module: mac-mini / azure-cli / az login
problem_type: runtime_error
component: tooling
symptoms:
  - "az login 提示已打开 https://login.microsoftonline.com/... 但本机没有浏览器窗口"
  - "osascript 报 execution error: 发生“-10810”类型错误"
  - "osascript 报 不能获得“application \"firefox\"”。 (-1728)"
root_cause: incomplete_setup
resolution_type: environment_setup
severity: medium
tags:
  - mac-mini
  - azure-cli
  - az-login
  - ssh
  - device-code
  - osascript
---

# SSH 上 `az login` 打不开浏览器（osascript -10810）

## Problem

在 **SSH 进 mac-mini** 的会话里跑 `az login`，Azure CLI 本身已装好，但默认交互登录要在本机弹出浏览器。mac-mini 当时没有 `konghai` 的图形会话，`osascript` 无法启动任何浏览器，登录卡住。

## Symptoms

- `az login` 打印 `A web browser has been opened at https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize`
- 紧接着多条 osascript 错误：`-10810`（Launch Services 拉不起 GUI 应用）和 `-1728`（没有 Firefox.app）
- `az account show` 仍是 `Please run 'az login' to setup account`

## What Didn't Work

- 再跑一次默认 `az login`：同样走 Python `webbrowser.MacOSXOSAScript`，同样 `osascript`，同样失败
- 指望本机已装的 Chrome / Safari / Edge：应用在 `/Applications` 里，但 SSH 会话没有 Aqua 会话，照样 `-10810`

## Solution

用设备代码流，在 **你面前的浏览器**（MacBook Air 或手机）完成登录：

```bash
az login --use-device-code
```

Azure CLI 2.90 打印的是 `https://login.microsoft.com/device`。那只是跳转入口；若页面没有输入框，直接打开 `https://login.microsoftonline.com/common/oauth2/deviceauth`。标题会写成「登录到您的帐户」，真正要找的是「输入代码以允许访问」和占位符「代码」（不是邮箱）。

登录后订阅选择器里两条都叫 `Microsoft Azure`：选 `408f1434-56ae-45b6-9762-7c9e1e615000`（默认 `[1]`，iCare 2.0 UAT/PROD）。`e026db6e-...` 是老 IHC，不要选。2026-09-18 用户已用 `--use-device-code` 完成，身份 `byang@icare.com.ph`。

不要给 runner 写 storage key / connection string。这次交互登录只给人手工验证 CLI；GitHub Actions 上传仍走 OIDC（`azure/login` + `--auth-mode login`）。

## Why This Works

`az login` 默认调用 Python `webbrowser.open()`。macOS 上实现是 `MacOSXOSAScript`：对默认浏览器执行 `open location "url"`，再按 `_tryorder`（`MacOSX`, `chrome`, `firefox`, `safari`）逐个 `tell application`。

2026-09-18 核验：

- 主机 `Mac-mini.local`，SSH 来自 `192.168.2.109` / Tailscale `100.92.181.15`
- `/dev/console` 属主是 `root`（登录窗口或非 konghai 图形用户），`who` 里没有 `konghai console`
- `/opt/homebrew/bin/az` 2.90.0 可用
- `/Applications` 有 Chrome / Safari / Edge / ego lite，**没有** Firefox → 对应 `-1728`
- 没有图形会话时 `osascript` 启动 GUI 应用失败 → 对应 `-10810`

设备代码流不依赖本机弹出浏览器，只要求终端能打印 URL 和短码。

## Prevention

- SSH / 无图形会话：永远用 `az login --use-device-code`
- 要在 mac-mini 本机弹出浏览器：先用 `konghai` 图形登录这台机器，再在本机 Terminal 跑默认 `az login`
- 约定见 `docs/runbooks/mac-mini-runner-start-stop.md` 的 azure-cli 节
