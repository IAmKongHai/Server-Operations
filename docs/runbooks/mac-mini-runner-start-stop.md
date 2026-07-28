# mac-mini GitHub Actions runner：启停与定时

> 最后更新：2026-07-28  
> 4 个 org runner：`mac-mini-sonar-1` … `4`  
> 目录：`~/actions-runner/mac-mini-sonar-{1..4}`  
> 固定恢复脚本：`~/bin/mac-mini-runner-resume.sh`  
> 日志：`~/Library/Logs/mac-mini-runner-resume.log`  
> 池与 label 定义见 [ci-runner-pools.md](./ci-runner-pools.md)

## 红线：不要用 `at` 做定时恢复

macOS **默认禁用** `com.apple.atrun`（plist 里 `Disabled=true`）。  
`at 16:01` 能入队，但到点**不会执行**；`atq` 里 job 会一直挂着。

**用 crontab 或 launchd**，不要用 `at` / `batch`。

详细取证：  
[docs/solutions/mac-mini/workflow-issues/macos-at-disabled-do-not-schedule-runner-resume-with-at-2026-07-28.md](../solutions/mac-mini/workflow-issues/macos-at-disabled-do-not-schedule-runner-resume-with-at-2026-07-28.md)

## 立即恢复

```bash
ssh mac-mini '~/bin/mac-mini-runner-resume.sh'
```

或：

```bash
for n in 1 2 3 4; do
  (cd ~/actions-runner/mac-mini-sonar-$n && ./svc.sh start)
done
```

**注意**：必须 `cd` 到 runner 根目录再调 `./svc.sh`。绝对路径调用会报：

`Failed: Must run from runner root or install is corrupt`

## 停止

```bash
for n in 1 2 3 4; do
  (cd ~/actions-runner/mac-mini-sonar-$n && ./svc.sh stop)
done
```

## 校验

```bash
# 本机
launchctl list | grep actions.runner
ps aux | grep Runner.Listener | grep -v grep

# GitHub
gh api orgs/cypressoai/actions/runners \
  --jq '.runners[] | select(.name|startswith("mac-mini-sonar")) | {name,status,busy}'
```

期望 `status` = `online`。

## 定时（推荐 cron）

```cron
# konghai crontab 示例：每天 16:00 拉起
0 16 * * * /Users/konghai/bin/mac-mini-runner-resume.sh
```

不要把恢复脚本只放在 `/tmp`（重启会丢）。

## 相关

- [ci-runner-pools.md](./ci-runner-pools.md)
- [operations/mac-mini.md](../operations/mac-mini.md)
