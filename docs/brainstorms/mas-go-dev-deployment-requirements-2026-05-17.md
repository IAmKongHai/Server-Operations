---
date: 2026-05-17
topic: mas-go-dev-deployment
---

# MAS Go + React 内网自动部署环境

## Summary

在 PVE 上新增独立 Linux VM `mas-go-dev`，用于承载 MAS Go 后端与 React 前端的内网开发/测试部署。该环境通过 GitHub Actions self-hosted runner 自动部署，但在 VM 内本地拉代码和构建 Docker 镜像，减少经过家庭网络透明代理的外网流量消耗。

---

## Problem Frame

MAS 正在从旧 C# / IIS 系统重构为 Go + React。现有 CI/CD 部署到 `dev-cypresso`，但这台公网测试机没有完整旧数据库，导致调试和行为对照困难。PVE 内已经有完整 SQL Server 参考库和旧 C# / IIS 参考环境，更适合承载新版 MAS 的内网调试环境。

`pve` 所在网络不能直接访问 GitHub，需要经过路由器上的透明代理。代理网络质量可用，但有月度流量限制；如果沿用“外部 runner 构建镜像 -> push registry -> 内网 VM pull 镜像”的方式，会额外消耗大量上传和下载流量。

---

## Actors

- A1. MAS 开发者：访问内网部署环境，调试 Go + React 重构版本，并对照旧系统行为。
- A2. GitHub Actions：在相关私有仓库有变更时触发自动部署。
- A3. `mas-go-dev` VM：运行 self-hosted runner、构建任务和 MAS 新系统容器。
- A4. `mssql-ref` VM：提供完整 MAS 参考 SQL Server 数据库。
- A5. `pve` 宿主机：提供虚拟化、Tailscale subnet route 和 VM 生命周期管理。

---

## Key Flows

- F1. 自动部署
  - **Trigger:** MAS 前端或后端私有仓库的部署分支发生变更。
  - **Actors:** A2, A3
  - **Steps:** GitHub Actions 将 job 分配给 `mas-go-dev` 上的 self-hosted runner；runner 在 VM 内 checkout 代码；VM 内执行 Docker build；构建成功后更新本机运行中的服务。
  - **Outcome:** 新版 Go 后端和 React 前端在 `mas-go-dev` 上完成部署，不需要 push/pull 业务镜像。
  - **Covered by:** R4, R5, R6, R7

- F2. 内网调试
  - **Trigger:** 开发者需要调试新版 MAS 或对照完整旧数据库数据。
  - **Actors:** A1, A3, A4, A5
  - **Steps:** 开发者通过家庭局域网或 Tailscale 访问 `mas-go-dev`；Go 后端连接 `mssql-ref` 的 SQL Server；开发者观察新版功能在完整参考数据上的行为。
  - **Outcome:** 调试环境能读到完整参考库，并且不依赖 `dev-cypresso` 的公网测试数据库。
  - **Covered by:** R1, R2, R3, R8

---

## Requirements

**VM 与隔离**

- R1. 在 PVE 上新增独立 VM `mas-go-dev` 承载新版 MAS，不直接把 Go、React、Docker、runner 或应用服务部署到 PVE 宿主机。
- R2. `mas-go-dev` 的操作系统应尽量对齐 `dev-cypresso`，优先使用 Amazon Linux 2023 x86_64，降低部署脚本和 Docker 行为差异。
- R3. `mas-go-dev` 应使用独立固定内网 IP，建议占用团队公共服务网段中的 `192.168.2.22`。

**CI/CD 与流量控制**

- R4. GitHub Actions 自动部署应通过 `mas-go-dev` 内的 self-hosted runner 执行，而不是要求 GitHub-hosted runner SSH 进入内网。
- R5. runner 只服务 MAS 相关私有仓库；当前至少覆盖前端和后端两个独立私有仓库，不开放给无关仓库。
- R6. 常规部署路径应在 `mas-go-dev` 内执行代码 checkout 和 Docker 本地构建，不把业务镜像 push 到 registry 后再 pull 回内网 VM。
- R7. 构建过程应保留可复用缓存，包括 Docker build cache、Go module cache、前端包管理器缓存和基础镜像缓存，以减少透明代理流量。

**网络与访问**

- R8. PVE 的 Tailscale subnet route 应从当前精确 `/32` 方案扩展为 `192.168.2.16/28`，把 `.16` 到 `.31` 作为团队公共服务网段管理。
- R9. `mas-go-dev` 对外访问 GitHub、包仓库和基础镜像仓库时允许经过现有透明代理，但方案应避免不必要的大体积重复上传/下载。
- R10. `mas-go-dev` 应能访问 `mssql-ref` 的 SQL Server，默认连接 `192.168.2.20:1433`。

**运维与安全**

- R11. 部署方案不得在仓库文档中记录明文密码、token、私钥、GitHub runner registration token 或数据库凭据。
- R12. runner 权限应按最小可用范围配置；优先使用 organization-level runner group 并限制 selected repositories，若权限不足再使用两个 repo-level runner。
- R13. PVE 网络配置、Tailscale route、VM 创建和 runner 注册都应有可回滚的操作记录；修改 PVE 配置前必须备份当前状态。

---

## Success Criteria

- 新版 MAS 前端和后端能由 GitHub Actions 自动部署到 `mas-go-dev`。
- 部署过程中不再常规 push/pull 业务 Docker 镜像，外网流量主要来自 git 增量、依赖变更和必要基础镜像更新。
- 开发者能通过家庭局域网或 Tailscale 访问 `mas-go-dev`，并让后端读取 `mssql-ref` 上的完整参考数据库。
- PVE 宿主机保持干净，只承担虚拟化和网络职责，不承载 MAS 应用运行时。
- 后续 `/ce:plan` 可以直接基于本文生成实施步骤，不需要重新决定 VM 拓扑、runner 范围或 Tailscale 网段。

---

## Scope Boundaries

- 不把 `mas-go-dev` 作为生产环境，也不承诺公网高可用。
- 不在 PVE 宿主机上直接运行 MAS 应用、Docker Compose stack 或 GitHub Actions runner。
- 不把业务镜像 registry 作为常规部署依赖；保留后续需要归档镜像时再单独设计。
- 不在本文决定前后端仓库的具体 workflow YAML、compose 文件结构、端口和域名；这些进入后续计划和实施。
- 不在本文改动 PVE、Tailscale、GitHub 或任何远端服务器配置。

---

## Key Decisions

- 新增独立 VM，而不是部署到 PVE 宿主机：隔离应用依赖、runner、Docker 缓存和日志，降低污染虚拟化宿主的风险，并便于快照回滚。
- VM 内运行 Docker 是可接受的：KVM + Linux VM + Docker 对 Go 后端和 React/nginx 这类负载的性能损耗可忽略，主要风险在磁盘、缓存和日志容量管理。
- 操作系统优先 Amazon Linux 2023：`dev-cypresso` 当前是 Amazon Linux 2023，Docker 25.0.14、Compose v2.24.5；新环境尽量对齐能减少兼容差异。
- 部署改为 VM 内本地 build：相比外部构建镜像再 push/pull，能显著减少透明代理流量，尤其避免业务镜像层重复上传和下载。
- Tailscale route 使用 `192.168.2.16/28`：这比列多个 `/32` 更符合后续团队公共服务网段规划，但要求 `.16-.31` 只放可被团队访问的公共服务。
- runner 范围限定到 MAS 相关私有仓库：优先用 GitHub organization runner group 的 selected repositories；如果不可用，再在 VM 上注册两个 repo-level runner。

---

## Dependencies / Assumptions

- PVE 已经可以运行 VM，并已有 `mssql-ref` 和 `mas-win` 参考环境。
- `mssql-ref` 的 SQL Server 地址为 `192.168.2.20:1433`。
- `mas-go-dev` 计划使用 `192.168.2.22`，且该地址未被其它服务占用。
- GitHub 当前 active 账号 `k-cypresso` 已验证可访问 `cypressoai` 的 org-level Actions runner API，具备继续按 organization runner group 方案规划的权限基础。
- `cypressoai` 当前只有 `Default` runner group，visibility 为 `all`；若要限制 selected repositories，实施时应新建 MAS 专用 runner group。
- 透明代理可以稳定访问 GitHub、GitHub Actions、Go module 源、npm/pnpm/yarn 依赖源和 Docker base image registry。
- 前后端仓库可以调整 workflow，使部署 job 跑在 `mas-go-dev` 的 self-hosted runner 上。

---

## Outstanding Questions

### Deferred to Planning

- [Affects R12][Technical] 新建 MAS 专用 organization runner group，并把可用范围限制到 MAS 前端和后端两个私有仓库。
- [Affects R1, R7][Technical] `mas-go-dev` 的初始规格是 4 vCPU / 8 GiB / 100G，还是前端构建较重需要 12-16 GiB RAM？
- [Affects R4, R6][Technical] 前后端是合并成一个 compose stack 部署，还是各仓库分别触发并更新自己的服务？
- [Affects R7][Technical] 前端包管理器是 npm、pnpm 还是 yarn；Go module cache 和前端依赖 cache 应落在哪个持久目录？
- [Affects R8][Technical] Tailscale Admin Console 中 approve `192.168.2.16/28` 后，是否需要撤掉旧的 `.20/.21` 精确 route 记录，还是由新 route 覆盖即可？
- [Affects R10][Technical] 新 Go 后端连接 SQL Server 时使用只读账号还是允许写入的参考环境账号；这取决于新版调试是否需要覆盖登录、审批、CRUD 等流程。
