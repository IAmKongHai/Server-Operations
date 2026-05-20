---
title: GitHub Actions 自托管 runner VPN 下载流量优化
date: 2026-05-20
category: docs/solutions/mac-mini/workflow-issues
server: mac-mini
module: mac-mini / GitHub Actions self-hosted runner
problem_type: workflow_issue
component: development_workflow
severity: medium
applies_when:
  - "GitHub Actions self-hosted runner 位于需要控制 VPN 或代理流量的机器上"
  - "workflow 使用 actions/cache、setup-node cache、upload-artifact 或 download-artifact"
  - "runner 本机缓存可以长期保留，不是每次任务后销毁"
  - "VPN 统计显示下载量远高于上传量"
related_components:
  - actions-cache
  - sonar-scanner
  - npm-ci
  - docker-build-cache
  - mas-go-dev
tags: [github-actions, self-hosted-runner, vpn-traffic, sonar, npm-cache, workflow-optimization]
---

# GitHub Actions 自托管 runner VPN 下载流量优化

## Context

`mac-mini` 上运行 4 个 `mac-mini-sonar-*` GitHub Actions runner，负责 iCare 多个仓库的 SonarQube / 部署 workflow。用户观察到 VPN 最近一天统计为：

```text
下载 41.79 GB
上传 1.98 GB
```

这说明问题是明显的 download-heavy，而不是 runner 往外大量上传。

同一轮排查确认：

- SonarQube 服务端就在 `mac-mini` 上，地址是 `http://mac-mini:9000`。
- Sonar scanner 上报分析结果和 coverage 到 SonarQube 时走本机 / 局域网路径，不应优先怀疑为 VPN 主流量来源。
- `mac-mini` 本机 `~/.npm` 约 `9.3GB`，`~/.sonar` 约 `521MB`，`~/actions-runner` 约 `48GB`，主要是各 runner slot 的 Go build cache。
- Git checkout pack 较小：backend 约 `45-52MB`，frontend-mas 约 `14-16MB`，`fetch-depth: 0` 不足以解释每天 40GB 级别下载。
- backend 曾经在两个 job 之间通过 GitHub artifact 传递 `coverage.out`，单个 `coverage.out` 约 `170MB`。

结论：优化重点不是清本地缓存，也不是先改 SonarQube，而是减少 workflow 对 GitHub 远端 cache / artifact 服务的依赖，让持久化 self-hosted runner 复用本机缓存。

## Guidance

### 优先使用 runner 本地缓存

对长期在线的 self-hosted runner，`actions/cache` 和 `setup-node cache` 不一定省流量。它们的 cache archive 存在 GitHub 远端服务，cache hit 也需要从 GitHub 下载压缩包；如果 runner 本机 `~/.npm` 已经稳定保留，这反而会把本来可本地命中的依赖变成 VPN 下载。

前端 workflow 优先使用：

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 20

- run: npm ci --prefer-offline --no-audit --fund=false
```

避免在持久 runner 上无条件使用：

```yaml
- uses: actions/setup-node@v4
  with:
    node-version: 20
    cache: npm

- uses: actions/cache@v4
  with:
    path: ~/.npm
    key: npm-${{ hashFiles('package-lock.json') }}
```

### 避免同机 job 之间绕 GitHub artifact

如果 coverage 生成和 Sonar 扫描最终都在 `mac-mini` runner 上完成，不要把 `coverage.out` 上传到 GitHub artifact 再下载回来。artifact 服务适合跨机器、跨系统、跨 job 传递必须保留的产物；同一台持久 runner 上的中间文件应尽量在同一个 job 内直接使用。

backend Sonar workflow 的优化方向：

```yaml
jobs:
  sonar:
    name: SonarQube Scan
    steps:
      - run: go test ./... -coverprofile=coverage.out
      - run: sonar-scanner
```

### 保持 required check 名称稳定

改 workflow 时要注意 GitHub branch ruleset / required checks 匹配的是 check context 名称。backend PR 曾因为 job 显示名从 `SonarQube Scan` 改成其它名字，被 GitHub 阻止合并并提示：

```text
Merging is blocked due to pending merge requirements
```

修复方式是恢复精确 job name：

```yaml
jobs:
  sonar:
    name: SonarQube Scan
```

以后改 CI 结构时，先查 required check context，避免“功能跑通但 PR 不能合并”。

### Docker build cache 不等于 VPN 流量

`mas-go-dev` 的排查显示，实际部署 runner 是 `ec2-user@192.168.2.22` 上的 `mas-go-dev`，不是 `mssql-ref` / `192.168.2.20`。该 runner 本地 Docker build cache 约 `59.13GB`，但这是本地磁盘缓存，通常会减少依赖、base image 和 build layer 的重复下载。

优化 VPN 流量时，不要为了“看起来缓存很大”就激进 prune Docker build cache。正确策略是：

- 先确认它是否导致磁盘压力；
- 没有磁盘压力时保留本地 build cache；
- 只有空间风险时，按时间清理旧 cache，而不是每次 CI 后清空。

## What Changed

本次优化已创建 Jira：

- `CYP-636`：优化 self-hosted runner VPN 流量消耗

已合并的 GitHub PR：

- backend：[cypressoai/iCare-backend#331](https://github.com/cypressoai/iCare-backend/pull/331)
- frontend-mas：[cypressoai/iCare-frontend-mas#327](https://github.com/cypressoai/iCare-frontend-mas/pull/327)
- frontend-hr-portal：[cypressoai/iCare-frontend-hr-portal#4](https://github.com/cypressoai/iCare-frontend-hr-portal/pull/4)
- frontend-map：[cypressoai/iCare-frontend-map#4](https://github.com/cypressoai/iCare-frontend-map/pull/4)

具体改动：

- `frontend-mas` sonar / deploy：移除 `actions/cache` / `setup-node` npm cache，`npm ci` 改为 `npm ci --prefer-offline --no-audit --fund=false`。
- `frontend-hr-portal` sonar：移除远端 npm cache，改用 runner 本地 npm cache。
- `frontend-map` sonar：移除远端 npm cache，改用 runner 本地 npm cache。
- `backend` sonar：把 coverage 生成和 Sonar 扫描合并到同一个 job，移除 `coverage.out` artifact 上传 / 下载。
- `backend` required check：恢复 job 显示名 `SonarQube Scan`，满足 `develop` ruleset 要求的精确 context。

## Why This Matters

自托管 runner 的优势是可以复用本地磁盘、局域网服务和 Docker / npm / Go cache。错误使用 GitHub 远端 cache 和 artifact，会把这些优势绕回公网服务。

这次的流量方向也强化了判断：

- 如果是 Sonar scanner 上传报告导致，应该看到上传量显著上升。
- 实际上传只有 `1.98GB`，下载却有 `41.79GB`。
- GitHub cache hit、artifact download、依赖下载、action 包下载都属于下载路径，更符合现象。
- SonarQube 服务端在 `mac-mini` 本地，coverage 上报到 SonarQube 不应计入 VPN 大头。

## Verification

用户已在 PR 全部合并后重置 VPN 流量统计。下一步观察 2026-05-21 的日流量：

- 如果下载量明显下降，说明远端 cache / artifact 是主要贡献项。
- 如果下载量仍接近 40GB，需要继续按域名 / 进程拆分：GitHub artifact/cache、npm registry、Go proxy、Docker registry、runner action 包下载。

本地 runner 侧可以用这些只读命令复查：

```bash
# mac-mini: 检查本地缓存规模
du -sh ~/.npm ~/.sonar ~/actions-runner 2>/dev/null

# mac-mini: 检查 git pack 是否足以解释大流量
find ~/actions-runner -path '*/.git/objects/pack/*.pack' -print -exec du -h {} \;

# mas-go-dev: Docker cache 先观察，不因 VPN 优化而立即清理
docker system df
```

## Related

- [SonarQube 从 dev-cypresso 迁移到 mac-mini](../sonarqube-migrated-from-dev-cypresso-2026-05-13.md)
- [在 PVE 上新增 MAS Go + React 内网自动部署环境](../../pve/best-practices/mas-go-dev-deployment-2026-05-17.md)
- [GitHub Actions 部署失败，磁盘被 Docker 老镜像占满](../../dev-cypresso/integration-issues/docker-image-buildup-fills-disk-2026-05-14.md)
- [PVE Tailscale subnet router](../../pve/best-practices/pve-tailscale-subnet-router-2026-05-16.md)

