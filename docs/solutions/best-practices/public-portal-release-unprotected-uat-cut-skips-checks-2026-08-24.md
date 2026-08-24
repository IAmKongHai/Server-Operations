---
title: 公网门户 release 未设 required checks，UAT cut 秒合跳过 Sonar
date: 2026-08-24
last_updated: 2026-08-24
applies_when:
  - 仓库有 develop/release/main 冻结线，CI 会跑，但 ruleset 只保护了其中一条
  - UAT cut / 同步 PR 只看 mergeStateStatus=CLEAN
  - 新仓抄了 CYP-2163 的 CI `on.branches` 但没抄 Protect release
category: docs/solutions/best-practices
server: (适用 iCare-public-backend / iCare-public-frontend)
module: iCare public portal / GitHub rulesets / UAT Cut Tag
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "UAT cut 的 develop→release PR 开出后 5–6 秒就被 merge，Sonar 还没开始"
  - "随后 SonarQube Scan 在 Checkout Code 失败：fatal: couldn't find remote ref refs/pull/N/merge"
  - "脚本注释写着等 mergeStateStatus=CLEAN（等同 required checks），实际完全不等 CI"
root_cause: incomplete_setup
resolution_type: config_change
severity: high
tags:
  - github-ruleset
  - uat-cut
  - cyp-2163
  - sonar
  - release
  - icare-public-backend
  - icare-public-frontend
---

# 公网门户 release 未设 required checks，UAT cut 秒合跳过 Sonar

## 现象

`iCare-public-backend` UAT cut 开出 develop→release PR 后几乎立刻合入，后面的 `SonarQube Scan` 变成空跑，并在 checkout 挂掉。

取证：

- PR [#196](https://github.com/cypressoai/iCare-public-backend/pull/196) `01:07:09Z` 打开，`01:07:15Z` 已 merged（6 秒）
- 同 run 的 `test-lint-build` 在 `lemon-imac-2` 通过；`SonarQube Scan` 因 `needs` 拖到 `01:10:27Z` 才在 `mac-mini-sonar-1` 开始
- Checkout：`fatal: couldn't find remote ref refs/pull/196/merge`（PR 合入后 GitHub 会删这个 ref）
- 最近一批 public 仓 UAT cut PR 全是 5–6 秒合入；对照同日 MAS backend [#1601](https://github.com/cypressoai/iCare-backend/pull/1601) 等了约 8.5 分钟

不是 runner 故障，也不是业务代码。

## 根因

`uat-cut-tag.sh` 的 `merge_pr_when_ready` **只**看 `mergeStateStatus=CLEAN`。`UAT_CUT_TOKEN` 没有 Checks 权限，不能读 `statusCheckRollup`（CYP-2186）。这套代理只有在目标分支挂了 required status checks 时才等于「等 CI」。

CYP-2163 从 MAS CYP-1923 抄了脚本和「等 CI 绿后自动 merge」的口径，但 **没抄 `Protect release` ruleset**：

| 仓库 | Protect develop | Protect release（补齐前） |
|------|-----------------|---------------------------|
| `iCare-backend` | 有 | 有（`SonarQube Scan` + `Lint`） |
| `iCare-frontend-mas` | 有 | 有（`Frontend Tests` + `SonarQube Scan` + `Typecheck`） |
| `iCare-public-backend` | 有（`SonarQube Scan` + `test-lint-build`） | **无** |
| `iCare-public-frontend` | 有（`SonarQube Scan` + `verify`） | **无** |

`release` 不受保护时 GitHub 认为没有要等的检查，`CLEAN` 立即成立，脚本第一轮就 `gh pr merge`。

## 解决

按各仓 **develop 的 required checks** 补 `Protect release`（结构对齐 MAS，check 名对齐本仓 develop）：

| 仓库 | ruleset | required checks |
|------|---------|-----------------|
| `iCare-public-backend` | [Protect release](https://github.com/cypressoai/iCare-public-backend/rules/21262059) `id=21262059` | `SonarQube Scan` + `test-lint-build`（GitHub Actions `integration_id=15368`） |
| `iCare-public-frontend` | [Protect release](https://github.com/cypressoai/iCare-public-frontend/rules/21262058) `id=21262058` | `SonarQube Scan` + `verify`（同上） |

其它参数与 develop / MAS 一致：禁止删分支、禁止 force-push、必须走 PR、审核数 0（cut token 才能自动合）、`strict_required_status_checks_policy: false`、无 bypass。

脚本和 token **不用改**。`mergeStateStatus` 会停在 `BLOCKED`，直到上述 checks 绿。副作用：hotfix 进 `release` 也被同一道门拦住，这与 MAS 相同。

### 回滚

```bash
gh api --method DELETE repos/cypressoai/iCare-public-backend/rulesets/21262059
gh api --method DELETE repos/cypressoai/iCare-public-frontend/rulesets/21262058
```

删除后 UAT cut 会重新在秒级合入，Sonar 再次失去门禁意义。

## 验证

- `GET .../rules/branches/release` 两侧都返回 `required_status_checks`，check 名与上表一致
- 下次正式 UAT cut：sync PR 应停数分钟（等 CI），不应再 5 秒合入；Sonar checkout 时 PR 仍开着，`refs/pull/N/merge` 还在

## 其它 iCare 仓排查（2026-08-24）

判据：有没有自动/人工秒合进冻结线、冻结线有没有 required checks、CI 会不会在合入后再跑。

| 仓库 | 冻结线 | 自动 cut | 结论 |
|------|--------|----------|------|
| `iCare-backend` / `iCare-frontend-mas` | `release` 有 Protect release；检查与 develop 对齐 | 有（CYP-1923；[#1616](https://github.com/cypressoai/iCare-backend/pull/1616) 起只看 CLEAN，对齐 CYP-2186） | **不是本条秒合问题**。token 换成 fine-grained 后旧脚本读 `statusCheckRollup` 会 403，见 `uat-cut-statuscheckrollup-403-fine-grained-pat-2026-08-24.md` |
| `iCare-public-backend` / `iCare-public-frontend` | 已补 Protect release | 有（CYP-2163，只看 CLEAN） | **本条已修** |
| `iCare-Operations-backend` / `frontend` | 无 `release`；`develop`+`main` 检查一致 | 无 | **无此问题**。注意 CI `on.branches` 已含 `release`，一旦建该分支且不补 ruleset 会重演 |
| **`iCare-mobile-app`** | 有活跃 `release`+`main`；**只** Protect develop（`CI Quality`+`SonarQube Scan`） | 无脚本，但是人工秒合 | **同型问题，仍在** |
| `iCare` root | 非 develop 全冻结（不能推） | 无 | 不是质量门问题 |
| `iCare-terraform` | 只有 develop | 无 | 无此问题 |
| `iCare-frontend-fraud` / `iCare-devDB` / `iCare-Pencil-design` | 无 ruleset | 无 | 无 UAT cut，不在本条范围 |

`iCare-mobile-app` 证据：

- CI 明确跑 `[develop, release, main]`，ruleset 注释写着 `CI Quality` 是 required check，但 **只挂在 develop**
- [`#202`](https://github.com/cypressoai/iCare-mobile-app/pull/202) develop→main：开 PR 到 merge **9 秒**；`CI Quality` 合入后 4 分钟才绿，`SonarQube Scan` **失败**
- `release` 无任何 ruleset、无以它为 base 的 PR；develop #243 合入后同 commit 出现在 `release` 上，等于直推/快进，完全不经 Sonar

若要堵：按 develop 的 `CI Quality` + `SonarQube Scan` 给 **`main` 和 `release` 各补一条** Protect ruleset（禁止直推、必须走 PR）。`main` 是默认分支（Actions 侧边栏可见性），`release` 是生产壳/热更冻结线，两边都会跑 CI，不保护则 Sonar 仍是空跑。

次要不一致（不是秒合空门，只是门比 develop 窄）：

- `iCare-backend` Protect main 只要 `SonarQube Scan`，没有 develop/release 的 `Lint`
- `iCare-frontend-mas` Protect main 没有 develop/release 的 `Typecheck`
- 两个 public 仓的 `main` 无保护，但已停更（backend 停在 2026-07-13，frontend 仍是 init）

## 不要误判成

- `mac-mini-sonar-*` 或 git 网络故障（fetch 能连 GitHub，只是 merge ref 已被删）
- 业务代码没过质量门（同 run 的 `test-lint-build` 已绿）
- 脚本忘了 sleep（循环在，但 `CLEAN` 在无 ruleset 时是空门）
