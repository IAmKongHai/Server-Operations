# lemon-imac GitHub Actions runner：启停

> 最后更新：2026-10-10
> org runner：`lemon-imac-1` / `lemon-imac-2`  
> 目录：`~/actions-runner/lemon-imac-{1,2}`（workFolder `~/gha/li{1,2}`）  
> 2026-08-19 起改为 **LaunchDaemon**（`system/actions.runner.cypressoai.lemon-imac-N`），注销图形用户后仍应在线。  
> 旧 LaunchAgent plist 停在 `~/Library/LaunchAgents.disabled-YYYYMMDD/`。  
> 维护任务同日改为 LaunchDaemon：`system/com.cypressoai.gha-runner-maintenance{,-weekly}`。  
> 池与 label 定义见 [ci-runner-pools.md](./ci-runner-pools.md)

**不要再运行 `./svc.sh install` / `./svc.sh start`。** 那会把 LaunchAgent 装回 `~/Library/LaunchAgents`，登录后和 Daemon 双开。

## 立即恢复

```bash
ssh lemon-imac 'sudo /Users/for-konghai/gha/scripts/lemon-imac-runner-resume.sh'
```

或：

```bash
sudo launchctl kickstart -k system/actions.runner.cypressoai.lemon-imac-1
sudo launchctl kickstart -k system/actions.runner.cypressoai.lemon-imac-2
```

KeepAlive 已开，崩溃后 launchd 会自己拉。resume 主要给「人为 bootout 之后」用。

## 停止

```bash
sudo launchctl bootout system/actions.runner.cypressoai.lemon-imac-1
sudo launchctl bootout system/actions.runner.cypressoai.lemon-imac-2
```

停之前先确认没有 `Runner.Worker`。

## 校验

```bash
# 本机
sudo launchctl print system | grep actions.runner.cypressoai.lemon-imac
ps aux | grep Runner.Listener | grep -v grep

# GitHub
gh api orgs/cypressoai/actions/runners \
  --jq '.runners[] | select(.name|startswith("lemon-imac")) | {name,status,busy}'
```

期望 `status` = `online`。`zhangli` 独占控制台、`for-konghai` 未登录图形界面时也应如此。

## 首次安装 / 重装

```bash
sudo /Users/for-konghai/gha/scripts/install-lemon-imac-runner-daemons.sh
```

仓库副本：`scripts/install-lemon-imac-runner-daemons.sh`。

## 回滚到 LaunchAgent

```bash
sudo launchctl bootout system/actions.runner.cypressoai.lemon-imac-1
sudo launchctl bootout system/actions.runner.cypressoai.lemon-imac-2
sudo rm /Library/LaunchDaemons/actions.runner.cypressoai.lemon-imac-{1,2}.plist
# 把 disabled 目录里的 Agent plist 移回 ~/Library/LaunchAgents
# 然后不要在无 Aqua 会话时指望它们还活着
```

## AcquiLang 仓库级 runner

`lemon-imac-acquilang-ci-1` 不属于 cypressoai org 池。label 只有 `self-hosted`、`macOS`、`ARM64`、`acquilang-build`。目录是 `~/actions-runner/lemon-imac-acquilang-ci-1`，工作目录 `~/gha/alci1`。

2026-10-10 先用用户域 LaunchAgent 拉起。检查：

```bash
launchctl print user/502/actions.runner.IAmKongHai-AcquiLangAI.lemon-imac-acquilang-ci-1 | grep -E 'state =|pid ='
```

停止这个 Agent，不碰 org runner：

```bash
launchctl bootout user/502/actions.runner.IAmKongHai-AcquiLangAI.lemon-imac-acquilang-ci-1
```

改成重启后仍在线：

```bash
sudo /Users/for-konghai/gha/scripts/install-lemon-imac-acquilang-ci-runner-daemon.sh
```

仓库副本：`scripts/install-lemon-imac-acquilang-ci-runner-daemon.sh`。不要对这个目录运行 `./svc.sh install`。

## 相关

- [ci-runner-pools.md](./ci-runner-pools.md)
- [operations/lemon-imac.md](../operations/lemon-imac.md)
- [mac-mini-runner-start-stop.md](./mac-mini-runner-start-stop.md)（同一套 LaunchDaemon 做法）
