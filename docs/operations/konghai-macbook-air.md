# macbook（本机 MacBook Air）运维时间线

## 2026-07-02 00:56 CST - 安装 Apple container 并验证 daohen-diary 容器化兼容性

- 原因：用户希望在本机安装 Apple 开源项目 `apple/container`，并评估 `/Users/konghai/Code_local/Project/daohen-diary` 是否可用它部署。
- 影响：
  - 本机安装 `container` CLI 1.0.0 到 `/usr/local/bin/container`，同时安装 `/usr/local/bin/update-container.sh` 与 `/usr/local/bin/uninstall-container.sh`。
  - 启动 Apple `container` system service，应用数据目录为 `/Users/konghai/Library/Application Support/com.apple.container/`。
  - 首次启动时安装默认 kernel：`vmlinux-6.18.15-186`。
  - 测试过程中拉取/构建了若干本机镜像：`alpine:latest`、`daohen-backend:local`、`daohen-frontend:local`、`golang:1.22-bookworm`、`debian:bookworm-slim`、`node:20-alpine`、`nginx:1.27-alpine`。
  - 未改动生产服务器；未改动本运维仓库以外的服务器环境。
- 回滚方式：
  - 停止 system service：`container system stop`。
  - 保留用户数据卸载：`/usr/local/bin/uninstall-container.sh -k`。
  - 删除用户数据卸载：`/usr/local/bin/uninstall-container.sh -d`。
  - 如只清理测试镜像/容器，可用 `container rm`、`container image rm`、`container prune` 按需删除。
- 做了什么：
  1. 确认本机满足官方要求：Apple Silicon，macOS 26.5.1，Homebrew 已安装；本运维仓库当前在 `main` 分支且工作区干净。
  2. 从 GitHub Release 下载官方签名安装包 `container-1.0.0-installer-signed.pkg`。
  3. 校验安装包 SHA-256：`13f45f26da94c354adcbefe1e8f7631e7f126e93c5d4dd6a5a538aa66b4f479d`，与 GitHub Release asset digest 一致。
  4. 用 `pkgutil --check-signature` 验证安装包由 `Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)` 签名，且 Apple notarization 可信。
  5. 通过 macOS 图形安装器完成安装；随后执行 `container system start`，按提示安装默认 kernel。
  6. 用 `container run --rm docker.io/library/alpine:latest echo container-ok` 验证基础镜像拉取与容器执行链路。
  7. 检查 `daohen-diary`：项目是 Go 后端 + Svelte/nginx 前端 + SQLite，已有 `Dockerfile`、`Dockerfile.frontend`、`docker-compose.yml`。
  8. 发现 `daohen-diary` 后端 `Dockerfile` 写死 `GOARCH=amd64`，Apple `container` 在本机默认以 `linux/arm64` 运行，直接启动时报 `Exec format error`；加 `--rosetta` 可临时运行，但不是原生方案。
  9. 临时修改 `daohen-diary/Dockerfile` 改用 `TARGETOS` / `TARGETARCH` 后重新构建，确认 Apple `container build` 产物为 `GOARCH=arm64`，不加 `--rosetta` 可启动后端并访问 `/api/health`。
  10. 构建前端镜像成功，但完整模拟 Compose 时，前端 nginx 的 `proxy_pass http://backend:8080/api/` 在 Apple `container` 网络内无法解析 `backend`，nginx 启动失败；说明 Apple `container` 不能直接等价替代 `docker compose up`。
  11. 按用户要求清理测试后端相关容器和测试网络；保留 Apple `container` builder。
- 验证结果：
  - `container --version`：`container CLI version 1.0.0 (build: release, commit: ee848e3)`。
  - `container system status`：`status running`，`apiserver.version container-apiserver version 1.0.0`。
  - Alpine 最小容器输出 `container-ok`。
  - `daohen-diary` 后端在修正架构构建后，`curl http://127.0.0.1:18081/api/health` 返回 `{"ok":true}`。
  - `daohen-diary/backend` 执行 `go test ./...` 通过。
  - 清理后 `container ls -a` 仅剩 Apple `container` 的 `buildkit` builder 容器运行。
- 结论：
  - Apple `container` 已可在本机使用，适合运行单容器或手工编排的 OCI 镜像。
  - `daohen-diary` 后端经过 Dockerfile 架构修正后可用 Apple `container` 原生运行。
  - `daohen-diary` 现有双容器部署仍以 Docker Compose 为准；若要正式支持 Apple `container`，需补充专用启动脚本，并处理前端到后端的服务发现 / nginx upstream 配置。

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
