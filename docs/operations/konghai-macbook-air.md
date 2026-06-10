# macbook（本机 MacBook Air）运维时间线

## 2026-06-10 22:35 CST

- 原因：本机注册 runner 后运行 CI job 时 CPU 满载发热，用户合盖使用，担心高温烫坏屏幕；且本机 label 已与 mac-mini 漂移（mac-mini 的 4 个 runner 第四 label 已是 `backend-ci`，本机仍是 `macbook` 且注册时用 `--no-default-labels` 去掉了 `self-hosted`，导致接不到改用 `runs-on: [self-hosted, backend-ci]` 的 backend CI job，分担队列的初衷已基本失效）。综合决定彻底下线本机 runner。
- 影响：org `cypressoai` 移除 self-hosted runner `macbook-1`；本机不再承接任何 CI job，CI 全部回落到 mac-mini（`mac-mini-sonar-1~4`）/ EC2 / `mas-go-dev` 等 runner；本机不再因 CI 发热。
- 回滚方式：如需重新上线，重新下载 runner 解压、`gh api -X POST orgs/cypressoai/actions/runners/registration-token` 取注册 token、`./config.sh` 注册到 org（**这次不要再用 `--no-default-labels`**，并把 label 对齐到 backend CI 共享池所需的 `self-hosted,backend-ci`，否则仍领不到 job）。
- 做了什么：
  1. `cd ~/actions-runner/macbook-1 && ./svc.sh stop` 停服务（Stopped）。
  2. `./svc.sh uninstall` 卸载 LaunchAgent（中途报 `Unload failed: 5: Input/output error`，因服务已先停、属无害报错；`launchctl list` 已无该服务、plist 文件已删，确认卸载成功）。
  3. `gh api -X POST orgs/cypressoai/actions/runners/remove-token` 取注销 token，`./config.sh remove --token <token>` 从 org 注销（Runner removed，`.credentials`/`.runner` 已清）。
  4. 清理 runner 目录：`~/actions-runner/macbook-1`（含 work 目录大量小文件，`rm -rf` 卡约 20 秒属正常）已删；`~/gha/m1` 删一半被 Ctrl+C 打断后，用户在访达内手动删除剩余 runner 缓存（`_PipelineMapping`/`_tool`/`iCare-frontend-mas`，均为 runner 工作缓存，非个人文件）。
- 验证结果：`gh api orgs/cypressoai/actions/runners` 列表已无 `macbook-1`；`~/actions-runner`、`~/gha` 两目录均 `No such file or directory`，已清空；家目录个人文件完好，未误删。
- 注意事项：macOS 默认无系统级文件删除审计日志（未开 `auditd`），删除是直接 unlink；本次删除参数写死两个 runner 专属路径、无通配符，不会波及个人文件。

## 2026-06-10 18:05 CST

- 原因：CI 队列大量积压，mac-mini 4 个 runner 不够消化；本机（MacBook Air M5，10 核 / 32GB / arm64）CPU 大多数时候空闲，注册为补充 runner 分担队列。
- 影响：org `cypressoai` 新增 self-hosted runner `macbook-1`，label 为 `mac-mini-sonar, macos, arm64, macbook`（与 mac-mini 4 个 runner 共享前三个 label，因此会领取同一队列的 job）；CI job 会在本机执行，占用本机 CPU / 磁盘。合盖或断网时 runner 掉线，job 回到队列由 mac-mini 接手。
- 回滚方式：`cd ~/actions-runner/macbook-1 && ./svc.sh stop` 临时下线；彻底移除执行 `./svc.sh uninstall`，再用 `gh api -X POST orgs/cypressoai/actions/runners/remove-token --jq .token` 取 token 后执行 `./config.sh remove --token <token>`。
- 做了什么：下载 runner v2.335.1 解压到 `~/actions-runner/macbook-1/`；用 `gh auth refresh -s admin:org` 提权后通过 API 取注册 token；`./config.sh` 注册到 org `cypressoai`，`--no-default-labels`，workFolder 用短路径 `/Users/konghai/gha/m1`（避免 mac-mini 2026-06-09 踩过的 GNUPGHOME 路径过长问题）；确认 `.path` 已含 `/opt/homebrew/bin`（gpg 可用）；`./svc.sh install && ./svc.sh start` 装成 LaunchAgent 开机自启。
- 验证结果：GitHub API 显示 `macbook-1 [online] busy=true`，启动后立即领取了排队 job；`launchctl` 服务 `actions.runner.cypressoai.macbook-1` Started（退出码 0）。
- 注意事项：MacBook Air 无风扇，长时间满载会热降频，定位为分担队列的补充 runner；`pmset` 显示 `sleep 0` 不会自动休眠，但合盖会掉线。
