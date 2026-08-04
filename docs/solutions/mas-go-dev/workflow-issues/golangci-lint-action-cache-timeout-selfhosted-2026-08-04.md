---
title: "self-hosted 上不要用 golangci-lint-action 默认 cache/verify"
date: 2026-08-04
category: docs/solutions/mas-go-dev/workflow-issues
server: mas-go-dev
module: backend-ci / iCare-public-backend CI
problem_type: workflow_issue
component: tooling
severity: high
applies_when:
  - "self-hosted backend-ci 跑 golangci/golangci-lint-action@v8 默认配置"
  - "job 被 cancelled，annotation 写 exceeded maximum execution time"
  - "Lint 日志出现 Failed to restore: The operation cannot be completed in timeout"
  - "golangci-lint config verify 拉 golangci-lint.run jsonschema 报 context deadline exceeded"
tags:
  - github-actions
  - self-hosted-runner
  - golangci-lint
  - backend-ci
  - mas-go-dev
  - cache
---

# self-hosted 上不要用 golangci-lint-action 默认 cache/verify

## Context

`iCare-public-backend` CI job `test-lint-build`（label `self-hosted` + `backend-ci`）在

[actions/runs/30898768407/attempts/1](https://github.com/cypressoai/iCare-public-backend/actions/runs/30898768407/attempts/1)

上由 **`mas-go-dev-ci-1`** 执行，结论 **cancelled**。Annotation：

> The job has exceeded the maximum execution time of 20m0s

同期多条 PR/push CI 还因同一 action 的 `config verify` 联网失败而红。

## Symptoms

| 观察 | 细节 |
|------|------|
| Job 结论 | `cancelled`（非用户点取消、非 concurrency 抢占） |
| Annotation | `The job has exceeded the maximum execution time of 20m0s` |
| 有效工作很短 | Test ~77s；真正 `golangci-lint run` ~4s 且 0 issues |
| Cache restore | Cache hit 后 ~16MB 以 **0.1 MB/s** 卡住 → `Failed to restore: The operation cannot be completed in timeout`；prepare env **~113s** |
| 日志空档 | Lint endgroup（10:03:58Z）到 Build 起步（10:19:17Z）约 **15 分钟无日志** |
| Post Lint | 仍 `Saved cache` ~16MB，**~63s** |
| 其它失败形态 | `config verify` → `https://golangci-lint.run/jsonschema/golangci.v2.4.jsonschema.json` → `context deadline exceeded`（lemon / mas-go-dev / umac 均见） |

对照：同仓库成功 run 的 `test-lint-build` 通常 **2–4 分钟**（如 umac / lemon）。

## Root cause

`golangci/golangci-lint-action@v8` **默认**：

1. **`skip-cache: false`** — 经 **GitHub Cache API** 拉/推 analyzer cache。self-hosted 经代理/跨境时带宽极差或半开连接，restore 可卡满默认超时仍失败，post 还继续 save。
2. **`verify: true`** — `golangci-lint config verify` 运行时下载远程 JSON Schema；到 `golangci-lint.run` 超时即 **整 job 失败**（与业务代码无关）。
3. 与 `setup-go: cache: false` 的 self-hosted 策略不一致：Go 模块已走本机 `GOMODCACHE`，lint 却又绕回 GH cache。

本机 `~/.cache/golangci-lint` 在 self-hosted 上**跨 job 本来就持久**，GH cache 对 backend-ci 池几乎无收益、净增抖点。

15 分钟无日志空档在家宽 Tailscale 不可达时未能读 `_diag`；即使有 runner 侧卡顿，去掉 action 的 cache/verify 仍是正确解耦。

## Guidance

### 推荐（与 `iCare-backend` 对齐）

不要用 action 默认路径；按需安装固定版本后直接 CLI：

```yaml
- name: Add Go bin to PATH
  run: echo "$(go env GOPATH)/bin" >> "$GITHUB_PATH"

- name: Install golangci-lint
  env:
    GOLANGCI_LINT_VERSION: v2.4.0
  run: |
    if command -v golangci-lint >/dev/null 2>&1; then
      if golangci-lint version 2>/dev/null | grep -Fq "${GOLANGCI_LINT_VERSION#v}"; then
        echo "golangci-lint ${GOLANGCI_LINT_VERSION} already installed; skipping go install"
        exit 0
      fi
    fi
    go install "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@${GOLANGCI_LINT_VERSION}"

- name: Lint
  run: golangci-lint run ./...
```

### 若必须暂时保留 action

至少显式：

```yaml
- uses: golangci/golangci-lint-action@v8
  with:
    version: v2.4.0
    skip-cache: true
    skip-save-cache: true
    verify: false
```

### 禁止 / 避免

- self-hosted 池上依赖 **GH Cache API** 存 golangci analyzer cache（与「本机 store 优先」策略冲突）
- 默认 `verify: true` 且无离线 schema 兜底
- 仅靠抬高 `timeout-minutes` 掩盖网络抖（治标不治本）

## Fix status

| 项 | 状态 |
|----|------|
| Workflow 修复 PR | [iCare-public-backend#62](https://github.com/cypressoai/iCare-public-backend/pull/62) |
| 取证 run | `30898768407` attempt 1（`mas-go-dev-ci-1`） |
| attempt 2 | quality gate 约 2min 成功（`lemon-imac-1`）；Sonar **Quality Gate FAILED** 属规则门禁，非 runner 基础设施 |

## Related

- Runner 池与缓存基线：[`docs/runbooks/ci-runner-pools.md`](../../../runbooks/ci-runner-pools.md)
- 主机时间线：[`docs/operations/mas-go-dev.md`](../../../operations/mas-go-dev.md)
- 对照实现：`cypressoai/iCare-backend` `.github/workflows/sonar.yml`（Install + `golangci-lint run`，无 action）
