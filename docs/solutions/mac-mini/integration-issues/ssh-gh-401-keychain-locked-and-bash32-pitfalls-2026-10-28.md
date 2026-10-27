---
title: "SSH 到 mac-mini 跑 gh 报 401（钥匙串锁定），以及远端脚本的 bash 3.2 陷阱"
date: 2026-10-28
category: docs/solutions/mac-mini/integration-issues
server: mac-mini
module: mac-mini / gh CLI / bash 脚本
problem_type: integration_issue
component: tooling
symptoms:
  - "ssh mac-mini 'gh api ...' 返回 Requires authentication (HTTP 401)"
  - "gh auth status：Failed to log in to github.com account IAmKongHai (default) / The token in default is invalid"
  - "sudo 跑 /usr/local/sbin/*.sh 报 X�: unbound variable 后 exit 1"
  - "set -u 脚本报 a[@]: unbound variable"
root_cause: config_error
resolution_type: workflow_improvement
severity: low
tags:
  - mac-mini
  - lemon-imac
  - gh
  - keychain
  - bash
  - ssh
---

# SSH 到 mac-mini 跑 gh 报 401（钥匙串锁定），以及远端脚本的 bash 3.2 陷阱

## 问题一：`ssh mac-mini 'gh api ...'` 返回 401

### 现象

`konghai` 在 mac-mini 上登录了两个 gh 账号：

- `IAmKongHai`（当前激活）：token 存在登录钥匙串（keyring）
- `k-cypresso`：token 存在 `~/.config/gh/hosts.yml`，scope `gist, read:org, repo`

SSH 进去执行 `gh` 时，`gh auth status` 说 `IAmKongHai` 的 token 无效，`gh api` 返回 401。

### 根因

不是 token 失效，是 **SSH 会话里登录钥匙串是锁着的**：

```bash
security find-generic-password -s "gh:github.com" -a "IAmKongHai"      # rc=0，条目存在
security find-generic-password -s "gh:github.com" -a "IAmKongHai" -w   # rc=36，读不出密码
```

`36` 即 `errSecInteractionNotAllowed`。gh 拿不到 token，只能不带认证请求，于是 401。同类问题见 `multica-daemon-https-repo-cache-403-2026-08-19.md`（keychain `-25308`）。

### 为什么不建议在 mac-mini 上"修好"它

就算换账号，mac-mini 上也没有哪个账号有查 runner 的权限（2026-10-28 实测）：

| 在哪跑 | 账号 | `repos/IAmKongHai/AcquiLangAI/actions/runners` | `orgs/cypressoai/actions/runners` |
|---|---|---|---|
| mac-mini `konghai` | `k-cypresso` | 404 | 403（缺 `admin:org`） |
| mac-mini `hon` | `hon003` | 404 | 403 |
| 本机 | `IAmKongHai` | ✅ 6 个 | 403 |
| 本机 | `k-cypresso`（激活） | — | ✅ 15 个 |

团队资产 10-22/23 起已归 `hon`，`konghai` 只做私人用途，也没有需要 gh 的定时任务。

### 做法

- **查 GitHub API（runner、workflow、secret）一律在本机跑**，不要 `ssh mac-mini 'gh ...'`。
- 查 repo 级 runner 用 `IAmKongHai`，不用切换激活账号：

  ```bash
  GH_TOKEN="$(gh auth token -u IAmKongHai)" gh api repos/IAmKongHai/AcquiLangAI/actions/runners
  ```

- 查 org 级 runner 用本机激活的 `k-cypresso` 即可。
- 确实要在远端用钥匙串里的 token，只能先 `security unlock-keychain`（要交互输入登录密码），不适合自动化。

## 问题二：远端 macOS 上脚本跑在 bash 3.2

### 背景

mac-mini、lemon-imac 上 `sudo`、`launchd`、`#!/bin/bash` 拉起的都是系统自带的 `/bin/bash` 3.2.57。本机 Claude Code 现在用的是 Homebrew bash 5，脚本在本机能跑，不代表在远端能跑。

### 两个实际踩到的坑（都在 `/bin/bash` 3.2 上复现过）

1. **`$VAR` 后面紧跟中文**：UTF-8 locale 下 3.2 会把多字节字符当成变量名的一部分，配合 `set -u` 直接退出。

   ```bash
   LC_ALL=en_US.UTF-8 /bin/bash -c 'set -u; X=1; echo "$X（"'   # X�: unbound variable
   ```

   写成 `${X}（`。

2. **`set -u` 下展开空数组**：bash 4.4 以前 `"${a[@]}"` 在数组为空时报 unbound variable。

   ```bash
   /bin/bash -c 'set -u; a=(); for x in "${a[@]}"; do :; done'   # a[@]: unbound variable
   ```

   可能为空的数组写成 `"${a[@]+"${a[@]}"}"`。`${#a[@]}` 和空的 `"$@"` 在 3.2 下没问题。

另外，3.2 没有 `declare -A`、`mapfile`、`${v,,}`、`|&`、`&>>`、`${a[-1]}`、`wait -n`。

### 检查命令

```bash
# 1. $VAR 后紧跟非 ASCII
LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z_0-9]*[^ -~]' scripts/*.sh
# 2. bash 4+ 专有语法
grep -nE 'declare -[a-zA-Z]*[An]|local -[a-zA-Z]*[An]|mapfile|readarray|\$\{[A-Za-z_][A-Za-z_0-9]*(,,|\^\^|@[QEPAa])|\|&|&>>|\[-1\]|wait -n' scripts/*.sh
# 3. 最可靠：在目标机器上用 /bin/bash -n 做语法检查，或直接用 /bin/bash 跑 --help / --status
```

### 2026-10-28 扫描结果

- 仓库 `scripts/`：两处 `$VAR` 紧跟中文已改（提交 `5bb368e`），没有 bash 4+ 语法；`set -u` 下可能为空的数组都已加 `+` 保护。
- mac-mini `/usr/local/sbin/*.sh`、`/Users/hon/gha/scripts/*.sh`：干净。
- lemon-imac：只有 `~/gha/scripts/migrate-lemon-imac-ci-to-nofsevents-volume.sh` 还是旧副本，问题在最后一行"完成"日志。该迁移 10-21 已做完，不影响现网；以后要重跑，先用仓库版本覆盖。
