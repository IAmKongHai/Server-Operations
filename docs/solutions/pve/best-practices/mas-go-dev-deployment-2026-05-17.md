---
title: 在 PVE 上新增 MAS Go + React 内网自动部署环境
date: 2026-05-17
last_updated: 2026-05-18
category: docs/solutions/pve/best-practices
server: pve
module: pve / mas-go-dev
problem_type: best_practice
component: development_workflow
severity: low
applies_when:
  - 新增内网开发测试 VM，同时保留既有 dev-cypresso 部署
  - GitHub Actions self-hosted runner 需要限制到指定私有仓库
  - 部署目标网络访问外网流量受限，需要避免 registry push/pull 业务镜像
  - 后端 schema 与 seed 需要随部署自动收敛
tags: [pve, mas, mas-go-dev, go, react, github-actions, self-hosted-runner, runner-group, docker, docker-compose, migration, seed, tailscale, internal-deployment]
---

# 在 PVE 上新增 MAS Go + React 内网自动部署环境

## Context

MAS 正在用 Go + React 重构。原有 `dev-cypresso` 部署在公网测试机上，必须继续保留，但它没有完整参考数据库，调试 MAS 旧业务行为不方便。

这次新增的是并行的内网部署目标：在 PVE 上创建独立 VM `mas-go-dev`，让 MAS Go 后端和 React 前端靠近 `mssql-ref` 参考数据库运行。PVE 既有 MAS 参考环境已经包括 `mssql-ref` 和 `mas-win`，早期 PVE session 已经验证过固定 VM/IP、Tailscale subnet router、凭据只留服务器本地、写入 `docs/solutions/` 的运维模式是可复用的（session history）。

最终目标不是替换 `dev-cypresso`，而是新增一套可通过 GitHub Actions 自动部署、可访问完整 SQL Server 参考库、且降低外网镜像流量消耗的开发测试环境。

| VMID | VM | IP | 用途 |
| ---: | --- | --- | --- |
| `110` | `mssql-ref` | `192.168.2.20` | MAS 参考 SQL Server |
| `120` | `mas-win` | `192.168.2.21` | MAS 老 C# / IIS 参考应用 |
| `130` | `mas-go-dev` | `192.168.2.22` | MAS Go 后端 + React 前端内网自动部署 |

## Guidance

在 PVE 上承载这类开发测试部署时，应用和 runner 放进独立 VM，不直接部署到 PVE 宿主机。PVE 宿主只负责虚拟化、网络和 Tailscale subnet router。

`mas-go-dev` 的部署路径与 `dev-cypresso` 明确分离：

- `dev-cypresso` 原有 build/push/SSH deploy workflow 不删除、不降级；
- `mas-go-dev` 使用独立 GitHub Actions runner group；
- feature branch 通过 `workflow_dispatch` 实测时，只跑 `mas-go-dev` 部署，不触发 GHCR build/push 和 `dev-cypresso` deploy；
- 后端和前端都在 VM 本地 checkout 后 Docker build，再 `docker compose up`，避免业务镜像 push 到 registry 再 pull 回内网；
- 后端每次部署自动用临时容器跑 migrate + seed，避免新增 migration 或 seed 后靠人工记得执行。

## Implementation

### VM 与运行时

`mas-go-dev` 最终配置：

| 项目 | 值 |
| --- | --- |
| VMID | `130` |
| IP | `192.168.2.22/24` |
| OS | Amazon Linux 2023 x86_64 |
| CPU / Memory | 4 vCPU / 16 GiB |
| Disk | `nvme-data`，120G thin-provisioned |
| Runtime root | `/opt/mas-go-dev` |
| Runtime owner | `actions-runner` |
| Docker | `25.0.14` |
| Docker Compose | `v2.24.5` |
| Docker network | `shared-services` |
| Backend env | `/opt/mas-go-dev/backend/.env.docker`，mode `600` |

AL2023 首次 UEFI 启动曾卡在 `Access Denied`。处理方式是重建 EFI disk 并关闭 pre-enrolled Secure Boot keys，之后 VM 正常启动。

### Tailscale subnet route

PVE Tailscale route 从只覆盖 `192.168.2.20/32`、`192.168.2.21/32` 扩展为团队公共服务网段：

```bash
tailscale set --advertise-routes=192.168.2.16/28
```

选择 `/28` 是为了覆盖 `192.168.2.16` 到 `192.168.2.31`，给后续团队公共服务留地址，同时不暴露整个家庭内网。相关细节见 [pve-tailscale-subnet-router-2026-05-16.md](pve-tailscale-subnet-router-2026-05-16.md)。

### GitHub Actions runner group

在 `cypressoai` organization 中创建 runner group：

| 项目 | 值 |
| --- | --- |
| Runner group | `mas-go-dev` |
| Group ID | `3` |
| Visibility | selected repositories |
| Selected repos | `cypressoai/iCare-backend`、`cypressoai/iCare-frontend-mas` |
| Runner name | `mas-go-dev` |
| Labels | `self-hosted`, `Linux`, `X64`, `docker`, `mas-go-dev`, `al2023` |

runner 只用于 MAS 后端和前端两个私有仓库，避免 organization-level runner 被其它仓库误用。

### Backend workflow

后端 PR：[cypressoai/iCare-backend#267](https://github.com/cypressoai/iCare-backend/pull/267)

新增 `deploy-mas-go-dev` job：

- `runs-on: [self-hosted, Linux, X64, mas-go-dev]`
- 本地构建镜像：`icare/backend:mas-go-dev-${{ github.sha }}`
- 使用 VM 本地 env：`/opt/mas-go-dev/backend/.env.docker`
- 部署前执行：

```bash
docker compose -f "$COMPOSE_FILE" run --rm seed
```

这个临时 `seed` 容器会执行 `migrate up -> seed dry-run check -> seed apply`，完成后自动删除。随后 workflow 停掉旧 API 容器并启动新 API 容器。

这样做比手动传参数更稳：每次部署都会让 schema、seed 和代码一起收敛，不依赖人记得“这次有没有 migration/seed”。

### Frontend workflow

前端 PR：[cypressoai/iCare-frontend-mas#265](https://github.com/cypressoai/iCare-frontend-mas/pull/265)

新增 `deploy-mas-go-dev` job：

- `runs-on: [self-hosted, Linux, X64, mas-go-dev]`
- 本地构建镜像：`icare/mas-portal:mas-go-dev-${{ github.sha }}`
- Docker build 使用 Node 24，匹配前端项目 runtime 要求；
- `MAS_PORT_BIND=0.0.0.0:5174`；
- compose 加入 external Docker network `shared-services`；
- nginx `/api/` 通过 Docker DNS 代理到后端服务名 `api:8080`。

核心 nginx 形态：

```nginx
location /api/ {
    resolver 127.0.0.11 ipv6=off;
    set $api_upstream http://api:8080;
    proxy_pass $api_upstream;
}
```

## Workflow Pitfalls

### `set-vars` 不能阻塞 mas-go-dev 手动部署

第一次 GitHub Actions 实测时，两个 repo 都卡在 `Set Environment Variables` job。原因是原 workflow 的 `set-vars` 固定跑在 `dev-cypresso-ci` self-hosted runner，而这组 runner 当前离线。

修复方式不是恢复旧 runner，而是拆开依赖：

- `set-vars` 只在原 `main/master/develop` 的 GHCR build/push 和 `dev-cypresso` 部署路径需要时运行；
- `mas-go-dev` 的 `workflow_dispatch` 不依赖 `set-vars`；
- feature branch 手动部署时，旧 GHCR build/push 和 `dev-cypresso` deploy 按条件 skipped。

### 合并 `origin/develop` 后保留两套语义

合并 `origin/develop` 时两个 workflow 都冲突。`develop` 已经有“develop 部署阶段跳过重复测试”的优化；本次分支需要“workflow_dispatch 实测仍跑质量门禁”。

最终规则：

- `workflow_dispatch`：跑 lint/test/typecheck，再部署 `mas-go-dev`；
- `develop` 自动部署：可接受质量门禁 skipped，但只有明确 skipped/success 才允许进入部署；
- `failure` 或 `cancelled` 不允许部署；
- `deploy-mas-go-dev` 使用 `always()` 时必须搭配 `needs.<job>.result` 显式判断，不能只靠默认 dependency 行为。

## Verification

最终 PR 状态：

| Repo | PR | Mergeable | Final run |
| --- | --- | --- | --- |
| backend | [#267](https://github.com/cypressoai/iCare-backend/pull/267) | `MERGEABLE` | `25996251791` success |
| frontend | [#265](https://github.com/cypressoai/iCare-frontend-mas/pull/265) | `MERGEABLE` | `25996251836` success |

最终服务验证：

```bash
curl -fsS http://192.168.2.22:5174/healthz
curl -fsS http://192.168.2.22:5174/api/v1/health
```

结果：

```text
/healthz -> ok
/api/v1/health -> 200, database up
```

最终运行容器：

```text
mas-icare-portal icare/mas-portal:mas-go-dev-905bfa9e9899167ca78186982ef553af3ee43719 Up 0.0.0.0:5174->80/tcp
icare-backend-api-1 icare/backend:mas-go-dev-83d5311614d618e3e844c372b4c22bdde5967659 Up (healthy) 127.0.0.1:8080->8080/tcp
```

后端 `/api/v1/health` 返回版本：

```text
83d5311614d618e3e844c372b4c22bdde5967659
```

## Database Migration Record

用户已确认允许在 `mssql-ref` 上为 MAS Go 后端执行 migrate + seed。

执行前创建回滚点：

| Type | Location |
| --- | --- |
| PVE snapshot | VM `110` snapshot `before-mas-go-migrate-20260517` |
| SQL backup | `/restore/backups/mas-go-dev-before-migrate-20260517-2334/medicalassistance.bak` |
| SQL backup | `/restore/backups/mas-go-dev-before-migrate-20260517-2334/maswebkit.bak` |
| SQL backup | `/restore/backups/mas-go-dev-before-migrate-20260517-2334/authprovidermasweb.bak` |

首次执行：

```bash
docker compose -f /opt/mas-go-dev/backend/backend.compose.yaml run --rm seed
```

结果：

- migrations `1` through `18` applied；
- seed dry-run check completed；
- seed apply completed；
- backend health healthy。

后续部署自动执行同一条 seed pipeline。`mas-go-dev` 是开发集成环境，自动 migrate+seed 的收益高于手动 gate：减少忘跑 migration/seed 的概率，让代码、schema、参考数据同步演进。

## Why This Matters

这个部署模式解决了三个具体问题：

1. `dev-cypresso` 必须保留，但它没有完整参考数据库；
2. PVE 所在网络访问 GitHub/GHCR/Docker Hub 依赖透明代理，镜像 push/pull 会消耗额外外网流量；
3. MAS Go 的 migration 和 seed 会持续变化，靠手动触发容易漏。

把 CI/CD 改成 VM 本地 build + compose deploy 后，GitHub Actions 只拉代码和依赖，业务镜像不需要绕 GHCR 一圈。把 migrate+seed 放进部署流程后，后端 schema 和 seed 数据跟随每次部署自动收敛。

## When to Apply

适用于：

- PVE 上新增项目级 dev/test VM；
- 需要靠近内网数据库或参考系统部署；
- GitHub Actions runner 可以放在目标网络内；
- 私有仓库数量有限，适合用 selected runner group 控制调度范围；
- 外网流量受限，不希望每次部署都 push/pull 大镜像；
- dev/test 环境允许每次部署自动跑幂等 migrate + seed。

不适用于：

- 生产环境直接自动 seed；
- runner group 不能可靠限制 repo 权限的组织；
- migration/seed 还不是幂等流程的项目；
- 需要跨多台机器共享同一个 registry image artifact 的部署链路。

## Operational Notes

- PVE 宿主机仍按运维守则处理：网络、VM、Tailscale、数据库等改动先说明影响和回滚方式。
- runner token、数据库密码、GitHub token 不写入仓库。
- `mas-go-dev` 后端 `.env.docker` 只保存在 VM 内，权限为 `600`。
- 本地 SHA-tag image 仍要保留 prune 逻辑，避免 self-hosted runner 磁盘累积；相关事故经验见 [docker-image-buildup-fills-disk-2026-05-14.md](../../dev-cypresso/integration-issues/docker-image-buildup-fills-disk-2026-05-14.md)。
- PVE thin pool 和 VM 快照不能无限保留；历史 PVE session 已经遇到过 thin pool 逻辑超配风险（session history）。
- 旧 MAS 参考环境经验显示 preprod/UAT 形态要看环境开关和内部 secret，不要只看缓存参数；`mas-go-dev` 的 env 文件也应按实际运行语义维护（session history）。

## Remaining Cleanup

- VM config 里仍有首次失败 EFI disk 留下的 `unused0: nvme-data:vm-130-disk-0`，约 4 MiB；后续可在明确确认后清理。
- `mssql-ref` 和 `mas-go-dev` 的 QEMU guest agent 配置/运行状态还需要单独整理；当前 PVE 快照按在线 crash-consistent 理解。
- Tailscale Admin Console 的 key expiry 状态如后续确认已 disable，可回写到 subnet router 文档。

## Related

- [pve-tailscale-subnet-router-2026-05-16.md](pve-tailscale-subnet-router-2026-05-16.md)
- [mas-legacy-reference-sql-vm-2026-05-16.md](mas-legacy-reference-sql-vm-2026-05-16.md)
- [mas-csharp-iis-reference-deploy-2026-05-16.md](mas-csharp-iis-reference-deploy-2026-05-16.md)
- [docker-image-buildup-fills-disk-2026-05-14.md](../../dev-cypresso/integration-issues/docker-image-buildup-fills-disk-2026-05-14.md)
