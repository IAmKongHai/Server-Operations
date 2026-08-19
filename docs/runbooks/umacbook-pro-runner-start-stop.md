# umacbook-pro GitHub Actions runner：启停

> 最后更新：2026-08-19  
> org runner：`umacbook-pro-1` / `umacbook-pro-2`  
> 目录：`~/actions-runner/umacbook-pro-{1,2}`（workFolder `~/gha/u{1,2}`）  
> 2026-08-19 起改为 **LaunchDaemon**（`system/actions.runner.cypressoai.umacbook-pro-N`），注销图形用户后仍应在线。  
> 旧 LaunchAgent plist 停在 `~/Library/LaunchAgents.disabled-YYYYMMDD/`。  
> 维护任务同日改为 LaunchDaemon：`system/com.cypressoai.gha-runner-maintenance{,-weekly}`（原 crontab 已删，避免双跑）。  
> 池与 label 定义见 [ci-runner-pools.md](./ci-runner-pools.md)

**不要再运行 `./svc.sh install` / `./svc.sh start`。** 那会把 LaunchAgent 装回 `~/Library/LaunchAgents`，登录后和 Daemon 双开。

## 立即恢复

```bash
ssh umacbook-pro 'sudo /Users/for-konghai/gha/scripts/umacbook-pro-runner-resume.sh'
```

或：

```bash
sudo launchctl kickstart -k system/actions.runner.cypressoai.umacbook-pro-1
sudo launchctl kickstart -k system/actions.runner.cypressoai.umacbook-pro-2
```

## 停止

先确认没有 `Runner.Worker`。

```bash
sudo launchctl bootout system/actions.runner.cypressoai.umacbook-pro-1
sudo launchctl bootout system/actions.runner.cypressoai.umacbook-pro-2
```

## 校验

```bash
sudo launchctl print system | grep actions.runner.cypressoai.umacbook-pro
ps aux | grep Runner.Listener | grep -v grep

gh api orgs/cypressoai/actions/runners \
  --jq '.runners[] | select(.name|startswith("umacbook-pro")) | {name,status,busy}'
```

期望 `status` = `online`。注销图形用户后也应如此。

## 首次安装 / 重装

```bash
sudo /Users/for-konghai/gha/scripts/install-umacbook-pro-runner-daemons.sh
```

仓库副本：`scripts/install-umacbook-pro-runner-daemons.sh`。

## 相关

- [ci-runner-pools.md](./ci-runner-pools.md)
- [operations/umacbook-pro.md](../operations/umacbook-pro.md)
- [lemon-imac-runner-start-stop.md](./lemon-imac-runner-start-stop.md)
