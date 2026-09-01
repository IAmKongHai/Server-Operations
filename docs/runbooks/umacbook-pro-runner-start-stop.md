# umacbook-pro GitHub Actions runner：启停

> 最后更新：2026-09-01  
> org runner：`umacbook-pro-1` / `umacbook-pro-2`  
> 目录：`~/actions-runner/umacbook-pro-{1,2}`（workFolder `~/gha/u{1,2}`）  
> 2026-08-19 起改为 **LaunchDaemon**（`system/actions.runner.cypressoai.umacbook-pro-N`），注销图形用户后仍应在线。  
> 旧 LaunchAgent plist 停在 `~/Library/LaunchAgents.disabled-YYYYMMDD/`。  
> 维护任务同日改为 LaunchDaemon：`system/com.cypressoai.gha-runner-maintenance{,-weekly}`（原 crontab 已删，避免双跑）。  
> 池与 label 定义见 [ci-runner-pools.md](./ci-runner-pools.md)  
> 这台是侄女的个人本：带到学校时用下面「长期停用」；回校后再 resume。**不要动 Tailscale。**

**不要再运行 `./svc.sh install` / `./svc.sh start`。** 那会把 LaunchAgent 装回 `~/Library/LaunchAgents`，登录后和 Daemon 双开。

## 立即恢复

长期停用之后必须走 resume 脚本（它会 `enable` + `bootstrap` + `kickstart`，并重新打开维护定时）。只 `kickstart` 对已经 disable / 未加载的 plist 不够。

```bash
ssh umacbook-pro 'sudo /Users/for-konghai/gha/scripts/umacbook-pro-runner-resume.sh'
```

若只是刚才 `bootout`、并未 `disable`：

```bash
sudo launchctl kickstart -k system/actions.runner.cypressoai.umacbook-pro-1
sudo launchctl kickstart -k system/actions.runner.cypressoai.umacbook-pro-2
```

## 停止

先确认没有 `Runner.Worker`。只 `bootout` 的话，重启整机还会被 `RunAtLoad` + `KeepAlive` 拉起来。

```bash
sudo launchctl bootout system/actions.runner.cypressoai.umacbook-pro-1
sudo launchctl bootout system/actions.runner.cypressoai.umacbook-pro-2
```

## 长期停用（带到学校）

`disable` + `bootout` runner 与维护任务，**不**注销 GitHub runner，**不**动 `system/homebrew.mxcl.tailscale`。有 `Runner.Worker` 时先等它结束再 bootout（不要对还在跑的 slot 直接 bootout，launchd 的 ExitTimeOut 会 SIGKILL）。

`launchctl disable` **不会**关掉已经加载的 job 的 KeepAlive。只 SIGTERM Listener 会被 launchd 立刻拉起来，pause 脚本会卡死。正确顺序是：disable → 等 Worker 结束 → bootout。

这台 `sudo` 没有 `/bin/launchctl` 免密（只有 `pmset`），需要一次密码。

```bash
ssh umacbook-pro 'sudo /Users/for-konghai/gha/scripts/umacbook-pro-runner-pause.sh --clean-cache'
```

只停 daemon、稍后自己清盘：

```bash
ssh umacbook-pro 'sudo /Users/for-konghai/gha/scripts/umacbook-pro-runner-pause.sh'
ssh umacbook-pro '/Users/for-konghai/gha/scripts/umacbook-pro-runner-pause.sh --clean-cache-only'
```

清掉的是 GOCACHE、workFolder `~/gha/u{1,2}`、GOMODCACHE、pnpm store、`_diag`、旧版 `bin.2.335.1`。runner 程序、`.runner` / `.credentials` / `.env` 都留着。回来后第一次 job 会重新拉工具缓存。

仓库副本：`scripts/umacbook-pro-runner-pause.sh`。

## 校验

```bash
sudo launchctl print system | grep actions.runner.cypressoai.umacbook-pro
ps aux | grep Runner.Listener | grep -v grep

gh api orgs/cypressoai/actions/runners \
  --jq '.runners[] | select(.name|startswith("umacbook-pro")) | {name,status,busy}'
```

恢复后期望 `status` = `online`，注销图形用户后也应如此。长期停用后期望 GitHub `offline`、本机没有 `Runner.Listener`，且 `homebrew.mxcl.tailscale` 仍 enabled。

## 首次安装 / 重装

```bash
sudo /Users/for-konghai/gha/scripts/install-umacbook-pro-runner-daemons.sh
```

仓库副本：`scripts/install-umacbook-pro-runner-daemons.sh`。

## 相关

- [ci-runner-pools.md](./ci-runner-pools.md)
- [operations/umacbook-pro.md](../operations/umacbook-pro.md)
- [lemon-imac-runner-start-stop.md](./lemon-imac-runner-start-stop.md)
