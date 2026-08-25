# mac-mini GitHub Actions runner：启停与定时

> 最后更新：2026-08-25  
> org runner（cypressoai）：`mac-mini-sonar-1` … `4`（质量门）+ `mac-mini-mobile-1`（preview 本机构建）  
> org runner（konghai-friends-lab）：`konghai-friends-lab-1`（label `konghai-friends-lab`，workFolder `~/gha/kfl1`）  
> 目录：`~/actions-runner/mac-mini-sonar-{1..4}`、`~/actions-runner/mac-mini-mobile-1`（workFolder `~/gha/m1`）、`~/actions-runner/konghai-friends-lab-1`  
> 2026-08-15 起 sonar 槽改为 **LaunchDaemon**（`system/actions.runner.cypressoai.mac-mini-sonar-N`），注销图形用户后仍应在线。  
> `mac-mini-mobile-1` 同样走 LaunchDaemon：`system/actions.runner.cypressoai.mac-mini-mobile-1`。  
> 旧 LaunchAgent plist 停在 `~/Library/LaunchAgents.disabled-20260815/`。  
> 固定恢复脚本：`~/bin/mac-mini-runner-resume.sh`（kickstart 1..4 + mobile-1）  
> 日志：`~/Library/Logs/mac-mini-runner-resume.log`  
> 池与 label 定义见 [ci-runner-pools.md](./ci-runner-pools.md)
>
> 2026-08-19 曾 `launchctl disable` 停掉 `mac-mini-sonar-3/4` 给 Multica 留并发；**2026-08-25 已 enable + bootstrap 恢复**，四 slot 重新 online。当时条目见 [operations/mac-mini.md](../operations/mac-mini.md)。

**不要再运行 `./svc.sh install` / `./svc.sh start`。** 那会把 LaunchAgent 装回 `~/Library/LaunchAgents`，登录后和 Daemon 双开。

## 红线：不要用 `at` 做定时恢复

macOS **默认禁用** `com.apple.atrun`（plist 里 `Disabled=true`）。  
`at 16:01` 能入队，但到点**不会执行**；`atq` 里 job 会一直挂着。

**用 crontab 或 launchd**，不要用 `at` / `batch`。

详细取证：  
[docs/solutions/mac-mini/workflow-issues/macos-at-disabled-do-not-schedule-runner-resume-with-at-2026-07-28.md](../solutions/mac-mini/workflow-issues/macos-at-disabled-do-not-schedule-runner-resume-with-at-2026-07-28.md)

## 立即恢复

```bash
ssh mac-mini 'sudo ~/bin/mac-mini-runner-resume.sh'
```

或：

```bash
for n in 1 2 3 4; do
  sudo /bin/launchctl kickstart -k system/actions.runner.cypressoai.mac-mini-sonar-$n
done
sudo /bin/launchctl kickstart -k system/actions.runner.cypressoai.mac-mini-mobile-1
```

KeepAlive 已开，崩溃后 launchd 会自己拉。resume 主要给「人为 bootout 之后」用。

## 停止

```bash
for n in 1 2 3 4; do
  sudo launchctl bootout system/actions.runner.cypressoai.mac-mini-sonar-$n
done
sudo launchctl bootout system/actions.runner.cypressoai.mac-mini-mobile-1
```

## konghai-friends-lab `konghai-friends-lab-1`

组织级 runner，Default group `visibility=all`，org 内私有仓都能用。**不是** `cypressoai` 池成员。workflow 写：

```yaml
runs-on: [self-hosted, konghai-friends-lab]
```

当前（2026-08-24）以 `nohup ./runsvc.sh` 运行，重启后会掉。本机 sudo 一次后改成 LaunchDaemon：

```bash
sudo /Users/konghai/gha/scripts/install-konghai-friends-lab-runner-daemon.sh
```

不要 `./svc.sh install`。装上 Daemon 之后：

```bash
sudo /bin/launchctl kickstart -k system/actions.runner.konghai-friends-lab.konghai-friends-lab-1
```

```bash
gh api orgs/konghai-friends-lab/actions/runners \
  --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
```

## 校验

```bash
# 本机
launchctl print system | grep actions.runner
ps aux | grep Runner.Listener | grep -v grep

# GitHub
gh api orgs/cypressoai/actions/runners \
  --jq '.runners[] | select(.name|startswith("mac-mini")) | {name,status,busy}'
```

期望 `status` = `online`。全员注销后也应如此。

## 定时（推荐 cron）

```cron
# konghai crontab 示例：每天 16:00 拉起
0 16 * * * /Users/konghai/bin/mac-mini-runner-resume.sh
```

不要把恢复脚本只放在 `/tmp`（重启会丢）。

## 相关

- [ci-runner-pools.md](./ci-runner-pools.md)
- [operations/mac-mini.md](../operations/mac-mini.md)
