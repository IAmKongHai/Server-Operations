---
title: 公网门户 release 未设 required checks，UAT cut 秒合跳过 Sonar
date: 2026-08-24
last_updated: 2026-08-24
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

## 不要误判成

- `mac-mini-sonar-*` 或 git 网络故障（fetch 能连 GitHub，只是 merge ref 已被删）
- 业务代码没过质量门（同 run 的 `test-lint-build` 已绿）
- 脚本忘了 sleep（循环在，但 `CLEAN` 在无 ruleset 时是空门）
