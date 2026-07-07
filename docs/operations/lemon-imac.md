# lemon-imac 运维操作时间线

## 2026-07-07 22:51 CST - 配置裸跑 macOS ARM GitHub Actions runner

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：将新增 iMac 接入 `cypressoai` GitHub Actions 组织级 self-hosted runner，用于后续按标签调度 macOS ARM 任务。
- 影响：
  - 新增 runner 目录：`/Users/for-konghai/actions-runner/lemon-imac`。
  - 新增短 work 目录：`/Users/for-konghai/gha/li`，避免 macOS 上部分工具因 runner 临时目录路径过长出问题。
  - 新增并启动 macOS LaunchAgent：`actions.runner.cypressoai.lemon-imac`，配置文件位于 `/Users/for-konghai/Library/LaunchAgents/actions.runner.cypressoai.lemon-imac.plist`。
  - runner 注册到 GitHub 组织 `cypressoai` 的 `Default` runner group，名称 `lemon-imac`，标签为 `self-hosted`、`macos`、`arm64`、`lemon-imac`、`macos-arm64`。
  - 未安装 Docker；该 runner 当前为裸跑模式。没有 `docker`、`backend-ci`、`frontend-sonar-ci` 标签，不会承接依赖这些标签的现有 job。
- 备份：
  - 新增安装，无既有 runner 文件需要备份。
  - GitHub 注册 token 仅在本次命令中临时使用，未写入文档或磁盘。
- 回滚方式：
  1. `cd /Users/for-konghai/actions-runner/lemon-imac && ./svc.sh stop && ./svc.sh uninstall`
  2. 用 GitHub removal token 执行 `./config.sh remove --token <removal-token>`（token 可由 `gh api -X POST orgs/cypressoai/actions/runners/remove-token --jq .token` 获取）。
  3. 删除 `/Users/for-konghai/actions-runner/lemon-imac` 与 `/Users/for-konghai/gha/li`。
- 变更时序：
  1. 通过 GitHub API 确认组织 `cypressoai` 下没有同名 `lemon-imac` runner。
  2. 从官方 `actions/runner` release 下载 `actions-runner-osx-arm64-2.335.1.tar.gz`。
  3. 用 release 公布的 SHA-256 `e1a9bc7a3661e06fa0b129d15c2064fe65dc81a431001d8958a9db1409b73769` 校验通过后解压。
  4. 执行 `config.sh --unattended` 注册 runner，指定 runner group `Default`、名称 `lemon-imac`、work folder `/Users/for-konghai/gha/li`。
  5. 执行 `svc.sh install` 与 `svc.sh start` 安装并启动 LaunchAgent。
- 验证：
  - `svc.sh status` 显示 `actions.runner.cypressoai.lemon-imac` 已启动。
  - 远端进程存在 `runsvc.sh` 与 `Runner.Listener run --startuptype service`。
  - runner 日志显示 `Connected to GitHub`、`Current runner version: '2.335.1'`、`Listening for Jobs`。
  - GitHub API 显示 `lemon-imac`：`status=online`、`busy=false`、`os=macos`、标签正确。
  - 当前 service PATH 为 `/usr/bin:/bin:/usr/sbin:/sbin`；`git`、`curl`、`tar`、`unzip`、`xcodebuild` 可用，`brew`、`node`、`npm`、`docker`、`dotnet`、`gpg` 暂不在 PATH。
- 后续：
  - 如需承接 frontend/backend Sonar 或构建任务，先补齐 Homebrew、Node/npm、GPG 等工具链，并更新 runner service 的 `.path`；验证后再加 `frontend-sonar-ci` / `backend-ci` 等共享标签。
  - 只有 workflow 用到 `container:`、`services:` 或 Docker 构建/运行时才需要安装 Docker；普通 shell、Node、Xcode、Go 等任务可以裸跑。

## 2026-07-07 22:43 CST - 接入 Tailscale iMac SSH 别名并安装公钥

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，设备名 `lemon-imac` / 主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：新增一台 iMac 作为后续 runner 机器，需要从本机通过 Tailscale 内网稳定 SSH 登录，并设置易记别名。
- 影响：
  - 本机 `~/.ssh/config` 新增 `Host lemon-imac`，指向 `100.81.246.93`，用户 `for-konghai`，使用 `~/.ssh/id_ed25519`。
  - 远端 `for-konghai` 用户的 `~/.ssh/authorized_keys` 加入本机公钥，后续可用 `ssh lemon-imac` 免密登录。
  - 未安装 runner，未启动或重启服务，未修改系统级 SSH 配置。
- 备份：
  - 本机 SSH 配置备份：`~/.ssh/config.bak.20260707-ssh-lemon-imac`。
  - 远端授权文件备份：`/Users/for-konghai/.ssh/authorized_keys.bak.20260707-ssh-lemon-imac`。
- 回滚方式：
  - 本机删除 `~/.ssh/config` 中 `Host lemon-imac` 配置块，或用备份文件恢复。
  - 远端从 `/Users/for-konghai/.ssh/authorized_keys` 删除本机公钥行，或恢复上述备份文件。
- 变更时序：
  1. 确认 Tailscale 中 `100.81.246.93` 在线；用户在图形界面开启 SSH 后，22 端口可用。
  2. 备份本机 SSH 配置并追加 `lemon-imac` 别名。
  3. 通过密码认证把本机 `id_ed25519.pub` 上传到远端临时目录。
  4. 远端创建/更新 `~/.ssh/authorized_keys`，设置 `~/.ssh` 为 `700`、`authorized_keys` 为 `600`，并清理临时公钥文件。
  5. 使用 `ssh lemon-imac` 验证公钥免密登录。
- 验证：
  - `ssh lemon-imac` 登录成功，返回用户 `for-konghai`。
  - 系统：macOS `26.5.1`（Build `25F80`），架构 `arm64`。
  - 当前可用基础工具：`git`、`curl`、`tar`、`unzip`、`xcodebuild`。
  - 暂未发现 GitHub Actions runner 目录或 runner 进程；`brew`、`node`、`npm`、`dotnet`、`docker` 暂不在当前 `PATH`。
