---
title: mac-mini-sonar runner 的重活迁到 Linux 容器 runner - Plan
type: ops
date: 2026-10-20
execution: manual
server: [mac-mini]
---

# mac-mini-sonar runner 的重活迁到 Linux 容器 runner - Plan

## 背景

2026-10-20 mac-mini 的 fseventsd 泄漏到 32G，load 73、swap 用满（见 `docs/operations/mac-mini.md` 当日条目）。实测和 XNU 源码表明，没有办法让内核不把某个卷的事件交给 fseventsd（`no_log` 只是不写事件日志）。VM 磁盘只是一个文件，内核会在 1 秒内合并同一进程对同一文件的同类事件，所以 VM 里怎么写盘都几乎不产生事件。真正产生大量事件的是直接在宿主上跑的 CI：Go 编译链接、`npm ci`、Vitest 会新建、删除、改名大量不同的文件，这些事件内核不合并。

目标：把 `mac-mini-sonar-1..4` 上不依赖 macOS 的重活挪进 colima VM 里的 Linux 容器 runner。文件变动留在 VM 自己的 ext4 盘里，宿主只看到一个磁盘文件。

## 现状：最近 14 天 job 构成

数据来源：`mac-mini-sonar-*/_diag/Worker_*.log`，统计 2026-10-06 ~ 10-20，按 job 占用 runner 的时长汇总，共 **6025 分钟**。

| 占用 | 次数 | 仓库 / job | runs-on | 依赖 macOS？ |
| --- | --- | --- | --- | --- |
| 1728m（29%） | 162 | iCare-backend / SonarQube Scan（`go test -coverpkg` + 扫描） | `[self-hosted, macos, arm64, backend-ci]` | 否 |
| 1867m（31%） | 259 | iCare-frontend-mas / Frontend Tests 1–4/4（Vitest + jsdom） | `[frontend-tests-ci, macos, arm64]` | 否 |
| 724m（12%） | 81 | backend / public-backend / Operations-backend / UAT Cut Tag | `[self-hosted, macos, arm64, backend-ci]` | 否，且基本是等 PR 检查，CPU 很轻 |
| 360m（6%） | 88 | iCare-mobile-app / CI Quality + SonarQube Scan（pnpm、jest） | `[frontend-quality-ci]` | 否 |
| 316m（5%） | 72 | iCare-frontend-mas / SonarQube Scan（PR 快扫 + 夜间全量） | PR：`[frontend-quality-ci]`；全量：`[mac-mini-sonar, macos, arm64]` | 否 |
| 284m（5%） | 25 | iCare-frontend-mas / Verify MAS UAT / PROD static bundle（Vite build） | `[mac-mini-sonar, macos, arm64]` | 否，但在发版关键路径上 |
| 192m（3%） | 14 | iCare-frontend-mas / Frontend Coverage（夜间，4 个分片并发） | `[mac-mini-sonar, macos, arm64]` | 否，但内存要求高 |
| 约 550m（9%） | — | 其它 lint / typecheck / 小仓库 CI / evp / moo-ticket | 多为 `frontend-quality-ci` / `backend-ci` | 否 |

结论：**sonar runner 上没有任何 job 真正依赖 macOS**。只要 macOS 的 iOS / EAS 构建在 `mac-mini-mobile-1`、`mac-mini-acquilang-native-1`，不在本计划范围内。

佐证：
- backend 测试只用进程内依赖（`glebarez/sqlite`、`miniredis`），已经在 Linux 的 `mas-go-dev-ci` 上跑过（workflow 注释说那里 coverage 最差 13 分钟，慢是因为那台是 2 核 x86 VM，不是 Linux 的问题）。SQL Server 相关测试需要显式环境变量才会跑。
- `frontend-quality-ci` 池本来就包含 Linux 的 `mas-go-dev-ci-1/2`，mobile CI、frontend lint / typecheck / PR Sonar 已经在 Linux 上跑通过。
- Vitest 用 jsdom，没有 Playwright / 浏览器 / 原生 canvas 依赖。

## 关键判断

1. **两类迁移方式不同。**
   - runs-on **不要求 macos** 的 job（`frontend-quality-ci` 一类）：只改 runner 侧 label，不用改 workflow。给容器 runner 贴上 label，再从 `mac-mini-sonar-*` 上摘掉这个 label 即可。
   - runs-on **写死了 `macos, arm64`** 的 job（backend Sonar / Lint、UAT Cut Tag、Frontend Tests 分片、Coverage、全量 Sonar、Verify bundle）：要改各仓库 workflow，PR base 到 `develop`。建议写成 `[self-hosted, Linux, ARM64, <池 label>]`，用 `ARM64` 排除 x86 的 `mas-go-dev-ci`。
2. **单独开一个 colima profile `ci`**，不要塞进 `konghai` 现有的 `colima`（6C/12G，已经跑着 sonarqube、多套 postgres、redis、s3、sub2api）。
3. **runner 工作目录必须在 VM 自己的盘上**（容器内路径或 docker volume），**不能**用 virtiofs 挂宿主目录，否则文件事件又回到宿主。
4. **内存是硬约束**。VM 内存是固定预留，宿主上 runner 是用多少占多少。迁一部分进 VM，就要同步减少宿主 sonar slot，不能两边都满配：

   | 阶段 | 宿主 `mac-mini-sonar` slot | `colima-ci` |
   | --- | --- | --- |
   | 现在 | 4 | 无 |
   | 试点 | 4（先不动） | 4C / 8G，2 个容器 runner |
   | 稳定后 | 1~2（只留给还没迁的 job / 兜底） | 6C / 12G，3~4 个容器 runner |

   同时建议 hon 把 `colima-moo` 的 10G 调小、停掉闲置的 CDC 组件，给 `colima-ci` 腾空间。

## 容器 runner 规格

- 镜像：基于官方 `ghcr.io/actions/actions-runner`（linux/arm64），加装 `git`、`gcc`、`libc6-dev`、`gnupg`、`dirmngr`（Sonar Scanner 签名校验需要，见 `docs/runbooks/ci-runner-pools.md` 上线 checklist）、`python3`、`unzip`、`gh`。Go 和 Node 由 job 内 `setup-go` / `setup-node` 安装。
- 注册：org `cypressoai`，组与现有 `mac-mini-sonar-*` 相同；名字 `mac-mini-linux-ci-{1..N}`；label 用默认的 `self-hosted, Linux, ARM64`，再按阶段加 `backend-ci` / `frontend-quality-ci` / `frontend-tests-ci`。
- 用 ephemeral 模式（每个 job 一个干净容器），缓存放 docker volume：`GOMODCACHE`、npm cache、pnpm store、Sonar Scanner 缓存。`GOCACHE` 每个 slot 一个 volume，避免 CYP-322 那种并发写竞争。
- `restart: always`，compose 放 `~/stacks/gha-linux-ci/`，凭据走 `.env`（600），不入库。
- **SonarQube 可达性**：`SONAR_HOST_URL` secret 现在大概是 `http://mac-mini:9000`（Tailscale MagicDNS）。容器里要先验证能不能解析；不行就在 compose 里加 `extra_hosts: mac-mini:host-gateway`。

## 分阶段

### 阶段 0：搭 VM 与 runner（不接任何 job）
- 建 `colima start --profile ci --cpu 4 --memory 8 --disk 100 --vm-type vz`，`mounts: []` 改成显式空挂载（不挂 `$HOME`）。
- 构建镜像，起 2 个 runner，只贴 `self-hosted, Linux, ARM64`（没有任何池 label，不会被现有 workflow 抽中）。
- 验证：容器内 `go`、`node` 可装，`gpg` + `dirmngr` 可用，`curl $SONAR_HOST_URL/api/system/status` 通。
- 写 LaunchDaemon 或复用 `com.konghai.colima` 的方式，让 `colima-ci` 开机自启。

### 阶段 1：只改 runner label 的 job（零 workflow 改动）
- 给容器 runner 加 `frontend-quality-ci`，从 `mac-mini-sonar-1..4` 摘掉 `frontend-quality-ci` 和历史的 `frontend-sonar-ci`。
- 覆盖：mobile CI Quality / Sonar、frontend lint / typecheck / PR Sonar、evp / moo-ticket frontend 等，约 600~900m / 14 天（部分小仓库 job 的 runs-on 没逐个核对）。
- 回滚：把 label 加回 mac-mini slot。

### 阶段 2：backend（改 iCare-backend 等的 workflow）
- `sonar.yml` 的 `lint`、`sonarqube` 和 `uat-cut-tag.yml`：`[self-hosted, macos, arm64, backend-ci]` → `[self-hosted, Linux, ARM64, backend-ci]`；容器 runner 加 `backend-ci`。
- 这一步会把 lemon-imac / umacbook-pro 也排除在外。runs-on 只能写"同时满足这些 label"，不能写"macos 或 Linux"，所以只能二选一：要么全部去 Linux 容器，要么保留 macos、继续在宿主上跑。
- 覆盖约 2600m / 14 天，是最大的一块。
- 观察一周：耗时对比（mac-mini 宿主平均 10.7 分钟/次）、OOM、缓存命中。

### 阶段 3：frontend Vitest 分片
- `sonar.yml` 的 `frontend-tests-shards`：`[frontend-tests-ci, macos, arm64]` → `[self-hosted, Linux, ARM64, frontend-tests-ci]`。
- 覆盖约 1870m / 14 天。`VITEST_MAX_WORKERS=2` 先不变。

### 阶段 4：重活（Coverage、全量 Sonar、Verify bundle）
- 需要 `colima-ci` 扩到 12G 左右；Coverage 注释里说要 32GB 机，4 个分片并发，进 VM 前要先量一次实际峰值内存。
- Verify MAS UAT / PROD static bundle 在发版关键路径上，最后迁，并保留一个宿主 slot 做兜底。
- 完成后宿主 `mac-mini-sonar` 可缩到 1 个 slot 或全部停用。

## 风险与回滚

| 风险 | 应对 |
| --- | --- |
| VM 内存预留太多，宿主更挤 | 按上表同步减宿主 slot；先试点 8G |
| 容器里解析不到 `mac-mini` | `extra_hosts: mac-mini:host-gateway`，或改用 Tailscale IP |
| 改 workflow 后 Linux 上有隐藏的平台差异（路径大小写、行尾、时区） | 每阶段先在一个 PR 上 `workflow_dispatch` 试跑，再合并 |
| colima-ci 挂了，带 Linux label 的 job 全部排队 | 稳定前宿主保留 1~2 个 slot；容器 `restart: always`，VM 开机自启 |
| 回滚 | runner 侧：label 加回宿主 slot；workflow 侧：revert PR |

## 预期效果

阶段 1~3 完成后，约 **5100~5400 / 6025 分钟（85%~90%）** 的 runner 占用离开宿主文件系统，宿主上 Go 编译链接 / `npm ci` / Vitest 产生的海量文件事件基本消失。fseventsd 看门狗（`com.konghai.fseventsd-watchdog`）继续保留，用来确认效果。

## 待决定

1. 阶段 2 是否接受 backend Sonar / Lint 不再分给 lemon-imac / umacbook-pro（二者只能选其一）。
2. `colima-ci` 的内存从哪里腾：缩 `colima-moo`、缩 `konghai` 的 `colima`，还是直接减宿主 slot。
3. 改 workflow 的 PR 由谁提（iCare-backend、iCare-frontend-mas、iCare-public-backend、iCare-Operations-backend，base 都是 `develop`）。
