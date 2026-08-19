---
title: macOS GitHub Actions runner 要用 LaunchDaemon，不能靠 svc.sh 的 LaunchAgent
date: 2026-08-19
category: docs/solutions/lemon-imac/workflow-issues
server: lemon-imac
module: lemon-imac / GitHub Actions self-hosted runner
problem_type: workflow_issue
component: tooling
severity: high
applies_when:
  - "macOS self-hosted runner 在图形用户注销或别人占用控制台后变成 offline"
  - "官方 ./svc.sh install 装完的服务只在登录用户下活着"
  - "要把 lemon-imac / umacbook-pro 做成和 mac-mini 一样注销后仍接 job"
tags:
  - lemon-imac
  - github-actions
  - self-hosted-runner
  - launchd
  - launchdaemon
  - launchagent
  - svc-sh
  - ci
---

# macOS GitHub Actions runner 要用 LaunchDaemon，不能靠 svc.sh 的 LaunchAgent

## Context

`lemon-imac` 上 `for-konghai` 跑 org runner `lemon-imac-1/2`。控制台长期是家人账号 `zhangli`，`for-konghai` 往往只有 SSH、没有 Aqua 会话。官方 `./svc.sh install` 只往 `~/Library/LaunchAgents` 写 plist，绑定用户图形登录。结果是：没人登 `for-konghai` 桌面，两个 slot 就停。

2026-08-09 之后 GitHub 上一直 **offline**，直到 2026-08-19 改成 LaunchDaemon。mac-mini 已在 2026-08-15 用同一做法验证过：全员注销后，launchd 系统域里的 `actions.runner.cypressoai.mac-mini-sonar-N` 仍 online。

## Guidance

1. **不要用 `./svc.sh install` / `start` 当「注册为服务」。**  
   `svc.sh` 明确拒绝 root，且路径写死 `~/Library/LaunchAgents`。装完再登 GUI，会和 Daemon 双开。
2. **写成 `/Library/LaunchDaemons`，`UserName` 指向 runner 账号。**  
   必要键：`KeepAlive`、`SessionCreate`、`HOME`、`PATH`，以及本机 `.env` 里的 `GOCACHE` / `GOMODCACHE` / `PNPM_STORE_PATH`。不要设 `ProcessType=Interactive`。
3. **旧 Agent plist 挪走，不要留在 `~/Library/LaunchAgents`。**  
   lemon-imac 现停在 `~/Library/LaunchAgents.disabled-20260819/`。
4. **维护任务一并改 Daemon。**  
   这台机 crontab 被 TCC 拒绝。日/周清理若仍是 LaunchAgent，`for-konghai` 未登录时 03:25 不会跑，盘会再涨（CYP-1547）。
5. **启停用 `launchctl` 打系统域 label，不要再 `svc.sh`。**

```bash
sudo launchctl kickstart -k system/actions.runner.cypressoai.lemon-imac-1
sudo launchctl kickstart -k system/actions.runner.cypressoai.lemon-imac-2
```

安装脚本：`~/gha/scripts/install-lemon-imac-runner-daemons.sh`（仓库 `scripts/install-lemon-imac-runner-daemons.sh`）。

## Why This Matters

LaunchAgent 活在用户域。别人占用控制台、自己只 SSH、或注销桌面，Agent 都不会保活。LaunchDaemon 挂在 `system` 域，磁盘解锁后不依赖谁坐在登录窗。lemon-imac 验证时控制台仍是 `zhangli`、`for-konghai` 无 Aqua，两个 Listener 已是 `Listening for Jobs`，GitHub `online`。

FileVault 冷启动仍要人在机前解锁，Daemon 绕不开这一步。

## When to Apply

- 任何一台「当 CI 机用的 Mac」，目标是注销 / 换用户后 runner 仍在
- 看到 `svc.sh status` = Stopped，同时 `launchctl print gui/$UID` 报 Domain 不支持
- 给 `umacbook-pro` 做同样改造时（它现在仍是 LaunchAgent）

## Examples

改之前（LaunchAgent，`ProcessType=Interactive`，无 `KeepAlive`）：

```xml
<key>Label</key>
<string>actions.runner.cypressoai.lemon-imac-1</string>
<key>UserName</key>
<string>for-konghai</string>
<key>ProcessType</key>
<string>Interactive</string>
```

改之后（`/Library/LaunchDaemons`，`system/` 域）：

```xml
<key>Label</key>
<string>actions.runner.cypressoai.lemon-imac-1</string>
<key>UserName</key>
<string>for-konghai</string>
<key>GroupName</key>
<string>staff</string>
<key>KeepAlive</key>
<true/>
<key>SessionCreate</key>
<true/>
<key>EnvironmentVariables</key>
<dict>
  <key>HOME</key>
  <string>/Users/for-konghai</string>
  <!-- PATH / GOCACHE / GOMODCACHE / PNPM_STORE_PATH -->
</dict>
```

## Related

- 启停：[docs/runbooks/lemon-imac-runner-start-stop.md](../../../runbooks/lemon-imac-runner-start-stop.md)
- 池：[docs/runbooks/ci-runner-pools.md](../../../runbooks/ci-runner-pools.md)
- 时间线：[docs/operations/lemon-imac.md](../../../operations/lemon-imac.md)
- mac-mini 同做法：[docs/runbooks/mac-mini-runner-start-stop.md](../../../runbooks/mac-mini-runner-start-stop.md)
