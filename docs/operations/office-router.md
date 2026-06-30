# office-router 运维操作时间线

## 2026-06-30 12:28 CST - 移除闲置 GitHub Actions runner

- 服务器：`office-router`
- 操作人：`Codex`
- 原因：该路由器上的 GitHub Actions self-hosted runner 已不再使用，需要停止 runner 并释放 Docker 镜像、volume 和运行进程占用的资源。
- 影响：
  - 停止并删除 Docker 容器 `github-runner-office`。
  - 删除 runner 使用的 Docker volume：`office-runner-home`、`office-runner-work`。
  - 删除不再被其它容器使用的镜像 `ghcr.io/actions/actions-runner:latest`。
  - 删除原始操作目录 `/opt/github-runner`，避免后续误执行 `start.sh` 重新拉起 runner。
  - 未重启路由器，未停止 Docker daemon，未修改网络、防火墙、SSH 或其它业务配置。
- 备份：
  - `/opt/github-runner-backup-20260630-122752/`，权限 `700`，包含原 `/opt/github-runner` 配置目录、清理前 `docker inspect`、`docker ps` 和 `docker system df` 输出。
- 回滚方式：
  1. 从 `/opt/github-runner-backup-20260630-122752/github-runner` 恢复 `/opt/github-runner`。
  2. 在 GitHub 页面重新生成 self-hosted runner 注册 token，并更新 `/opt/github-runner/runner.env`。
  3. 执行 `/opt/github-runner/start.sh` 重新创建 volume、拉取镜像并注册 runner。
  4. 如 GitHub 页面仍保留旧的离线 `office-router-light-ci-1` runner，需要在 GitHub UI/API 中手动删除。
- 变更：
  1. 清理前确认 runner 形态：
     - 容器：`github-runner-office`
     - 镜像：`ghcr.io/actions/actions-runner:latest`
     - 重启策略：`unless-stopped`
     - volume：`office-runner-home` 挂载到 `/home/runner`，`office-runner-work` 挂载到 `/home/runner/_work`
     - runner 进程：`/home/runner/bin/Runner.Listener run`
  2. 创建备份目录并保存现状。
  3. 执行 `docker rm -f github-runner-office` 停止并删除容器。
  4. 执行 `docker volume rm office-runner-home office-runner-work` 删除 runner 数据卷。
  5. 执行 `docker image rm ghcr.io/actions/actions-runner:latest` 删除闲置 runner 镜像。
  6. 删除 `/opt/github-runner` 原始操作目录。
- 验证：
  - `docker ps -a` 无容器。
  - `docker volume ls` 无 volume。
  - `docker images` 无镜像。
  - `docker system df` 显示 Images / Containers / Local Volumes 均为 `0B`。
  - `ps w` 未发现 `Runner.Listener`、`Runner.Worker`、`actions-runner` 或 `github-runner-office` 进程。
  - `/opt/github-runner` 已不存在，备份目录 `/opt/github-runner-backup-20260630-122752` 保留。
  - `/opt` 从清理前约 `2.2G` 已用降至 `2.7M` 已用。
