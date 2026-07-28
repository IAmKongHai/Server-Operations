---
title: "macOS 上不要用 at 定时恢复 GitHub Actions runner"
date: 2026-07-28
category: docs/solutions/mac-mini/workflow-issues
server: mac-mini
module: mac-mini / GitHub Actions self-hosted runner
problem_type: workflow_issue
component: tooling
severity: high
applies_when:
  - "需要停掉 mac-mini 上的 self-hosted runner，并在某个时刻自动恢复"
  - "用 at / atrun 安排一次性任务启动 runner 后没有执行"
  - "atq 里任务到点仍在队列，resume 脚本从未写出 resume start 日志"
  - "svc.sh start 报 Failed: Must run from runner root or install is corrupt"
tags:
  - mac-mini
  - github-actions
  - self-hosted-runner
  - at
  - atrun
  - cron
  - launchd
  - ci
---

# macOS 上不要用 at 定时恢复 GitHub Actions runner

## Context

mac-mini 上跑 org 级 self-hosted runner：`mac-mini-sonar-1` … `mac-mini-sonar-4`  
（目录 `~/actions-runner/mac-mini-sonar-{1..4}`，LaunchAgent `actions.runner.cypressoai.mac-mini-sonar-*`）。

2026-07-28 为腾出本机资源，手动 `svc.sh stop` 停掉 4 个 runner，并用 `at` 安排 **16:01** 执行 `/tmp/mac-mini-runner-resume.sh` 自动恢复。到点后 runner 仍全部 offline。

操作时间线见 [`docs/operations/mac-mini.md`](../../../operations/mac-mini.md) 当日条目。

## Root cause

### 1. macOS 默认禁用 `atrun`（主因）

`at` 只负责入队；真正到点执行依赖系统 daemon `com.apple.atrun`。

在本机：

```text
/System/Library/LaunchDaemons/com.apple.atrun.plist
  Disabled => true
  StartInterval => 30
```

`launchctl print system/com.apple.atrun` → **service 不存在（未加载）**。

表现：

| 检查 | 结果 |
|------|------|
| `atq` | job 仍在队列（过了 16:01 也不被消费） |
| resume 日志 | 只有创建时写的 `method=at`，没有 `=== resume start ===` |
| GitHub | 4 runner 全是 `offline` |

`at` 能 `at 16:01` 成功，**不等于**会执行。Linux 上常见、macOS 上默认不可用。

### 2. `svc.sh` 必须在 runner 根目录执行（次因 / 脚本坑）

绝对路径调用会失败：

```bash
# 错：从任意 cwd 调绝对路径
/Users/konghai/actions-runner/mac-mini-sonar-1/svc.sh start
# Failed: Must run from runner root or install is corrupt

# 对：先 cd 再调
cd /Users/konghai/actions-runner/mac-mini-sonar-1 && ./svc.sh start
```

早期 `/tmp` 版 resume 脚本用绝对路径调 `svc.sh`，即便 `at` 跑起来也会 8 次 Failed。

### 3. `/tmp` 脚本不适合当「恢复入口」

重启或清理后 `/tmp` 会丢。脚本应放固定路径（如 `~/bin/mac-mini-runner-resume.sh`），日志放 `~/Library/Logs/`。

## Guidance

### 禁止 / 避免

- **不要**用 `at` / `batch` 在 mac-mini 上做 runner 启停定时（除非已显式 `sudo launchctl load -w ...atrun.plist` 并验证 `atrun` 在跑——仍不推荐，可移植性差）。
- **不要**在脚本里用绝对路径直接调 `svc.sh`。
- **不要**把唯一恢复脚本只放在 `/tmp`。

### 推荐做法

#### 立即手动恢复

见 runbook：[`docs/runbooks/mac-mini-runner-start-stop.md`](../../../runbooks/mac-mini-runner-start-stop.md)

```bash
ssh mac-mini '~/bin/mac-mini-runner-resume.sh'
# 或
for n in 1 2 3 4; do
  (cd ~/actions-runner/mac-mini-sonar-$n && ./svc.sh start && ./svc.sh status)
done
```

校验：

```bash
# 本机
launchctl list | grep actions.runner
ps aux | grep Runner.Listener | grep -v grep

# GitHub（需 gh 已登录 org）
gh api orgs/cypressoai/actions/runners \
  --jq '.runners[] | select(.name|startswith("mac-mini-sonar")) | {name,status,busy}'
```

期望：`status` 均为 `online`。

#### 定时恢复：用 crontab（已有 cron 习惯）或 launchd

```cron
# 例：每天 16:00 拉起 runner（写在 konghai 的 crontab）
0 16 * * * /Users/konghai/bin/mac-mini-runner-resume.sh
```

或 LaunchAgent + `StartCalendarInterval`（更 macOS 原生，适合需要 GUI session 的服务）。

#### 标准 resume 脚本位置

- 脚本：`~/bin/mac-mini-runner-resume.sh`
- 日志：`~/Library/Logs/mac-mini-runner-resume.log`

脚本要点：对每个 `n` **`cd` 进目录** 再 `./svc.sh start`。

#### 若坚持启用 atrun（不推荐）

```bash
sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.atrun.plist
# 验证
launchctl print system/com.apple.atrun
# 再 at 一次后观察 atq 是否被消费、日志是否出现 resume start
```

SIP / 系统升级后可能回退，**不要**把 CI 恢复链路绑在 atrun 上。

## Incident timeline (2026-07-28)

| 时间 (CST) | 事件 |
|------------|------|
| ~13:01 | 手动 stop 4 runner；`at` 入队 16:01；写 `/tmp/mac-mini-runner-resume.sh` |
| 16:01 | **未执行**（atrun disabled） |
| 18:27 | 排查：进程无、LaunchAgent 未加载、GitHub offline、`atq` 仍有 job |
| 18:36 | `cd` + `./svc.sh start` 恢复；GitHub 4× online；安装 `~/bin/mac-mini-runner-resume.sh` |

## Related

- 启停速查：[`docs/runbooks/mac-mini-runner-start-stop.md`](../../../runbooks/mac-mini-runner-start-stop.md)
- Runner 池定义：[`docs/runbooks/ci-runner-pools.md`](../../../runbooks/ci-runner-pools.md)
- 主机时间线：[`docs/operations/mac-mini.md`](../../../operations/mac-mini.md)
- Labels：`mac-mini-sonar`, `macos`, `arm64`, `backend-ci`, `frontend-sonar-ci`, `frontend-tests-ci`, `frontend-quality-ci`
