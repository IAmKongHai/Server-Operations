---
title: 改动 .env 任意一行会触发所有 env_file 引用方 service recreate
date: 2026-05-28
category: docs/solutions/dev-cypresso/integration-issues
server: dev-cypresso
module: dev-cypresso / docker-compose 共享 infra 栈
problem_type: integration_issue
component: tooling
symptoms:
  - "只想改 redis 一处配置，`docker-compose up -d` 却把同栈内其他 service（postgres、rabbitmq 等）也 Recreate 了"
  - "`docker inspect <other-service> --format '{{.State.StartedAt}}'` 显示时间戳跳到本次 up 时刻，与原本预期"不重启它"不符"
  - "排查 yaml diff 显示自己只动了一个 service 段，却产生跨 service 影响"
root_cause: config_error
resolution_type: workflow_improvement
severity: medium
tags: [docker-compose, env-file, recreate, config-hash, dev-cypresso, infra]
---

# 改动 .env 任意一行会触发所有 env_file 引用方 service recreate

## Problem
在 `/home/ec2-user/stacks/infra/docker-compose.yml` 这种"多 service 共享一份 .env"的编排里，删除或新增 `.env` 中的任一行——即使该行只跟某一个 service 有关——都会让**所有以 `env_file: .env` 方式引用它的 service** 的 compose config-hash 发生变化，下一次 `docker-compose up -d` 因此对那些"看似无关"的 service 也执行 `stop → rm → create → start` 序列。如果同栈内还有 `unless-stopped` 但当前处于 `Exited` 的容器，本次 `up -d` 还会顺手把它们一起拉起，违反运维者"我只是改了 redis 一件事"的心智预期。

## Symptoms
- 改 `infra/.env` 删除 `REDIS_PASSWORD=...` 一行，预期只 recreate `shared-redis`，实际 `shared-postgres`、`shared-rabbitmq`、`sonarqube` 也都进入 Recreate 流程
- 之前用 `docker stop` 主动停掉的 `shared-mongodb` / `shared-clickhouse` / `shared-rabbitmq` / `sonarqube` 在 `up -d` 后**被一起拉起**（restart policy 是 `unless-stopped`，compose 视它们为 yaml 声明态的合法成员）
- `docker inspect shared-postgres --format '{{.State.StartedAt}}'` 在 `up -d` 后变成最新时间，而 `shared-sqlserver`（**没用 env_file: .env**，直接 `environment:` 内联）保持 10 天前的 StartedAt

## What Didn't Work
- 仔细比对 yaml diff 试图找到自己改了哪个 service 段——diff 显示只动了 redis service，但实际副作用范围更大。yaml diff 视角是错的，应该看 **`docker-compose config` 渲染后的整 service 块**：compose 会把 `env_file` 展开成 inline `environment`，所以引用方在渲染后的全文都不同了，hash 自然也不同。
- 想"只 recreate 一个 service"用 `docker-compose up -d shared-redis` 来限定范围——确实能跳过其他 service，但这是**绕过**而非理解 hash 行为，且当还需要同步起新 service（如本次的 `shared-azurite`）时这一招就失效。

## Solution
两个层面的应对，按"事后兜底"和"事前规避"分开：

**事后兜底 — 副作用发生后的 4 步检查清单**
1. 立刻 `docker ps` 看哪些容器进入了 Up 状态，与预期对比
2. 对每个**意外**被拉起的容器，回查 `docs/operations/<server>.md` 看它历史上是不是被主动 `stop` 过；如果是，立刻 `docker stop <name>` 恢复到 Exited
3. 对每个**被 Recreate 但应保持运行**的 service，确认它 healthcheck 通过后继续；命名卷不丢就 OK，数据完整性不受影响
4. 在运维记录里**显式写明** "X 个 service 被意外 recreate / 拉起、原因是 env_file hash 变化"，避免未来回看以为是 bug

**事前规避 — 编排层的防御**
- 真正"只属于一个 service"的环境变量，**用 inline `environment:` 而不是 `env_file:`**。例如本案 redis 改造后已经把 `REDIS_PASSWORD` 从 environment 段彻底删除，未来再加 redis 专属变量直接写在 redis service 的 `environment:` 下，不要回 `.env`
- 必须共享的环境变量（比如多个 service 都要连同一个数据库）才走 `env_file: .env`
- 在 yaml 文件头部用注释明确这条约定，让下一个运维者一眼看到

**针对意外拉起的 Exited 容器：要长期阻止某 service 自动重启，正确做法不是 `docker stop`，而是从 yaml 里删除 / 注释 service 定义**。`docker stop` 只是改变当前进程状态，对 compose 视角的"yaml 声明应有此 service"没有任何影响。

## Why This Works
docker-compose 用 **config-hash** 决定 `up -d` 时是否 recreate 容器。这个 hash 是基于**渲染后的最终 service spec**（也就是 `docker-compose config` 输出里的那个 service 块）计算的。`env_file:` 字段在渲染时会被展开成 `environment:` 的 key-value，所以 `.env` 任何一行的变化都会让所有引用方的渲染结果不同——hash 自然变。

更进一步，`docker-compose up -d` 的语义是"使所有 yaml 里声明的 service 达到运行态"。它会忽略容器**当前**的 Exited 状态（无论是 `docker stop` 还是上次崩溃造成），只看 yaml 是不是写了这个 service。所以"我已经 stop 它了"和"我希望它别启动"在 compose 视角里不是同一件事。

## Prevention
1. **Yaml 编排注释约定** — 在 `docker-compose.yml` 头部、`.env` 头部都加一行注释说明"本 .env 被多个 service 共享，改动会触发跨 service recreate；service 专属变量请用 inline environment"
2. **每次 `up -d` 前先 dry run** — 习惯先跑 `docker-compose config | head` 或 `docker-compose up -d --dry-run`（compose v2 支持），把意图与最终渲染结果对照
3. **`StartedAt` 旁观快照** — 改 yaml 之前先抓一份 `docker inspect <旁观容器> --format '{{.Name}} StartedAt={{.State.StartedAt}}'`，up -d 后再抓一份对比，副作用一眼可见
4. **stopped 容器的长期处置写入 yaml** — 想要永久不自动拉起的 service，要么从 yaml 里删 / 注释、要么把 `restart` 改成 `no`，单纯 `docker stop` 不能持续生效；本仓库 `docs/operations/dev-cypresso.md` 2026-05-19 09:42 那条记录"已 stop 的 4 个迁出容器"在 2026-05-28 因为本次 `up -d` 全部被拉起，就是这个教训的反面教材
5. **运维记录写明意外副作用** — 在 `docs/operations/<server>.md` 的影响段不只写"我做了什么"，也写"它额外做了什么"，让未来 audit 不需要靠 `docker ps` 反推

## Related Issues
- 同栈记录：`docs/operations/dev-cypresso.md` 2026-05-28 15:24 "shared-redis 移除 requirepass + shared-azurite 上线（含 env 改动副作用）"——本案的原始发现现场
- 旁路问题：`docs/solutions/dev-cypresso/integration-issues/docker-image-buildup-fills-disk-2026-05-14.md`——同台机器 docker 层另一个治本/治标教训，与本案无直接因果关系但同属 dev-cypresso docker 编排经验
- 上下游：`docs/plans/2026-05-28-001-feat-dev-cypresso-icare-worker-rollout-plan.md`——本案出自该计划 U2 实施过程
