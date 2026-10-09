# mac-mini GitHub Actions runner：启停与定时

> 最后更新：2026-10-10
> org runner（cypressoai）：`mac-mini-sonar-1` … `4`（质量门）+ `mac-mini-mobile-1`（preview 本机构建）  
> org runner（konghai-friends-lab）：`konghai-friends-lab-1`（label `konghai-friends-lab`，workFolder `~/gha/kfl1`）  
> 仓库级 runner（`IAmKongHai/AcquiLangAI`）：`mac-mini-acquilang-native-1`（label `acquilang-native-ci`，workFolder `~/gha/al1`）
> 日常 CI 仓库级 runner：`mac-mini-acquilang-ci-1` … `5`（label `acquilang-ci`，workFolder `~/gha/alc1` … `alc5`）
> 目录：`~/actions-runner/mac-mini-sonar-{1..4}`、`~/actions-runner/mac-mini-mobile-1`（workFolder `~/gha/m1`）、`~/actions-runner/konghai-friends-lab-1`、`~/actions-runner/mac-mini-acquilang-native-1`、`~/actions-runner/mac-mini-acquilang-ci-{1..5}`  
> 2026-08-15 起 sonar 槽改为 **LaunchDaemon**（`system/actions.runner.cypressoai.mac-mini-sonar-N`），注销图形用户后仍应在线。  
> `mac-mini-mobile-1` 同样走 LaunchDaemon：`system/actions.runner.cypressoai.mac-mini-mobile-1`。  
> 旧 LaunchAgent plist 停在 `~/Library/LaunchAgents.disabled-20260815/`。  
> 固定恢复脚本：`~/bin/mac-mini-runner-resume.sh`（kickstart 1..4 + mobile-1 + acquilang-native-1）  
> 日志：`~/Library/Logs/mac-mini-runner-resume.log`  
> 池与 label 定义见 [ci-runner-pools.md](./ci-runner-pools.md)
>
> 2026-08-19 曾 `launchctl disable` 停掉 `mac-mini-sonar-3/4` 给 Multica 留并发；**2026-08-25 已 enable + bootstrap 恢复**，四 slot 重新 online。当时条目见 [operations/mac-mini.md](../operations/mac-mini.md)。

**不要再运行 `./svc.sh install` / `./svc.sh start`。** 那会把 LaunchAgent 装回 `~/Library/LaunchAgents`，登录后和 Daemon 双开。

## 宿主工具：azure-cli

`mac-mini-mobile-1` 的 launchd PATH 已含 `/opt/homebrew/bin`。OTA JS 以后若在本机 `az storage blob upload-batch`，二进制必须是 `/opt/homebrew/bin/az`。现网已装 Homebrew `azure-cli` 2.90.0；声明版本跟 brew 最新稳定即可，不必钉死这个号。

幂等安装（已装则跳过）：

```bash
brew list azure-cli || brew install azure-cli
```

验收（在 **mac-mini** 上，不要用开发者 MacBook Air）：

```bash
command -v az          # 必须打印 /opt/homebrew/bin/az
az version             # azure-cli 有版本即可
# 以 runner 的 PATH 再确认一次，避免只在交互 shell 里看得到：
PATH='/opt/homebrew/opt/node@22/bin:/opt/homebrew/opt/openjdk@17/bin:/Users/konghai/Library/Android/sdk/platform-tools:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin' command -v az
```

不要为了 `az` 改 plist 或重启 `mac-mini-mobile-1`。不要给 runner 写 storage key / connection string。交互 `az login` 只给人手工验证，不能替代 GitHub Actions 的 OIDC。装 CLI **不会**让现有 `ota-publish-js.yml` 自动直传 Blob。

SSH 进 mac-mini 时 **不要** 跑默认 `az login`：当时 `/dev/console` 往往是 `root`，没有 `konghai` 图形会话，`osascript` 开浏览器会 `-10810`（没装 Firefox 还会再报 `-1728`）。用设备代码，在你面前的浏览器完成登录：

```bash
az login --use-device-code
```

终端给的 `https://login.microsoft.com/device` 只是跳转入口；填码页是 `https://login.microsoftonline.com/common/oauth2/deviceauth`（标题「登录到您的帐户」，输入框占位符是「代码」不是邮箱）。登录后两条订阅都叫 `Microsoft Azure`：选 `408f1434-56ae-45b6-9762-7c9e1e615000`（iCare 2.0 UAT/PROD，选择器默认 `[1]`）。另一条 `e026db6e-...` 是老 IHC，不要选。

2026-09-18 已用 `--use-device-code` 核验通过，交互身份 `byang@icare.com.ph`。这不能替代 GHA OIDC。

取证：[az-login-ssh-cannot-open-browser-2026-09-18](../solutions/mac-mini/runtime-errors/az-login-ssh-cannot-open-browser-2026-09-18.md)。

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
sudo /bin/launchctl kickstart -k system/actions.runner.konghai-friends-lab-AcquiLangAI.mac-mini-acquilang-native-1
```

KeepAlive 已开，崩溃后 launchd 会自己拉。resume 主要给「人为 bootout 之后」用。`acquilang-native-1` 在装上 LaunchDaemon 之前，kickstart 会报 not loaded。

## 停止

```bash
for n in 1 2 3 4; do
  sudo launchctl bootout system/actions.runner.cypressoai.mac-mini-sonar-$n
done
sudo launchctl bootout system/actions.runner.cypressoai.mac-mini-mobile-1
sudo launchctl bootout system/actions.runner.konghai-friends-lab-AcquiLangAI.mac-mini-acquilang-native-1
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

## AcquiLangAI `mac-mini-acquilang-native-1`

仓库级 runner，只给 `IAmKongHai/AcquiLangAI` 用。**不要**贴 `mac-mini`（会命中 iCare `mac-mini-mobile-1`），**不要**贴 `konghai-friends-lab`（会和 org 槽抢活）。workflow 写：

```yaml
runs-on: [self-hosted, macos, arm64, acquilang-native-ci]
```

仓库迁移后保留旧 LaunchDaemon 名称，不要据服务名判断仓库归属。2026-09-11 21:40 CST 已装 LaunchDaemon：`system/actions.runner.konghai-friends-lab-AcquiLangAI.mac-mini-acquilang-native-1`。不要 `./svc.sh install`。仓库副本：`scripts/install-mac-mini-acquilang-native-runner-daemon.sh`。

若需重装 Daemon：

```bash
sudo /Users/konghai/gha/scripts/install-mac-mini-acquilang-native-runner-daemon.sh
```

kickstart：

```bash
sudo /bin/launchctl kickstart -k system/actions.runner.konghai-friends-lab-AcquiLangAI.mac-mini-acquilang-native-1
```

```bash
gh api repos/IAmKongHai/AcquiLangAI/actions/runners \
  --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
```

## AcquiLangAI 日常 CI `mac-mini-acquilang-ci-1` … `5`

仓库级 runner，只注册到 `IAmKongHai/AcquiLangAI`。五个 slot 使用同一个 label `acquilang-ci`，GitHub 把 backend、admin、native、web、sonar 分到空闲 slot。原生打包继续使用 `acquilang-native-ci`。这些实例共享 mac-mini 的 CPU、内存与磁盘，也不带 cypressoai 池标签。

| slot | 程序 | 工作目录 | 2026-10-10 的拉起方式 |
| --- | --- | --- | --- |
| 1 | `~/actions-runner/mac-mini-acquilang-ci-1` | `~/gha/alc1` | 系统 LaunchDaemon，重启后仍在 |
| 2–5 | `~/actions-runner/mac-mini-acquilang-ci-{2..5}` | `~/gha/alc{2..5}` | 用户域 LaunchAgent。当前会话在线；重启或用户域卸载后不会自动回来 |

- 服务名：`actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-N`
- `ci-1` 的 plist 在 `/Library/LaunchDaemons/`。`ci-2` … `5` 的 plist 目前在 `~/Library/LaunchAgents/`，`LimitLoadToSessionType` 为 `Background`。
- 日志：`~/Library/Logs/actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-N/`
- Python：`/opt/homebrew/opt/python@3.12/bin/python3.12`（接入时为 3.12.11）。CI 直接调用，不使用依赖 `/Users/runner` 的 `setup-python` macOS 安装包。
- 各 slot 的 `.env` 把 `PNPM_STORE_PATH` 和 `npm_config_store_dir` 指到同一个 `/Users/konghai/gha/cache/pnpm-store`。不复制 Native 的凭据。
- `config.sh` 不生成根目录的 `runsvc.sh`。从 `bin/runsvc.sh` 复制。不要跑 `./svc.sh install`，那会再写一份用户域 LaunchAgent，并和系统服务抢同一个 runner。
- 安装脚本只安装尚未存在的系统服务；已有 plist 或已加载的系统服务会跳过，不覆盖、不重启。

把 `ci-2` … `5` 改成重启后仍在的系统服务（在 mac-mini 上执行，需要 sudo）。脚本会先卸下对应的用户域 LaunchAgent；slot 上有 job 时会退出，不打断：

```bash
sudo /Users/konghai/gha/scripts/install-mac-mini-acquilang-ci-runner-daemon.sh 2 3 4 5
```

安装脚本仓库副本：[`scripts/install-mac-mini-acquilang-ci-runner-daemon.sh`](../../scripts/install-mac-mini-acquilang-ci-runner-daemon.sh)。不带参数时只处理 slot 1。

只读检查：

```bash
uid=$(id -u)
for n in 1 2 3 4 5; do
  echo "=== ci-$n"
  launchctl print "system/actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-$n" 2>/dev/null \
    || launchctl print "user/${uid}/actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-$n"
done
gh api repos/IAmKongHai/AcquiLangAI/actions/runners \
  --jq '.runners[] | {name,status,busy,labels:[.labels[].name]}'
```

停止或恢复前，先确认没有运行中的 CI，并取得操作确认。系统服务：

```bash
# 暂停并阻止重启后自动加载；保留注册、工作目录与 plist
sudo launchctl disable system/actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-1
sudo launchctl bootout system/actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-1

# 恢复已卸载的服务
sudo launchctl enable system/actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-1
sudo launchctl bootstrap system /Library/LaunchDaemons/actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-1.plist
```

用户域 slot（`ci-2` … `5`，把 `N` 换成 slot 号）：

```bash
uid=$(id -u)
label="actions.runner.IAmKongHai-AcquiLangAI.mac-mini-acquilang-ci-N"
launchctl bootout "user/${uid}/${label}"
launchctl bootstrap "user/${uid}" "$HOME/Library/LaunchAgents/${label}.plist"
```

`~/bin/mac-mini-runner-resume.sh` 和 crontab 日/周清理的 `WORK_DIRS` 仍不包含 `alc1` … `alc5`。定时清理需另行确认后添加。

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
