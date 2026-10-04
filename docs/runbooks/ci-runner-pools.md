# GitHub Actions self-hosted runner 池（cypressoai）

> 最后更新：2026-10-05
> 目标：按**任务重量**分层共享池，提高 PR CI 吞吐；部署机不接质量门禁；runner 侧减流量 + 护磁盘。

## 池定义

| 逻辑池 | Label | 成员机器 | 承接 job | 明确不接 |
|--------|-------|----------|----------|----------|
| 前端测试分片 | `frontend-tests-ci` | mac-mini、lemon-imac、umacbook-pro | Frontend Tests 1–4/4 | Coverage、完整 Sonar、Docker 部署 |
| 前端质量 | `frontend-quality-ci` | 上表 Mac + mas-go-dev-ci-1/2 | Lint、Typecheck、Frontend Tests 汇总、**PR** SonarQube Scan | Coverage、完整 branch Sonar、生产 Docker 部署 |
| 前端重活 | `mac-mini-sonar`（+ `macos`,`arm64`） | **仅** mac-mini | Frontend Coverage、完整 Branch Sonar、deploy quality-gate、Verify MAS UAT static bundle | — |
| 后端质量 | `backend-ci` | mac-mini、lemon-imac、umacbook-pro、mas-go-dev-ci | 后端 Lint / Build and Test / Sonar | Docker 镜像 build-push 到 GHCR（仍走 dev-cypresso） |
| 现网/集成部署构建 | `dev-cypresso-ci` | **仅** dev-cypresso | set-vars、Build and Push、Deploy to Server（前后端）；EVP 生产 `workflow_dispatch`（`deploy-prod.yml`） | 任何 Lint / Sonar / Tests |
| mas-go-dev 本机部署 | `mas-go-dev` | **仅** mas-go-dev 部署 runner | Deploy to mas-go-dev（前后端） | 质量门禁（质量用 `mas-go-dev-ci`） |
| 非 iCare SIT 本机部署 | `shared-sit` / runner group `shared-sit` | **仅** mas-go-dev 上的 `shared-sit` runner | EVP 等非 iCare 项目部署到 `/opt/evp-sit` 等 | 质量门禁、iCare 仓库、`mas-go-dev` label |
| Azure UAT | `azure` / runner group `icare-2-uat` | icare-2-uat-runner、**icare-2-uat-runner-2**（CYP-2263 burst） | Deploy MAS to Azure UAT、UAT 镜像构建 / mirror | 日常 PR CI |
| 会员端 preview 本机构建 | `mobile-preview-ci` | **仅** `mac-mini-mobile-1` | iCare-mobile-app preview `eas build --local`（Android APK / iOS IPA，串行） | 质量门、backend CI、EAS 云构建、production、AcquiLang Native |
| AcquiLang 日常 CI | `acquilang-ci`（+ `macos`,`arm64`） | **仅** `mac-mini-acquilang-ci-1`（仓库级，`IAmKongHai/AcquiLangAI`） | backend / admin / native 类型检查 / web / Sonar / CI 汇总，单 slot 排队 | 原生打包、其它仓库 |
| AcquiLang Native 本机构建 | `acquilang-native-ci` | **仅** `mac-mini-acquilang-native-1`（仓库级，`IAmKongHai/AcquiLangAI`） | AcquiLangAI `eas build --local`（iOS IPA / Android AAB，串行）后 `eas submit` | iCare 质量门、iCare preview、org 内其它仓 |

历史标签 `frontend-sonar-ci` 仍保留在部分 runner 上便于回滚；**新 workflow 应使用 `frontend-quality-ci`（PR）与 `mac-mini-sonar`（full）**。

## 机器与 runner 快照（2026-08-25）

| Runner name | 主机 | 关键 labels（含默认） |
|-------------|------|---------------------|
| `mac-mini-sonar-1..4` | mac-mini（10 核 / 32GB） | **`self-hosted`**, `mac-mini-sonar`, `macos`, `arm64`, `frontend-tests-ci`, `frontend-quality-ci`, `frontend-sonar-ci`, `backend-ci`。2026-08-19 曾停 3/4；**2026-08-25 已恢复四 slot 在线** |
| `mac-mini-mobile-1` | mac-mini | **`self-hosted`**, `macos`, `arm64`, `macos-arm64`, `mac-mini`, **`mobile-preview-ci`**（**无** sonar / quality / backend 标签）。宿主须有 Homebrew `azure-cli`（`/opt/homebrew/bin/az`），供日后 OTA JS 直传 Azure Blob；现网 workflow 仍走 GitHub artifact + `ubuntu-latest` upload，见 [mac-mini-runner-start-stop.md](./mac-mini-runner-start-stop.md) |
| `mac-mini-acquilang-native-1` | mac-mini | **`self-hosted`**, `macOS`, `ARM64`, `macos-arm64`, **`acquilang-native-ci`**（**无** `mac-mini` / sonar / quality / `konghai-friends-lab`） |
| `mac-mini-acquilang-ci-1` | mac-mini | **`self-hosted`**, `macOS`, `ARM64`, **`acquilang-ci`**；新增于 2026-09-15，日常 CI 独立 slot |
| `lemon-imac-1/2` | lemon-imac（8 核 / 8GB） | **`self-hosted`**, `frontend-tests-ci`, `frontend-quality-ci`, `backend-ci`, `lemon-imac`, … |
| `umacbook-pro-1/2` | umacbook-pro（8 核 / 8GB） | **`self-hosted`**, `frontend-tests-ci`, `frontend-quality-ci`, `backend-ci`, `umacbook-pro`, … |
| `mas-go-dev` | mas-go-dev | `mas-go-dev`, `docker`, `al2023`（**无** quality/tests 标签）；组 `mas-go-dev` |
| `mas-go-dev-ci-1/2` | mas-go-dev | **`self-hosted`**, `mas-go-dev-ci`, `frontend-quality-ci`, `backend-ci`, （ci-1 另有 `docker`）；组 `mas-go-dev` |
| `shared-sit` | mas-go-dev | **`self-hosted`**, `Linux`, `X64`, `docker`, `al2023`, **`shared-sit`**（**无** quality/tests / `mas-go-dev` 标签）；组 `shared-sit`，selected repo 目前仅 `cypressoai/evp` |
| `ip-172-31-42-99.ec2.internal` | dev-cypresso | `dev-cypresso-ci`（**仅**部署） |
| `ip-172-31-42-99.ec2.internal-2` | dev-cypresso | 默认 Linux labels，不进专用池 |
| `icare-2-uat-runner` | UAT VM `icare-2-uat-ci-runner`（`ssh icare-uat-runner-1`，兼容 `icare-uat-runner`） | `azure`, `uat` |
| `icare-2-uat-runner-2` | UAT burst VM `icare-2-uat-ci-runner-2`（`ssh icare-uat-runner-2`，CYP-2263 D8s_v5） | `azure`, `uat`；**必须**预建 `/var/cache/buildx` 属主 `icareadmin` |
| `icare-2-uat-wait` | 原 UAT VM `icare-uat-runner-1` 上的 wait slot（`/opt/actions-runner-uat-wait`） | `uat-wait`（**不要**进 group `icare-2-uat`；Default pool） |

**调度硬匹配提醒**：workflow 写 `runs-on: [self-hosted, backend-ci]` 时，runner **必须同时**有 `self-hosted` 与 `backend-ci`。注册时若用了 `--no-default-labels` 会丢掉 `self-hosted`，表现为「有 `backend-ci` 却永远接不到 job」。2026-08-05 已给 mac-mini 四 slot 补回 `self-hosted`（见 `docs/operations/mac-mini.md`）。

`runs-on: [self-hosted, mac-mini]` 会命中 iCare 的 `mac-mini-mobile-1`（它带 `mac-mini` 标签）。AcquiLang Native 必须写 `[self-hosted, macos, arm64, acquilang-native-ci]`。

**组 visibility 同样硬匹配**：label 对上但仓库不在该 runner group 的 selected 名单里，job 会一直 `queued`、runner 空闲。`mas-go-dev` 组（id 3）里是 `mas-go-dev` 部署 runner + `mas-go-dev-ci-1/2`。2026-09-09 已把 `cypressoai/evp` 加进该组，否则 EVP 的 `Linux + docker + backend-ci` job 永远没人接（唯一匹配者是 `mas-go-dev-ci-1`）。2026-10-05 已把 `cypressoai/moo-ticket` 加进该组，原因相同。SIT 部署仍走 `shared-sit` 组。EVP / moo-ticket workflow **不要**写裸 `docker` / 不要贴 `mas-go-dev` label，避免抢部署 runner。

## 仓库 workflow 对照

### `iCare-frontend-mas`

| Job | Label |
|-----|-------|
| Frontend Tests shards | `frontend-tests-ci` + `macos` + `arm64` |
| Frontend Tests 汇总 | `frontend-quality-ci` |
| Typecheck / Lint | `frontend-quality-ci` |
| SonarQube Scan（PR） | `frontend-quality-ci` |
| SonarQube Scan（branch + coverage） | `mac-mini-sonar` + `macos` + `arm64` |
| Frontend Coverage | `mac-mini-sonar` + `macos` + `arm64` |
| Deploy quality-gate | `mac-mini-sonar` + `macos` + `arm64` |
| Verify MAS UAT static bundle | `mac-mini-sonar` + `macos` + `arm64` |
| set-vars / build-push / Deploy to Server | `dev-cypresso-ci` |
| Deploy to mas-go-dev | `mas-go-dev` |
| Deploy MAS to Azure UAT | wait：`uat-wait`；deploy：runner group `icare-2-uat` |

### `iCare-backend`

| Job | Label |
|-----|-------|
| Lint / SonarQube / Build and Test | `backend-ci` |
| set-vars / build-push / Deploy to Server | `dev-cypresso-ci` |
| Deploy to mas-go-dev | `mas-go-dev` |
| Build Azure UAT Images / Migrate then roll | runner group `icare-2-uat` |

### `evp`

| Job | Label / group |
|-----|----------------|
| Checks frontend lint/build | `[self-hosted, frontend-quality-ci]` |
| Checks backend 测试（含临时 Postgres） | `[self-hosted, Linux, docker, backend-ci]`（当前只有 `mas-go-dev-ci-1`；不要占宿主机 5432） |
| Checks 镜像构建 | 同上；串行四镜像，不要用 `shared-sit` / `mas-go-dev` 部署 runner |
| SonarQube Scan（backend） | `[self-hosted, backend-ci]`（可达 `http://mac-mini:9000`） |
| SonarQube Scan（frontend） | `[self-hosted, frontend-quality-ci]`（PR 快扫，不含覆盖率） |
| Deploy SIT | runner group `shared-sit` + labels `self-hosted, Linux, X64, shared-sit`（`mas-go-dev` 上的 `shared-sit`） |
| Deploy production | **仅** `workflow_dispatch`；`[self-hosted, Linux, X64, dev-cypresso-ci]`（dev-cypresso 本机）。不要用 `shared-sit` / `mas-go-dev` |

### `moo-ticket`

| Job | Label / group |
|-----|----------------|
| CI backend（临时 Postgres、`go test -race`、CLI） | `[self-hosted, Linux, docker, backend-ci]`（当前只有 `mas-go-dev-ci-1`；`docker run -p 127.0.0.1::5432`，不要占宿主机 5432） |
| CI frontend（npm lint / test / tsc / build） | `[self-hosted, frontend-quality-ci]` |
| CI image（`docker build`） | 与 backend 相同的 Linux + docker 标签 |
| CI 汇总（分支保护要求的 `CI` check） | `[self-hosted, backend-ci]` |
| Deploy to dev-cypresso | `[self-hosted, Linux, X64, dev-cypresso-ci]` |

仓库需在 runner group `mas-go-dev`（id 3）的 selected 名单里，backend / image 才会有人接。Deploy 走 Default 组的 `dev-cypresso-ci`，不进 `mas-go-dev` 部署 runner。

## 容量注意

- **8GB 机**（lemon / umacbook / mas-go-dev）：适合轻中质量活与测试分片；**禁止**挂完整 Coverage / 全量 branch Sonar。
- 同机多 runner **不增加** CPU/内存，只增加抢占；8GB 机若 Vitest 与 Sonar 同时打满可考虑减 slot 或降 `VITEST_MAX_WORKERS`。
- umacbook-pro 为个人本：合盖/断网会掉线，只作吞吐扩容，不当唯一关键路径。**2026-09-01 起带到学校，`umacbook-pro-1/2` 已 disable+bootout（保留 Tailscale，未注销 GitHub）；回来用 `umacbook-pro-runner-resume.sh`。**
- lemon / umacbook 的 Go 由 job 内 `setup-go` 安装；本机 login PATH 可能没有 `go`/`node`，属正常。

## 上线 checklist（贴 `backend-ci` / `frontend-quality-ci` 前）

共享池 label = **能力承诺**。未达标不要贴 label；也不要在业务仓 workflow 里用 `skipSignatureVerification: true` 迁就缺工具的 runner。

Sonar Scanner CLI（`SonarSource/sonarqube-scan-action` 默认）会做 GPG 签名校验；任意承接 Sonar 的 self-hosted runner 必须满足：

| 检查项 | macOS | Linux（AL2023 等） |
|--------|-------|-------------------|
| 完整 GnuPG | `brew install gnupg` → `gpg` + `dirmngr` | 完整 `gnupg2`（不要只用 `gnupg2-minimal`） |
| runner service PATH 可见 gpg | 各 slot `.path` **含** `/opt/homebrew/bin`（SSH login shell 有 brew ≠ service 有） | `.path` 含 `/usr/bin`（通常默认已有） |
| 短 workFolder（macOS） | `.runner` 的 `workFolder` 用短路径（如 `~/gha/u1`），避免 `GNUPGHOME` socket `File name too long` | 一般无此限制 |
| CGO / 编译器（backend） | Xcode CLT / `gcc` 可用 | `gcc` + glibc-devel（或 job 内可 `sudo dnf install`） |
| 验证 | 对 **Runner.Listener 真实 PATH** 执行 `command -v gpg`；可选 `gpg --recv-keys` 拉 SonarSource 公钥 | 同左 |

验证示例（在目标机上）：

```bash
# 用 runner 目录 .path，而不是交互 shell PATH
export PATH="$(cat ~/actions-runner/<slot>/.path)"
command -v gpg && gpg --version | head -1
command -v dirmngr

# 重启 service 后核对进程环境
pid=$(pgrep -f "actions-runner/<slot>/bin/Runner.Listener" | head -1)
ps eww -p "$pid" | tr ' ' '\n' | grep '^PATH='
```

相关历史：

- mac-mini PATH / 短 workFolder：`docs/solutions/mac-mini/integration-issues/sonarqube-scanner-cli-cache-never-hits-4part-version-2026-06-09.md`
- mas-go-dev `gnupg2-minimal` 缺 dirmngr：`docs/solutions/mas-go-dev/integration-issues/sonar-scan-fails-no-dirmngr-on-x86-runner-2026-06-10.md`
- 2026-07-20 lemon / umacbook 补齐 gnupg + `.path`：见各机 `docs/operations/*.md`

### golangci-lint（backend-ci）

self-hosted **不要**依赖 `golangci/golangci-lint-action` 的默认行为：

- 默认会走 **GitHub Cache API** 拉/推 analyzer cache（跨境/代理下可 0.1MB/s 级卡死，甚至拖满 `timeout-minutes`）
- 默认 `verify: true` 会访问 `golangci-lint.run` 拉 jsonschema，网络抖即硬失败

推荐与 `iCare-backend` 一致：`go install` 固定版本 + `golangci-lint run`；本机 `~/.cache/golangci-lint` 已跨 job 持久。  
取证与修复：`docs/solutions/mas-go-dev/workflow-issues/golangci-lint-action-cache-timeout-selfhosted-2026-08-04.md`；`iCare-public-backend` PR #62。

### 缓存基线（减公网流量 / 防 CYP-322）

self-hosted **优先**本机 store；workflow 侧 `setup-go cache: true` / `setup-node cache: pnpm` 仍可能走 GitHub Cache API（占公网）。runner `.env` 的本机路径在 store 命中后可显著少拉 registry。

| 缓存 | 策略 | 注入位置 |
|------|------|----------|
| `GOCACHE` | **每 slot 独立目录**（同机 multi-slot 必须） | 各 runner `.env`（Linux 另见 systemd `EnvironmentFile`） |
| `GOMODCACHE` | **每主机共享一份** | 各 runner `.env` 指向同一路径 |
| `PNPM_STORE_PATH` | **每主机共享一份**（frontend-quality / 会跑 JS 的 CI slot） | 各 **CI** runner `.env`；**不要**写到纯部署 runner |
| coverage GOCACHE | **job-local**：`${{ runner.temp }}/go-build-cover` + 同目录侧 `TMPDIR=.../go-tmp` | workflow step `env`；**不**写持久 slot |
| npm | 默认 `~/.npm`；有 `PNPM_STORE_PATH` 时 pnpm 优先本机 store | home + `.env` |
| tool-cache | 每 slot `workFolder/_tool`（setup-go/node/sonar 自动） | **不可共享**；日常维护**不要**整盘 `rm _tool` |
| 修剪策略 | 见下节「定时维护」 | `scripts/gha-runner-maintenance.sh` + `scripts/prune-gocache.sh` |

**为何 coverage 必须 job-local：** 全量 `-covermode=atomic -coverpkg=./cmd/...,./internal/...` 为插桩变体单独建 cache key，对象大且随每个 commit 追加；Go 默认约 5 天未用才 trim，高频 CI 下持久 GOCACHE 会涨到数十 GB/slot（见 2026-07 lemon/umac/mas 盘满复盘）。

**贴 label 前额外确认：**

```bash
# .env 应含（路径按主机调整）
grep -E 'GOCACHE|GOMODCACHE|PNPM_STORE' ~/actions-runner/<slot>/.env
# multi-slot：GOCACHE 必须不同，GOMODCACHE / PNPM_STORE 应相同

# 无 Worker 时修剪（2 天 + 体积门槛）
# mac：
./scripts/prune-gocache.sh ~/actions-runner/<slot>/cache/go-build
# 删迁移前 orphan（runner 已改 per-slot 后）：
rm -rf ~/Library/Caches/go-build
# mas-go-dev：
sudo -u actions-runner bash -lc './scripts/prune-gocache.sh /opt/actions-runner/mas-go-dev-ci-N/cache/go-build'
# Linux：确认 Listener 进程环境（systemd EnvironmentFile 后）
pid=$(pgrep -f 'mas-go-dev-ci-1/bin/Runner.Listener' | head -1)
sudo strings /proc/$pid/environ | grep -E 'GOCACHE|GOMODCACHE|PNPM'
```

参考计划：`docs/plans/2026-07-20-001-ops-ci-runner-cache-baseline-plan.md`；Jira **CYP-1547**（parent CYP-853）。

当前主机约定（2026-08-03 加固后）：

| 主机 | GOCACHE | GOMODCACHE | PNPM_STORE_PATH |
|------|---------|------------|-----------------|
| mac-mini slot N | `~/actions-runner/mac-mini-sonar-N/cache/go-build` | `~/gha/cache/go-mod` | `~/gha/cache/pnpm-store` |
| lemon-imac slot N | `~/actions-runner/lemon-imac-N/cache/go-build` | `~/go/pkg/mod` | `~/gha/cache/pnpm-store` |
| umacbook-pro slot N | `~/actions-runner/umacbook-pro-N/cache/go-build` | `~/go/pkg/mod` | `~/gha/cache/pnpm-store` |
| mas-go-dev-ci-N | `/opt/actions-runner/<name>/cache/go-build` | `/home/actions-runner/go/pkg/mod` | `/var/cache/gha/pnpm-store` |
| mas-go-dev（部署） | `/opt/actions-runner/mas-go-dev/cache/go-build` | 同上 | **不设**（避免与质量门混用） |
| dev-cypresso（部署） | — | — | **不设**；只清 `_work`，保留 `/var/cache/buildx` |

### 定时维护（2026-08-03）

| 主机 | 调度 | 动作 |
|------|------|------|
| mac-mini | crontab 03:15 日 / 周日 04:30 | `~/gha/scripts/gha-runner-maintenance.sh` |
| lemon-imac | LaunchDaemon 03:25 / 周日 04:45（crontab TCC 不可用；2026-08-19 由 LaunchAgent 改来，注销后仍调度） | 同上 |
| umacbook-pro | LaunchDaemon 03:20 / 周日 04:40（2026-08-19 由 crontab+LaunchAgent 改来，注销后仍调度；MAX_GB=15） | 同上 |
| mas-go-dev | systemd timer 03:15 / 周日 04:30 UTC | `/opt/gha-scripts/...`；含 CI + 部署 work |
| dev-cypresso | systemd timer 03:50 UTC | **仅** work 清理，不碰 buildx / 质量 store |

维护脚本会：清过期 `_temp` 与 stale 仓库 work 目录；**保留** `_tool` / `_actions`；按 2 天 mtime + 体积门槛修剪 GOCACHE；weekly 可选 `pnpm store prune` / 超 cap 的 `go clean -modcache`。有 `Runner.Worker` 时跳过破坏性 prune。

### 并发建议

- 同物理机 N 个 slot = N 倍 `_work` + 出口流量；8GB 机（lemon / umacbook）**1～2 slot** 已足够质量门。
- mac-mini 10 核 / 32GB 可保留 4 slot（重活 + 分片），但仍受磁盘峰值约束。2026-08-19 曾停 3/4 给本机 Multica 留并发；**2026-08-25 已恢复四 slot**。高峰时 CI 会再和 Multica / Colima 抢核。
- **不要**为减流量去清空整个 `_tool`（Sonar Scanner / setup-go 会重新大流量下载）。

## 标签运维命令

```bash
# 查看
gh api orgs/cypressoai/actions/runners --paginate \
  --jq '.runners[] | "\(.id)\t\(.name)\t\([.labels[].name] | sort | join(", "))"'

# 追加 label（不替换既有）
gh api -X POST orgs/cypressoai/actions/runners/<id>/labels \
  -f 'labels[]=frontend-quality-ci'

# 删除 label
gh api -X DELETE orgs/cypressoai/actions/runners/<id>/labels/frontend-quality-ci
```

## 相关变更

- mac-mini 四 slot 启停 / 定时恢复（**禁止用 `at`**）：[`mac-mini-runner-start-stop.md`](./mac-mini-runner-start-stop.md)；取证 `docs/solutions/mac-mini/workflow-issues/macos-at-disabled-do-not-schedule-runner-resume-with-at-2026-07-28.md`
- 前端 workflow：`cypressoai/iCare-frontend-mas` PR #1185
- 后端注释：`cypressoai/iCare-backend` PR #1083
- 2026-07-20 org 侧 label 扩容（见各机 `docs/operations/*.md` 时间线）
- 2026-07-20 lemon-imac / umacbook-pro 补齐 gnupg + runner `.path`；backend 去掉 `skipSignatureVerification`（runner 基线修复，非 workflow 旁路）
- 2026-07-20 四机缓存基线：per-slot `GOCACHE`、共享 `GOMODCACHE`、mas 清 ~128G go-build；计划 `docs/plans/2026-07-20-001-ops-ci-runner-cache-baseline-plan.md`；backend PR #1094
- 2026-08-03 CI 池加固：共享 `PNPM_STORE_PATH`、日/周维护脚本（work + go-build + store prune）、mas/dev-cypresso systemd timer、lemon LaunchAgent（见各机 `docs/operations/*.md`）；仓库 `scripts/gha-runner-maintenance.sh`
- 2026-08-19 lemon-imac runner + 维护任务改为 LaunchDaemon（注销图形用户后仍在线）；不要再 `./svc.sh install`。见 `docs/runbooks/lemon-imac-runner-start-stop.md`、`docs/operations/lemon-imac.md`
- 2026-08-19 umacbook-pro 同样改为 LaunchDaemon；原 crontab 已删避免双跑。见 `docs/runbooks/umacbook-pro-runner-start-stop.md`
- 2026-09-01 umacbook-pro 带到学校：pause 脚本 `disable`+`bootout` 两 slot 与维护任务，清 GOCACHE / work / modcache；Tailscale 仍在。见 `docs/operations/umacbook-pro.md`
