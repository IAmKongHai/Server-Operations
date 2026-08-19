---
title: "Multica daemon 预克隆 iCare 私有仓 HTTPS 403 / keychain -25308"
date: 2026-08-19
category: docs/solutions/mac-mini/integration-issues
server: mac-mini
module: mac-mini / Multica daemon / git
problem_type: integration_issue
component: tooling
symptoms:
  - "daemon.log 里 repo cache: clone failed，GitHub 403 Write access to repository not granted"
  - "同时出现 failed to get: -25308"
  - "runtime 显示 online，但担心改这些仓的任务会失败"
root_cause: config_error
resolution_type: config_change
severity: medium
tags:
  - mac-mini
  - multica
  - git
  - github
  - keychain
---

# Multica daemon 预克隆 iCare 私有仓 HTTPS 403 / keychain -25308

## Problem

`multica --profile konghai` 的 daemon 启动时会把 workspace 挂着的 git 仓预克隆到 `~/multica_workspaces_konghai/.repos/`。iCare 一组 HTTPS URL 克隆失败，日志同时出现钥匙串 `-25308` 和 GitHub `403 Write access to repository not granted`。

这不表示 runtime 掉线，只表示 **HTTPS 这条取代码路径失败**。

## Symptoms

- `repo cache: clone failed`，URL 形如 `https://github.com/cypressoai/iCare-backend`
- `failed to get: -25308`（`errSecInteractionNotAllowed`：后台进程打不开钥匙串弹窗）
- GitHub：`remote: Write access to repository not granted` / HTTP 403
- 同一仓的 `git@github.com:...` 随后能克隆成功

2026-08-19 实测：`IAmKongHai` 对 `cypressoai/iCare*` 有 push；SSH `git ls-remote` 成功；HTTPS 在交互 SSH 里同样 403。所以不是「用户没权限」，是 **HTTPS 用错了凭证**。

## What Didn't Work

- 把 403 理解成 GitHub 组织没给写权限：`gh api` 显示 `iCare` admin、`iCare-backend` push
- 以为只有 daemon 会失败：本机 `GIT_TERMINAL_PROMPT=0 git ls-remote https://...` 一样 403
- 停 daemon / 重登 Multica：不动 git 凭证，HTTPS 不会好

## Solution

先看缓存目录里是不是已经有包。当前 iCare 主仓已经通过 **SSH 重试** 落到磁盘：

| 仓 | 缓存 | 说明 |
| --- | --- | --- |
| `cypressoai/iCare` | 有（约 844M） | HTTPS 失败后 SSH 成功 |
| `cypressoai/iCare-backend` | 有（约 179M） | 同上 |
| `cypressoai/iCare-frontend-mas` | 有（约 37M） | 同上 |
| `konghai-friends-lab/richer` | 有 | SSH / HTTPS fetch 可用 |
| `cypresso-ai/icare-sit` | **没有** | 另一个 org；`IAmKongHai` 404，SSH 也 `Repository not found` |

对已缓存的仓，agent 任务会从 bare cache 建 worktree，**不必再修 HTTPS** 也能改代码。

若希望 HTTPS 也通（或避免以后再挂 HTTPS URL）：

1. **优先**：Multica workspace 里把仓库改成 SSH URL（`git@github.com:cypressoai/iCare-backend.git`）。`gh` 的 git protocol 已经是 ssh，本机 `Host github.com` 用 `~/.ssh/id_ed25519`，`ssh -T git@github.com` 是 `Hi IAmKongHai!`。
2. **HTTPS**：`~/.git-credentials` 里 github.com 有两条，第一条用户是 `x-access-token`（安装令牌 / 旧 token），Git 会先用它，GitHub 就回那句误导性的 Write access 403。系统还有 Xcode 的 `osxkeychain` helper，后台拿不到钥匙串就会 `-25308`。在 **GUI 终端** 执行 `gh auth setup-git`，让 HTTPS 走 `gh`（当前 token scope 含 `repo`），不要让 daemon 去弹钥匙串。不要在文档或脚本里写 token。
3. **`icare-sit`**：要么把 `IAmKongHai` 加进 `cypresso-ai/icare-sit`，要么从 Multica workspace 卸掉这个 repo。没权限怎么换协议都拉不下来。

## Why This Works

daemon 只是对本机 `git clone --bare` 做一层缓存。认证完全走机器上的 git / SSH / credential helper。runtime online 只说明任务通道通，不保证缓存已热。SSH 走的是对的 GitHub 用户；HTTPS 走的是 store 里过期的 `x-access-token` 和打不开的钥匙串。

## Prevention

- 给 Multica 挂私有仓时用 `git@github.com:...`
- 后台 daemon 不要依赖 `osxkeychain`（会 `-25308`）
- `git credential` 里不要留失效的 `x-access-token`
- 新仓先 `ssh -T git@github.com` 和 `gh api repos/<org>/<repo>` 确认当前 GitHub 用户真能看见

## Related Issues

- `docs/solutions/mac-mini/integration-issues/multica-setup-ssh-login-localhost-3000-2026-08-19.md`
- `docs/operations/mac-mini.md` — 2026-08-19 13:13 / 14:58 记录
