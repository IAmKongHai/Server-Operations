# GitHub Actions self-hosted runner 池（cypressoai）

> 最后更新：2026-07-20  
> 目标：按**任务重量**分层共享池，提高 PR CI 吞吐；部署机不接质量门禁。

## 池定义

| 逻辑池 | Label | 成员机器 | 承接 job | 明确不接 |
|--------|-------|----------|----------|----------|
| 前端测试分片 | `frontend-tests-ci` | mac-mini、lemon-imac、umacbook-pro | Frontend Tests 1–4/4 | Coverage、完整 Sonar、Docker 部署 |
| 前端质量 | `frontend-quality-ci` | 上表 Mac + mas-go-dev-ci-1/2 | Lint、Typecheck、Frontend Tests 汇总、**PR** SonarQube Scan | Coverage、完整 branch Sonar、生产 Docker 部署 |
| 前端重活 | `mac-mini-sonar`（+ `macos`,`arm64`） | **仅** mac-mini | Frontend Coverage、完整 Branch Sonar、deploy quality-gate、Verify MAS UAT static bundle | — |
| 后端质量 | `backend-ci` | mac-mini、lemon-imac、umacbook-pro、mas-go-dev-ci | 后端 Lint / Build and Test / Sonar | Docker 镜像 build-push 到 GHCR（仍走 dev-cypresso） |
| 现网/集成部署构建 | `dev-cypresso-ci` | **仅** dev-cypresso | set-vars、Build and Push、Deploy to Server（前后端） | 任何 Lint / Sonar / Tests |
| mas-go-dev 本机部署 | `mas-go-dev` | **仅** mas-go-dev 部署 runner | Deploy to mas-go-dev（前后端） | 质量门禁（质量用 `mas-go-dev-ci`） |
| Azure UAT | `azure` / runner group `icare-2-uat` | icare-2-uat-runner | Deploy MAS to Azure UAT、UAT 镜像 mirror | 日常 PR CI |

历史标签 `frontend-sonar-ci` 仍保留在部分 runner 上便于回滚；**新 workflow 应使用 `frontend-quality-ci`（PR）与 `mac-mini-sonar`（full）**。

## 机器与 runner 快照（2026-07-20）

| Runner name | 主机 | 关键自定义 labels |
|-------------|------|---------------------|
| `mac-mini-sonar-1..4` | mac-mini（10 核 / 32GB） | `mac-mini-sonar`, `macos`, `arm64`, `frontend-tests-ci`, `frontend-quality-ci`, `frontend-sonar-ci`, `backend-ci` |
| `lemon-imac-1/2` | lemon-imac（8 核 / 8GB） | `frontend-tests-ci`, `frontend-quality-ci`, `backend-ci`, `lemon-imac`, … |
| `umacbook-pro-1/2` | umacbook-pro（8 核 / 8GB） | `frontend-tests-ci`, `frontend-quality-ci`, `backend-ci`, `umacbook-pro`, … |
| `mas-go-dev` | mas-go-dev | `mas-go-dev`, `docker`, `al2023`（**无** quality/tests 标签） |
| `mas-go-dev-ci-1/2` | mas-go-dev | `mas-go-dev-ci`, `frontend-quality-ci`, `backend-ci`, （ci-1 另有 `docker`） |
| `ip-172-31-42-99.ec2.internal` | dev-cypresso | `dev-cypresso-ci`（**仅**部署） |
| `ip-172-31-42-99.ec2.internal-2` | dev-cypresso | 默认 Linux labels，不进专用池 |
| `icare-2-uat-runner` | UAT VM | `azure`, `uat` |

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
| Deploy MAS to Azure UAT | runner group `icare-2-uat` |

### `iCare-backend`

| Job | Label |
|-----|-------|
| Lint / SonarQube / Build and Test | `backend-ci` |
| set-vars / build-push / Deploy to Server | `dev-cypresso-ci` |
| Deploy to mas-go-dev | `mas-go-dev` |

## 容量注意

- **8GB 机**（lemon / umacbook / mas-go-dev）：适合轻中质量活与测试分片；**禁止**挂完整 Coverage / 全量 branch Sonar。
- 同机多 runner **不增加** CPU/内存，只增加抢占；8GB 机若 Vitest 与 Sonar 同时打满可考虑减 slot 或降 `VITEST_MAX_WORKERS`。
- umacbook-pro 为个人本：合盖/断网会掉线，只作吞吐扩容，不当唯一关键路径。
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

- 前端 workflow：`cypressoai/iCare-frontend-mas` PR #1185
- 后端注释：`cypressoai/iCare-backend` PR #1083
- 2026-07-20 org 侧 label 扩容（见各机 `docs/operations/*.md` 时间线）
- 2026-07-20 lemon-imac / umacbook-pro 补齐 gnupg + runner `.path`；backend 去掉 `skipSignatureVerification`（runner 基线修复，非 workflow 旁路）
