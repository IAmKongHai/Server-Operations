---
artifact_contract: "ce-handoff/v1"
created_at: "2026-08-24T03:00:22Z"
title: "iCare mobile + Operations: auto-cut to release, then build from release"
summary: "Mobile 构建源不统一（preview 已 snapshot 到 release，生产/Promote 仍绑 main，OTA 默认 develop）；用户要求改为自动 cut/tag/同步 release 再构建。Operations 双侧还没有 cut，但 UAT 部署已经在听 v* tag。"
keywords: ["icare-mobile-app", "icare-operations", "uat-cut", "release-branch", "protect-release", "eas-build", "cyp-1923", "cyp-2163"]
cwd: "/Users/konghai/Code/Project/Server"
resume_focus: "在代码仓落地：iCare-mobile-app 改为自动 cut/tag/同步 release 并用 release 构建；iCare-Operations-backend/frontend 按 MAS/public 配自动 cut。"
repository: "Server"
repo_root_sha: "105e22b22e8936b9788d571dd0dd845a4cf8424d"
branch: "main"
head: "6e407c4eeae6f98bbdc1211c22f9e1d6e5bb9ee4"
---

# Handoff：mobile 构建改走 release + Operations 配自动 cut

接收端：到 **代码仓** 开新 session 做，不在本运维笔记仓改 workflow。本文件只提供已核实的现状、用户决定、对照实现和坑。

## 用户决定（原话口径，不是 agent 推断）

1. `iCare-mobile-app` **确实需要**改为：自动 cut、自动 tag、自动同步 `release`，**然后用 `release` 分支构建**。
2. `iCare-Operations-backend` / `iCare-Operations-frontend`：参考其它仓，配置自动 cut。
3. 本 session 只落盘 handoff；实现去代码仓。

## 当前客观：mobile-app 现在用哪个分支构建？

**没有统一源。** 按 workflow：

| Workflow | 触发 | 检出 / 构建源 | 备注 |
|----------|------|----------------|------|
| `EAS Preview Local (mac-mini)` `.github/workflows/eas-build-preview-local.yml` | `workflow_dispatch` | **先把 `source_branch`（默认 `develop`）merge 进 `origin/release` 并直推，打 annotated tag `YYYY-MM-DD.NN`（无 `v` 前缀），再 `checkout` 该 tag 做 `eas build --local`** | 文件头写明：Actions 里跑的 YAML 来自你选的分支（常是默认分支 `main`），**app 总是从刚打到 release 上的 snapshot 构建**。这是仓内已有的「弱 cut」：无 PR、不等 CI。 |
| `EAS Production Build` `.github/workflows/eas-build-prod.yml` | `workflow_dispatch` | `actions/checkout@v4` **无 `ref`** → 检出 **你在 Actions 里选的那条分支**。默认分支是 `main` | 生产 EAS 云构建实际绑 **main**（或操作者随手选的 ref），**不是 release**。 |
| `EAS QA Build` `.github/workflows/eas-build-qa.yml` | `release: published` 或 dispatch | 发布事件则是 **`v*` GitHub Release 对应 commit**；手动则同样无 `ref`，跟 dispatch 分支 | `v*` 来自 `New App Version`（semver + `np`），和 preview 的 `YYYY-MM-DD.NN` 是两套。 |
| `New App Version` `.github/workflows/new-app-version.yml` | dispatch | checkout 无 `ref` → 默认 **main** 上 bump `package.json` 并推 `v*` tag | 会触发 `New GitHub Release`（只匹配 `v*`）。 |
| `Publish Production Mobile Release` `.github/workflows/activate-production-release.yml` | dispatch + `release_tag` | **强制 tag 必须是 `origin/main` 的 ancestor**，然后 detached checkout 该 tag | 生产 Promote 明确绑 **main**，不是 release。 |
| `OTA Publish JS` `.github/workflows/ota-publish-js.yml` | dispatch | 默认 `source_branch: develop` | 热更默认 **develop**。 |

近期 tag 形态（`gh api .../tags`）：`2026-08-22.01` 这类 preview snapshot，以及更早的 `preview-20260818-*`。MAS/public 用的是 `v2026-08-24.01`。`new-github-release.yml` 只匹配 `v*`，就是为了避免 preview tag 误触发 EAS QA 云构建。

`release` 分支是活的（2026-08-22 与 develop #243 同一 merge commit），但 **没有 Protect release、没有以 release 为 base 的 PR**；代码是直推/快进上去的。

## 本 session 已做完（运维仓 / GitHub ruleset，不要在代码仓重做）

- 诊断 public-backend CI job `97292060347`：不是 runner，是 UAT cut 秒合后 `refs/pull/196/merge` 消失。
- 根因：`uat-cut-tag.sh` 只看 `mergeStateStatus=CLEAN`；public 仓没有 Protect release。MAS 有。
- 已在 GitHub 创建：
  - `iCare-public-backend` Protect release `id=21262059`（`SonarQube Scan` + `test-lint-build`）
  - `iCare-public-frontend` Protect release `id=21262058`（`SonarQube Scan` + `verify`）
- org 扫描：同类秒合空门 **仍开着的是 `iCare-mobile-app`**（`main`/`release` 无 required checks）。Operations 目前无 `release` 分支，但 `develop`+`main` 检查一致。
- 复盘文档（运维仓）：`docs/solutions/best-practices/public-portal-release-unprotected-uat-cut-skips-checks-2026-08-24.md`
- 术语：运维仓 `CONCEPTS.md` → `Protect release`

## 目标形状（对照，不要发明第三套）

权威抄本：

- MAS：`cypressoai/iCare-backend` `.github/workflows/uat-cut-tag.yml` + `.github/scripts/uat-cut-tag.sh` + `docs/runbooks/uat-cut-tag.md`（CYP-1923）
- 公网门户：`cypressoai/iCare-public-backend` 同名文件（CYP-2163；脚本只看 CLEAN，所以 **目标分支必须有 Protect release**）

共同行为：

1. `workflow_dispatch` 单入口；secret **`UAT_CUT_TOKEN`**（Contents + PRs + Metadata，不要 Checks；**不要用默认 `GITHUB_TOKEN` 推 tag**，否则下游 `on: push tags` 不触发）
2. 保证 `origin/release` 存在；缺则从 develop 自举
3. 开 PR：`develop` → `release`（merge commit，保留 release hotfix）
4. 等到 `mergeStateStatus=CLEAN`（= 目标分支 required checks 绿）再 merge
5. 双侧同名 annotated tag `vYYYY-MM-DD.NN`（Asia/Shanghai，NN 取 max+1）打在 **release tip**
6. 现有 `on: push tags: v*` 部署接棒
7. 不部署、不做 release→develop 回流；hotfix 用 `skip_develop_sync`

MAS 脚本仍读 `statusCheckRollup`；public 因 CYP-2186 去掉了。新仓跟 public：只看 CLEAN + 先配 Protect release。

## Track A — `iCare-mobile-app`（代码仓做）

用户要的是 cut/tag/同步 release，然后 **构建改走 release**。现状已经有一半「preview 内部 cut」，缺的是正规门禁和把生产/OTA/Promote 从 main/develop 拧过来。

建议顺序（一条路径，不是多选）：

1. **先补 GitHub ruleset**（否则 cut 会重演 public #196：秒合、Sonar 空跑）。develop 已有 `CI Quality` + `SonarQube Scan`。给 **`release` 和 `main`** 同样两项；禁止直推、必须走 PR、审核数 0（token 才能自动合）。`main` 仍是默认分支（Actions 侧边栏可见性，见 PR #235），即使构建改走 release 也不要让 main 变无门。
2. **独立 cut workflow**，不要继续把 merge+tag 埋在 `eas-build-preview-local.yml` 的 `prepare` 里（那是 ubuntu-latest + 默认 GITHUB_TOKEN 直推 release）。对齐 MAS：PR 等 CI、`UAT_CUT_TOKEN`、annotated tag。单仓，不必 dual-repo。
3. **tag 格式要拍板**（用户未指定；agent 建议对齐 MAS `vYYYY-MM-DD.NN`，预览/生产共用 cut）。必须同时改 `new-github-release.yml` 的 `v*` 和 `eas-build-qa.yml` 的 `release: published`，避免 cut 的 tag 误开 GitHub Release / 误触 EAS QA 云构建。现状 preview tag **没有** `v` 前缀，就是为了躲这两条。
4. **构建入口改 checkout**：
   - Preview local：`prepare` 不再自己 merge/push release；cut 完成后再 dispatch/needs tag；`ref` 用 cut 的 tag 或 `release`。
   - `eas-build-prod.yml`：显式 `ref: release` 或 cut 的 tag，不要依赖 Actions 当前选中的默认 `main`。
   - `activate-production-release.yml`：把「tag 必须是 `origin/main` ancestor」改成 **`origin/release`**。
   - `ota-publish-js.yml`：默认 `source_branch` 从 `develop` 改为 `release`（或 tag）。
5. 直推 `release` 的路径关掉之后，develop #243 那种「合入 develop 后同 SHA 出现在 release」必须改成 cut PR。

不要重做：preview 的 mac-mini runner 约定（`mobile-preview-ci` / `mac-mini-mobile-1`）——运维仓 `docs/runbooks/ci-runner-pools.md`。

## Track B — `iCare-Operations-backend` + `iCare-Operations-frontend`（代码仓做）

这两个仓 **比 mobile 更接近 public 门户抄作业**。

已有：

- `develop` + `main` 均 Protect，检查与 develop 对齐（BE：`SonarQube Scan` + `test-lint-build`；FE：`SonarQube Scan` + `verify`）
- **没有 `release` 分支、没有任何 tag**
- CI `on.pull_request.branches` 已含 `develop, main, release`（注释还写着 CYP-2163 freeze line，是从 public 抄的）
- UAT 部署 **已经在听 `v*`**：
  - BE `.github/workflows/build-azure-uat-images.yml` `on.push.tags: v*`
  - FE `.github/workflows/deploy-azure-uat.yml` `on.push.tags: v*`
- 没有 `uat-cut-tag.yml` / 没有 `UAT_CUT_TOKEN`

缺的就是：自举 `release`、Protect release、cut 脚本、token、第一次 cut 打出 `v*`。部署 workflow 不用从零写。

必须先于第一次 cut 做的 GitHub 配置（否则 CLEAN 立刻成立，秒合）：

- Protect release，检查名与本仓 develop 相同（不要抄 MAS 的 `Lint` / `Frontend Tests`）
- `UAT_CUT_TOKEN` 覆盖这两个 Operations 仓（可复用 MAS/public 那枚 PAT，但要加 repository access）

Dual-repo 入口放哪：MAS/public 都把 cut 放在 **backend** 仓。Operations 应对齐：workflow 放 `iCare-Operations-backend`，脚本同步 FE。

Operations 的 `main` 已保护。产品上 UAT 冻结线在 MAS/public 是 `release` 不是 `main`。Cut 应打 **release**，让现有 `v*` 部署从 release tip 取代码（`actions/checkout@v4` 在 tag push 时检出的就是该 tag）。不要改成往 main 上打 tag，除非用户以后改口。

## 坑（下一 session 很容易重踩）

- **没有 Protect release 就上 cut** = public #196：6 秒合入，后续 Sonar checkout `couldn't find remote ref refs/pull/N/merge`。
- Fine-grained PAT **不能**授 Checks；不要读 `statusCheckRollup`（CYP-2186）。
- `GITHUB_TOKEN` push 的 tag **不会**触发 `on: push` 下游。
- mobile 现有三套 tag：`YYYY-MM-DD.NN`、`preview-*`、`v*`（semver）。混用会点着 QA 云构建。
- mobile `activate-production-release` 今天硬编码 main ancestor，只改 cut 不改这一步，生产 Promote 会拒绝 release 上的 tag。
- Operations CI 已监听 `release`，但分支不存在；一创建就有 PR CI，记得 ruleset 和 check **名字**对得上（BE `test-lint-build`，FE `verify`）。
- public 仓 `main` 无保护但已停更；不要在这次范围里顺手改 public。

## 权威指针

- MAS cut：`iCare-backend` `.github/workflows/uat-cut-tag.yml`（header 说明 secret / 不做部署）、`.github/scripts/uat-cut-tag.sh`（`merge_pr_when_ready`、`next_version`、dual tag）
- Public cut：`iCare-public-backend` 同路径；runbook 仍写「Protect **develop** 把门」——那是错的，release 才是 cut 目标。
- mobile preview 弱 cut：`iCare-mobile-app` `.github/workflows/eas-build-preview-local.yml` 第 1–15 行注释 + `prepare` job（直推 `HEAD:release`）
- mobile 生产绑 main：`.github/workflows/eas-build-prod.yml` checkout；`.github/workflows/activate-production-release.yml`「Verify tag is in main」
- Operations 已有 v* 部署：`iCare-Operations-backend/.github/workflows/build-azure-uat-images.yml`；`iCare-Operations-frontend/.github/workflows/deploy-azure-uat.yml`
- 运维复盘：本仓 `docs/solutions/best-practices/public-portal-release-unprotected-uat-cut-skips-checks-2026-08-24.md`（含 org 扫描表）
- runner 池：本仓 `docs/runbooks/ci-runner-pools.md`（mobile-preview-ci 不要和 sonar 池混标签）

## 建议下一 session 怎么走

在对应代码仓、base **`develop`** 开 PR（iCare 活跃分支不是 main）。先 Operations（抄 public 即可），再 mobile（要处理 tag 格式和生产绑 main 的迁移）。GitHub ruleset 可在进 cut 脚本前用 `gh api` 配，不必等 PR 合入。

本文件在运维仓 `docs/handoffs/`；实现 commit 打到 `iCare-mobile-app` / `iCare-Operations-*`，不要打回本仓。
