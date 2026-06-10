---
title: frontend-mas Vitest 在 mac-mini self-hosted runner 上用 sharding + 低 worker 数降耗时
date: 2026-06-11
category: docs/solutions/mac-mini/performance-issues
server: mac-mini
module: iCare-frontend-mas / GitHub Actions Frontend Tests
problem_type: performance_issue
component: testing_framework
severity: medium
symptoms:
  - "GitHub Actions `Frontend Tests` job 长期接近 9 分钟，主要耗时在 Vitest jsdom 测试"
  - "单纯提高 `--maxWorkers` 到 6 或 8 会引发测试报错，不能作为稳定加速方案"
  - "`pool: 'vmThreads'` 在 sharding 后暴露 `crypto.subtle`、`window.location` 等全局状态/环境不稳定问题"
  - "`deps.optimizer.client` 与大量 `vi.mock('antd')` / `vi.importActual('antd')` 测试不兼容"
root_cause: config_error
resolution_type: config_change
related_components:
  - github-actions-self-hosted-runner
  - vitest
  - jsdom
  - antd
tags: [vitest, github-actions, sharding, mac-mini, self-hosted-runner, frontend-mas, maxworkers, jsdom]
---

# frontend-mas Vitest 在 mac-mini self-hosted runner 上用 sharding + 低 worker 数降耗时

## Problem

`iCare-frontend-mas` 的 PR CI 中，`Frontend Tests` 长期是慢步骤。初始 run `27292211369` 的 Vitest 主体约 9 分钟；把 `--maxWorkers` 提高到 4 并加 `vmThreads` 后，run `27295505735` 仍约 9 分钟量级，收益不明显。

目标是在不牺牲 CI 稳定性的前提下降低前端测试墙钟时间。

## Symptoms

- `npm ci` 只占十几秒，慢点集中在 `vitest run`。
- 测试套件大量使用 jsdom、Ant Design、`@ant-design/*`、React Testing Library，import 和 DOM environment 成本高。
- 直接提高单 job 的 `--maxWorkers` 到 6 或 8 会引发报错；在 mac-mini 同机 4 个 runner 并发时，继续提高每个 job 的 worker 数会放大 CPU / 内存争用。
- `pool: 'vmThreads'` 的实验在 run `27298087872` 中导致 4 个 shard 里 3 个失败，典型错误包括：

```text
TypeError: Cannot read properties of undefined (reading 'digest')
TypeError: Cannot redefine property: location
```

- `deps.optimizer.client` 的实验在本地稳定复现失败，典型错误为：

```text
Error: There is a new version of the pre-bundle for .../deps/antd.js&v=...
Cannot find module '/node_modules/antd/lib/index.js&v=...'
```

## What Didn't Work

- **只提高 `--maxWorkers`**：`--maxWorkers=4` 对单 job 有一定帮助，但在 4 个 runner / 4 个 shard 同机并发时，`4 shards × 4 workers = 16` 个 Vitest worker 会超过 mac-mini 的稳定并发承载。`--maxWorkers=6/8` 更不稳定。
- **`pool: 'vmThreads'`**：理论上比 forks 轻，但 Vitest 4 下 `vmThreads` 对 jsdom/global isolation 更敏感。sharding 改变文件分组后，`crypto.subtle`、`window.location` 等全局环境问题被放大。该项应撤回，保留默认 forks pool。
- **`deps.optimizer.client`**：官方建议可减少 jsdom/happy-dom 外部依赖 import 开销，但本项目很多测试会 partial mock `antd`：

```ts
vi.mock('antd', async () => {
  const actual = await vi.importActual<typeof import('antd')>('antd')
  return { ...actual, App: ... }
})
```

开启 client optimizer 后，`antd` 实际导入被改写到 optimized dep 路径并带 `&v=` 查询串，Vitest mock 阶段失败。尝试移除 `antd` include、添加 `exclude: ['antd']`、清理 `node_modules/.vite/vitest` 后仍失败，因此不适合直接上。

- **把纯逻辑测试迁到 node environment**：本地小样本显示 91 个纯逻辑候选文件从 `40.95s` 降到 `14.30s`，但需要通过命名约定或 Vitest projects 长期治理，否则逐文件加 `// @vitest-environment node` 成本高且容易遗漏。当前收益相对 5 分钟级 CI 不够大，暂不做。

## Solution

最终保留的稳定方案是：

1. **Frontend Tests 做 4-way Vitest sharding**。
2. **每个 shard 的 Vitest worker 限制为 2**。
3. **撤回 `pool: 'vmThreads'`，继续使用默认 forks pool**。
4. **保留 `--silent=passed-only`，降低成功测试日志量**。

前端仓关键配置形态：

```json
{
  "scripts": {
    "test:ci": "vitest run --reporter=dot --silent=passed-only --maxWorkers=2 --testTimeout=30000"
  }
}
```

GitHub Actions 侧用 matrix 拆分：

```yaml
frontend-tests-shards:
  name: Frontend Tests ${{ matrix.shard }}/4
  strategy:
    fail-fast: false
    matrix:
      shard: [1, 2, 3, 4]
  steps:
    - run: npm run test:ci -- --shard=${{ matrix.shard }}/4

frontend-tests:
  name: Frontend Tests
  needs: frontend-tests-shards
```

聚合 job 保留原来的 `Frontend Tests` 名称，方便分支保护规则继续绑定一个稳定检查名。

实测结果：

- run `27298087872`：4 shard + `vmThreads`，3 个 shard 失败。
- run `27299225012`：撤回 `vmThreads` 后，剩 1 个 shard 因 UI 交互测试偶发失败；命令仍为 `--maxWorkers=4`。
- run `27300088076`：`--maxWorkers=2` 后全部通过，`Frontend Tests` 降到 `5m44s`。

## Why This Works

mac-mini 上的 `mac-mini-sonar-1..4` 是 4 个独立 GitHub Actions runner slot，同一台物理机最多可同时接 4 个 job。若每个 job 内部再开太多 Vitest worker，实际并发是：

```text
总并发 worker = shard/job 数 × 每个 job 的 --maxWorkers
```

因此：

- `4 shards × 4 workers = 16 workers`，容易把 mac-mini 推到 CPU / 内存 / swap 争用，jsdom + Ant Design UI 测试更容易 timing flaky。
- `4 shards × 2 workers = 8 workers`，并发仍能利用多 runner 横向拆分，但不会把单机压到不稳定。

sharding 的收益来自横向缩短墙钟时间；低 `maxWorkers` 的收益来自控制同机最坏并发。两者要一起考虑，不能只看单 job worker 数。

`vmThreads` 和 `deps.optimizer.client` 都是理论上的 import/setup 优化，但本项目测试大量依赖 jsdom 全局对象、`vi.mock('antd')`、`vi.importActual('antd')`。这些优化改变模块隔离或依赖解析路径后，稳定性成本高于性能收益。

## Prevention

- 优化 self-hosted runner 上的 Vitest 性能时，先算“同机总 worker 数”，不要只看单个 job 的 `--maxWorkers`。
- 对单台机器多个 runner slot 的场景，优先用 `shard` 控制墙钟时间，再用较低 `maxWorkers` 控制每个 shard 的资源峰值。
- `vmThreads`、dependency optimizer 这类低层优化必须先用 PR / 本地失败文件验证，不能直接合入主线。
- 对大量 `vi.mock('antd')` 的项目，不要盲开 `deps.optimizer.client` include `antd`；这会影响 `vi.importActual('antd')` 的解析路径。
- 如果未来要继续压缩几十秒级耗时，再考虑制定 `*.node.test.ts` 命名约定 + Vitest projects，把纯逻辑测试迁到 node environment；不要逐文件靠人工加环境文件头。

## Related Issues

- `docs/operations/mac-mini.md` 2026-06-10 17:05：确认 mac-mini 4 个 runner slot 并发和 `--maxWorkers` 最坏并发关系。
- `docs/operations/mac-mini.md` 2026-06-10 17:20 / 17:49：曾尝试单 runner 串行化，后因 CI 队列积压恢复 4 runner 并发。
- `docs/solutions/mac-mini/integration-issues/sonarqube-scanner-cli-cache-never-hits-4part-version-2026-06-09.md`：同一批 `mac-mini-sonar-*` runner 的环境和 slot-local cache 背景。
