# macbook（本机 MacBook Air）运维时间线

## 2026-06-10 18:05 CST

- 原因：CI 队列大量积压，mac-mini 4 个 runner 不够消化；本机（MacBook Air M5，10 核 / 32GB / arm64）CPU 大多数时候空闲，注册为补充 runner 分担队列。
- 影响：org `cypressoai` 新增 self-hosted runner `macbook-1`，label 为 `mac-mini-sonar, macos, arm64, macbook`（与 mac-mini 4 个 runner 共享前三个 label，因此会领取同一队列的 job）；CI job 会在本机执行，占用本机 CPU / 磁盘。合盖或断网时 runner 掉线，job 回到队列由 mac-mini 接手。
- 回滚方式：`cd ~/actions-runner/macbook-1 && ./svc.sh stop` 临时下线；彻底移除执行 `./svc.sh uninstall`，再用 `gh api -X POST orgs/cypressoai/actions/runners/remove-token --jq .token` 取 token 后执行 `./config.sh remove --token <token>`。
- 做了什么：下载 runner v2.335.1 解压到 `~/actions-runner/macbook-1/`；用 `gh auth refresh -s admin:org` 提权后通过 API 取注册 token；`./config.sh` 注册到 org `cypressoai`，`--no-default-labels`，workFolder 用短路径 `/Users/konghai/gha/m1`（避免 mac-mini 2026-06-09 踩过的 GNUPGHOME 路径过长问题）；确认 `.path` 已含 `/opt/homebrew/bin`（gpg 可用）；`./svc.sh install && ./svc.sh start` 装成 LaunchAgent 开机自启。
- 验证结果：GitHub API 显示 `macbook-1 [online] busy=true`，启动后立即领取了排队 job；`launchctl` 服务 `actions.runner.cypressoai.macbook-1` Started（退出码 0）。
- 注意事项：MacBook Air 无风扇，长时间满载会热降频，定位为分担队列的补充 runner；`pmset` 显示 `sleep 0` 不会自动休眠，但合盖会掉线。
