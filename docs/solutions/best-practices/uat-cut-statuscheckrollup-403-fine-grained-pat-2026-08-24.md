---
title: Fine-grained PAT 读 statusCheckRollup，MAS UAT cut 在等 CI 时 403
date: 2026-08-24
last_updated: 2026-08-24
applies_when:
  - UAT cut 脚本用 gh pr view 读取 GraphQL statusCheckRollup
  - UAT_CUT_TOKEN 是 fine-grained PAT（无法授予 Checks）
  - Protect release 已存在，mergeStateStatus=CLEAN 本身就能等 required checks
category: docs/solutions/best-practices
server: (适用 iCare-backend / iCare-frontend-mas UAT Cut Tag)
module: iCare MAS / UAT Cut Tag / GitHub PAT
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "UAT Cut Tag 在 Run UAT cut 失败：GraphQL Resource not accessible by personal access token (repository.pullRequest.statusCheckRollup)"
  - "第一次轮询 checks:[] 成功，sync PR 出现 Check run 后第二次轮询立刻 403"
  - "clone / 开 PR / token 读仓都成功，不是 runner 故障"
root_cause: missing_permission
resolution_type: code_fix
severity: high
tags:
  - uat-cut
  - cyp-2186
  - cyp-1923
  - fine-grained-pat
  - statuscheckrollup
  - icare-backend
---

# Fine-grained PAT 读 statusCheckRollup，MAS UAT cut 在等 CI 时 403

## 现象

`iCare-backend` UAT Cut Tag [run 32718244629](https://github.com/cypressoai/iCare-backend/actions/runs/32718244629/job/97409057176) 跑在 `mac-mini-sonar-2`。工具检查、clone、开 sync PR [#1615](https://github.com/cypressoai/iCare-backend/pull/1615) 都成功。`merge_pr_when_ready` 第一次轮询：

```text
attempt 1/120: {"checks":[],"mergeStateStatus":"UNKNOWN","state":"OPEN"}
```

约 33 秒后：

```text
GraphQL: Resource not accessible by personal access token
(repository.pullRequest.statusCheckRollup.nodes.0.commit.statusCheckRollup)
```

同日稍早的「成功」run 是 `DRY_RUN=true`，根本不进等 PR 循环。

不是 runner，也不是 CYP-2299 业务代码没过门（#1615 随后 Lint / Sonar 全绿，`CLEAN`）。

## 根因

`UAT_CUT_TOKEN` 于 2026-08-24 03:41 UTC 换成 fine-grained PAT。Fine-grained PAT **不能**授 Checks（CYP-2186）；GitHub 只把这项留给 GitHub App，classic PAT 的 `repo` scope 也能读。

MAS `.github/scripts/uat-cut-tag.sh` 的 `merge_pr_when_ready` 仍 `gh pr view --json state,mergeStateStatus,statusCheckRollup`。`checks:[]` 时字段为空能过；一旦 PR 上有 check 节点，GraphQL 嵌套 `commit.statusCheckRollup` 就 403。

public-portal 脚本因 CYP-2186 已经只看 `mergeStateStatus`。MAS Protect release 一直在（BE：`SonarQube Scan` + `Lint`；FE：`Frontend Tests` + `SonarQube Scan` + `Typecheck`），所以 **不必** Checks 权限：`CLEAN` 仍然等于 required checks 绿。

## 解决

对齐 public CYP-2163：只轮询 `state` + `mergeStateStatus`，`CLEAN` / `HAS_HOOKS` 才 `gh pr merge --merge --delete-branch`。CI 红了表现为一直 `BLOCKED`，直到 60 分钟超时。

改动在 `iCare-backend`（cut 入口仓，FE 没有单独脚本）：

- PR：[cypressoai/iCare-backend#1616](https://github.com/cypressoai/iCare-backend/pull/1616)
- 文件：`.github/scripts/uat-cut-tag.sh`、`docs/runbooks/uat-cut-tag.md`
- **不要**改 workflow YAML、secret 名、runner labels
- **不要**给 token 加 Checks，也不要退回 classic PAT 迁就旧脚本

Cut 跑的是 dispatch 所选 ref 上的脚本，所以必须先合 #1616 进 `develop` 再重跑 UAT Cut Tag。

### 半成品 cut

失败时已开 [#1615](https://github.com/cypressoai/iCare-backend/pull/1615)（`v2026-08-24.05` 没打成；BE 停在 `.04`，FE 停在 `.03`）。重跑前先合掉或关掉 #1615，否则会再开一条 sync PR。#1615 合入后重跑会 skip backend sync，再打双侧 tag。

### 回滚

还原 #1616 的脚本后，fine-grained token 会再次 403。只有换成 classic PAT / GitHub App 才能让旧查询活过来。

## 不要误判成

- `mac-mini-sonar-*` 磁盘 / DNS / gh 未安装（clone 和开 PR 都成功）
- 业务代码没过质量门（#1615 checks 随后全绿）
- Protect release 缺失导致秒合（那是 public #196；本次是读 Checks 被拒，不是秒合）
