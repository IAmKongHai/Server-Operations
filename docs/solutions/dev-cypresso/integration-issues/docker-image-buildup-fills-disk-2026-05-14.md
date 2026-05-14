---
title: GitHub Actions 部署失败，dev-cypresso 磁盘被 Docker 老镜像占满
date: 2026-05-14
category: docs/solutions/dev-cypresso/integration-issues
server: dev-cypresso
module: dev-cypresso / Docker + GitHub Actions Runner
problem_type: integration_issue
component: tooling
symptoms:
  - GitHub Actions 的 "Backend Deploy → Build and Push" 步骤报错 `mkdir /tmp/go-build.../...: no space left on device`
  - `df -h /` 显示根分区 100G 已 100% 使用，可用空间仅剩 17M
  - `du` 定位到 `/var/lib/docker` 占用 82G，其中 208 个镜像 37.6G、17 个 volumes 35.5G、build cache 2.5G
  - `ghcr.io/cypressoai/icare-backend` 仓库累积了上百个按 commit SHA 打 tag 的历史镜像，每个约 170MB
root_cause: config_error
resolution_type: configuration
severity: high
tags: [docker, disk-full, ci-cd, github-actions, image-cleanup, dev-cypresso]
---

# GitHub Actions 部署失败，dev-cypresso 磁盘被 Docker 老镜像占满

## Problem
dev-cypresso 上的 GitHub Actions self-hosted runner 每次部署都会拉取一个按 commit SHA 打 tag 的 `ghcr.io/cypressoai/icare-backend` 镜像，但部署流程没有清理旧镜像的步骤。镜像随 CI 频率不断累积（每个 ~170MB），最终把 100G 根分区占满，导致后续 CI 的 `docker build` 阶段在 `go build` 过程中因临时目录写盘失败而中断。

## Symptoms
- GitHub Actions 步骤日志：
  ```
  #17 [builder 8/9] RUN go build -trimpath -ldflags=... -o /out/api ./cmd/api
  #17 7.537 crypto/internal/fips140/aes/gcm: mkdir /tmp/go-build1642016868/b127/: no space left on device
  ```
- `df -h /` → `100G  100G   17M 100% /`
- `sudo du -h -d 1 /var/lib` → `/var/lib/docker  82G`
- `sudo docker system df` → `Images 208 / 37.6GB / RECLAIMABLE 31.72GB (84%)`
- `sudo docker image ls ghcr.io/cypressoai/icare-backend` 列出 200+ 条按 commit SHA 打 tag 的历史镜像

## What Didn't Work
- 直接清 `/tmp`：CI 失败的 `/tmp/go-build...` 是容器构建内部路径，主机 `/tmp` 只占 200M，不是根因
- 仅清 build cache：build cache 只有 2.5G，杯水车薪；元凶是历史镜像层

## Solution
通过 SSH 登录后用 Docker 自带的 prune 命令分两步清理。**注意不能用 `docker system prune -a --volumes`**，那会把 35.5G 的 volumes（含数据库等）一起删掉。

```bash
ssh dev-cypresso

# 删除所有未被运行容器引用的镜像（dangling + unused tagged）
sudo docker image prune -a -f

# 清理 builder/buildx 的构建缓存
sudo docker builder prune -a -f

# 验证
df -h /
sudo docker system df
```

清理后效果：

| 项 | 清理前 | 清理后 | 释放 |
|------|--------|--------|------|
| 根分区可用 | 17M | 32G | ~32G |
| Docker Images | 208 个 / 37.6GB | 16 个 / 9.38GB | ~28GB |
| Build Cache | 2.5GB (159 项) | 0 | ~4.3GB |
| Local Volumes | 35.5GB | 35.5GB | 未动（13 个在用） |

## Why This Works
- `docker image prune -a` 的判定标准是"是否被某个容器（运行或停止状态）引用"。生产部署里只有当前在跑的那个 tag 会被容器引用，其它 200 多个历史 SHA tag 都成了 dangling 引用，可以安全删除
- `-f` 跳过交互确认；CI 服务器上没有交互终端
- `docker builder prune` 只清 BuildKit 的中间层缓存，不会删任何最终镜像或 volume
- 不加 `--volumes` 是关键安全点：业务数据（数据库、上传文件等）都在 named volume 里，volumes 必须显式确认才能删

## Prevention

### 长期方案：在 CI 部署脚本里做"保留 1 个"白名单清理（2026-05-14 已落地）

根因是 CI 每次部署都打多个 tag（`:<branch>`、`:sha-<短>`、`:<github.sha>`、`:latest`），其中按 commit SHA 打的 tag 每次净增 2 个，而部署脚本里原本的 `docker image prune -f` **只清 dangling 镜像，对每个 tag 都不同的情况完全无效**——这就是为什么短时间内堆到 208 个镜像。

修复策略：在 `deploy` job 的最后一步（启动新容器之后），按"仓库白名单"清理同仓库下的历史 SHA tag，**只保留当前 SHA 和滚动 tag（`latest` / 分支名）**。这三者指向同一个镜像层，留下来才能 `docker images` 正常显示，也方便排查。

为什么放在 `deploy` job 而不是 `build-and-push`：只有"新容器已经起来"之后才能安全判断哪些 tag 没人引用。

#### iCare backend `.github/workflows/deploy.yml`

```yaml
echo "Cleaning up old icare-backend images (keep only the one in use)..."
# 只保留当前部署的 SHA 以及滚动 tag（latest/main/master/develop）指向的镜像层；
# 其余按 commit SHA 打 tag 的历史镜像全部删掉，避免磁盘累积。
IMAGE_REPO="${{ env.REGISTRY }}/${{ needs.set-vars.outputs.image_name }}"
CURRENT_SHA="${{ github.sha }}"
docker images "$IMAGE_REPO" --format '{{.Repository}}:{{.Tag}}' \
  | grep -vE ":(${CURRENT_SHA}|latest|main|master|develop)$" \
  | xargs -r docker rmi -f || true
# 再清一遍 dangling 层（被 rmi 解除引用后会变成 dangling）
docker image prune -f
```

#### iCare frontend-mas `.github/workflows/deploy.yml`

与 backend 同范式，差异：
- 这个仓库没有 `master` 分支，白名单只列 `main|develop`
- SSH 脚本里通过 `envs:` 注入了 `REGISTRY`，直接用 shell 变量 `$REGISTRY`
- 部署容器用的是 `:latest` 而非 `:<github.sha>`，但白名单两个都保留（指向同一层，多列一项不会出错）

```yaml
echo "Cleaning up old mas-portal images (keep only the one in use)..."
IMAGE_REPO="$REGISTRY/${{ needs.set-vars.outputs.image_name }}"
CURRENT_SHA="${{ github.sha }}"
docker images "$IMAGE_REPO" --format '{{.Repository}}:{{.Tag}}' \
  | grep -vE ":(${CURRENT_SHA}|latest|main|develop)$" \
  | xargs -r docker rmi -f || true
docker image prune -f
```

#### 写法上的几个细节

- **正则末尾的 `$`**：防止 SHA 中包含 "main" 字符串这种边界 case 误中（极小概率，但加上几乎零成本）
- **`xargs -r`**：没有输入时不执行 `docker rmi`（否则会报 "requires 1 argument"）
- **末尾 `|| true`**：某个层被已停止容器临时引用时 `docker rmi -f` 可能失败，不应阻塞部署
- **保留 `latest` / 分支 tag**：它们和当前 SHA 指向同一镜像层，删了不省空间，反而让 `docker images` 看不到这些 tag

### 适用范围

只对 **iCare backend + frontend-mas** 这两个项目生效。dev-cypresso 上其它项目（若新增）需要各自在 deploy.yml 里加同款逻辑。

### 验证方法

下一次部署完成后：

```bash
ssh dev-cypresso "sudo docker images ghcr.io/cypressoai/icare-backend | head"
ssh dev-cypresso "sudo docker images ghcr.io/cypressoai/icare-mas-portal | head"
```

每个仓库应该只剩 2-4 行（当前 SHA + latest + 分支 tag，可能指向同一个 IMAGE ID）。

### 监控自检（只读，可随时跑）

```bash
ssh dev-cypresso "df -h / && sudo docker system df"
```

后续若 `Use% > 80%` 或 `Images` 数量重新膨胀，说明白名单失效或又冒出新项目没接清理逻辑。

## 关联
- 服务器：dev-cypresso（iCare 项目集成测试环境，self-hosted GitHub Actions runner 跑在这台机上）
- 影响范围：iCare backend 部署链路；其它项目不受影响
- 触发场景：CI 频率 ≈ 每天 30+ 次部署，每次新增 ~170MB 镜像
