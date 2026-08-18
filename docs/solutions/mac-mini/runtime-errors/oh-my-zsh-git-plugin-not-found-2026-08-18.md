---
title: "SSH 登录 mac-mini 报 oh-my-zsh plugin git not found"
date: 2026-08-18
category: docs/solutions/mac-mini/runtime-errors
server: mac-mini
module: mac-mini / zsh / oh-my-zsh
problem_type: runtime_error
component: tooling
symptoms:
  - "ssh mac-mini 先刷 Powerlevel10k instant prompt 警告：console output during zsh initialization"
  - "[oh-my-zsh] plugin 'git' not found"
  - "git 插件提供的 alias（如 gst）不可用"
root_cause: incomplete_setup
resolution_type: environment_setup
severity: low
tags:
  - mac-mini
  - zsh
  - oh-my-zsh
  - powerlevel10k
  - instant-prompt
  - git-plugin
---

# SSH 登录 mac-mini 报 oh-my-zsh plugin git not found

## Problem

`ssh mac-mini` 每次都会先弹出 Powerlevel10k instant prompt 的长警告，真正的初始化输出是 `[oh-my-zsh] plugin 'git' not found`。登录能进，但 `git` 插件 alias 丢了。

## Symptoms

- 交互式登录（本机 Terminal / `ssh mac-mini`）刷 p10k instant prompt 提示，并写 *console output produced during zsh initialization follows*
- 紧接着一行 `[oh-my-zsh] plugin 'git' not found`
- `alias gst` 不存在（oh-my-zsh 的 git 插件没加载）

非交互 `ssh mac-mini 'cmd'` **不会**复现：`~/.zshrc` 顶部有 `[[ ! -o interactive ]] && return` 守卫（见 2026-05-13 gitstatus / `setopt monitor` 那次）。

## What Didn't Work

- 只看 `~/.zshrc` 的 `plugins=(git ...)`：声明是对的，问题不在配置写错插件名
- 只关 instant prompt（`POWERLEVEL9K_INSTANT_PROMPT=quiet`）：能压掉警告框，但 `git` 插件依然加载失败
- 把 `git` 从 `plugins` 里删掉：警告会消失，同时失去 alias，治标不治本

## Solution

`~/.oh-my-zsh` 仍是完整 git 仓库（`origin` = `https://github.com/ohmyzsh/ohmyzsh.git`），只是工作树里的 `~/.oh-my-zsh/plugins` 整目录没了（886 个已跟踪文件显示 `D`）。`~/.oh-my-zsh/custom` 完好：

- `~/.oh-my-zsh/custom/plugins/{zsh-autosuggestions,zsh-syntax-highlighting}`
- `~/.oh-my-zsh/custom/themes/powerlevel10k`

恢复：

```bash
cd ~/.oh-my-zsh
git status --porcelain | wc -l   # 当时 886，且全部是 plugins/ 下的 D
git restore plugins
test -f plugins/git/git.plugin.zsh
```

不要重装整个 oh-my-zsh，也不要改 `~/.zshrc` / 关 instant prompt。

验证（必须是交互式，注意变量不要被本机 shell 提前展开）：

```bash
ssh -tt mac-mini 'zsh -ic '"'"'echo "plugins=$plugins"; alias gst'"'"''
```

期望：`plugins=git zsh-autosuggestions zsh-syntax-highlighting`，`gst='git status'`，且不再出现 `plugin 'git' not found` 或 p10k instant prompt 警告。

操作记录见 [`docs/operations/mac-mini.md`](../../../operations/mac-mini.md) 2026-08-18 13:25 条目。

## Why This Works

oh-my-zsh 按 `$ZSH/plugins/<name>/<name>.plugin.zsh` 找标准插件。目录被删后找不到文件就 `echo` 一行错误；这行输出发生在 p10k instant prompt preamble 之后，于是 p10k 认为「初始化阶段有 console I/O」再叠一层长警告。

`~/.oh-my-zsh/plugins` 只是工作树缺失，HEAD 里还在，在该仓库里 `git restore plugins` 即可还原。p10k 本身、主题、自定义插件都没坏。

未定位是谁删的。`~/.oh-my-zsh` 目录 mtime 为 2026-08-15 00:35，和 OMZ 自动更新的 `git pull --quiet --rebase origin master` 接近，但删除没有进 commit。

## Prevention

- 登录再报 `plugin 'X' not found` 时，先 `ls "$ZSH/plugins/X"` 和 `git -C "$ZSH" status --porcelain`，不要先改 `plugins=()` 或关 instant prompt
- 不要对 `~/.oh-my-zsh/plugins` 做磁盘清理 / 误 `rm -rf`
- 备份或迁移 oh-my-zsh 时保留 `~/.oh-my-zsh/plugins`；`~/.oh-my-zsh/custom` 完好不等于标准插件还在

## Related Issues

- [`docs/solutions/mac-mini/sonarqube-migrated-from-dev-cypresso-2026-05-13.md`](../sonarqube-migrated-from-dev-cypresso-2026-05-13.md) — 非交互 shell 跳过 oh-my-zsh / p10k / gitstatus 的 `~/.zshrc` 守卫
