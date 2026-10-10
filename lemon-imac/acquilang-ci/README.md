# AcquiLangAI CI

2026-10-10 在 lemon-imac 增加一个仓库级 runner，分担 mac-mini 上的 AcquiLang 日常检查。

## Runner

| 项目 | 配置 |
| --- | --- |
| 名称 / GitHub ID | `lemon-imac-acquilang-ci-1` / `28` |
| 范围 | 私有仓库 `IAmKongHai/AcquiLangAI` |
| Labels | `self-hosted`, `macOS`, `ARM64`, `acquilang-build` |
| 系统用户 | `for-konghai` |
| 服务 | LaunchDaemon `system/actions.runner.IAmKongHai-AcquiLangAI.lemon-imac-acquilang-ci-1`（2026-10-10 11:37 CST 起） |
| 程序 / 工作区 | `~/actions-runner/lemon-imac-acquilang-ci-1` / `~/gha/alci1` |
| 缓存 | `~/gha/cache/acquilang-pnpm-store`、`~/gha/cache/acquilang-npm` |
| runner 包 | `actions-runner-osx-arm64-2.337.0`，SHA-256 `5a2cd92908a93d7276a194e1de6008099f3e7946f3f8e14aa7a1a7b4a31fdec2` |

一个 slot。backend、admin、web、CI 汇总使用 `acquilang-build`。native 还要求 `macos` 和 `arm64`，所以也能落到这台机器。Sonar 仍要求 `macos` + `arm64` + `acquilang-ci`，因为后端测试库在 mac-mini 的 localhost。不要给这个 runner 加 `acquilang-ci`、`acquilang-native-ci` 或 cypressoai 池标签。

Python 由 workflow 里的 `uv` 安装，Node 24 由 `actions/setup-node` 安装。`.env` 只有语言和 pnpm / npm 缓存路径，没有数据库密码。

8GB 内存上已经有 org runner `lemon-imac-1/2`。不要再加第二个 AcquiLang slot。

## 服务

2026-10-10 11:37 CST 起由 LaunchDaemon 拉起，注销图形用户或重启后仍应在线。plist 在 `/Library/LaunchDaemons/actions.runner.IAmKongHai-AcquiLangAI.lemon-imac-acquilang-ci-1.plist`。不要运行 `./svc.sh install` 或 `./svc.sh start`，那会再写一份用户域 LaunchAgent，和 Daemon 双开。

再执行安装脚本时，如果系统服务已在，脚本会跳过：

```bash
sudo /Users/for-konghai/gha/scripts/install-lemon-imac-acquilang-ci-runner-daemon.sh
```

## 只读检查

```bash
gh api repos/IAmKongHai/AcquiLangAI/actions/runners/28 --jq '{name,status,busy,labels:[.labels[].name]}'
ssh lemon-imac 'launchctl print system/actions.runner.IAmKongHai-AcquiLangAI.lemon-imac-acquilang-ci-1 | grep -E "state =|pid ="'
```

## 回滚

确认没有 job 后，只 bootout 上述 LaunchDaemon。不要停止 `lemon-imac-1/2`。注册、目录和缓存先留着；要彻底删除需另行确认。

```bash
sudo launchctl bootout system/actions.runner.IAmKongHai-AcquiLangAI.lemon-imac-acquilang-ci-1
```
