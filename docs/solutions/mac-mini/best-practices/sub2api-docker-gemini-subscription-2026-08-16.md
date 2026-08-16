---
title: 在 mac-mini 用 Colima 部署 Sub2API，并用订阅额度调用 Gemini 3.7 Flash
date: 2026-08-16
last_updated: 2026-08-16
category: docs/solutions/mac-mini/best-practices
server: mac-mini
module: mac-mini / Sub2API
problem_type: best_practice
component: tooling
severity: medium
applies_when:
  - 要在 mac-mini 的现有 Colima 上部署 Sub2API
  - 要用 Google AI Pro / Antigravity 订阅额度，而不是 Gemini Developer API 或 Vertex 按 token 计费
  - 客户端走 OpenAI 兼容的 /v1/chat/completions，目标模型是 Gemini 3.7 Flash
  - 看到 503 / 404 / 429 / All available accounts exhausted，需要先判断是路径、分组还是上游
tags: [mac-mini, sub2api, colima, docker-compose, antigravity, gemini, google-ai-pro, gemini-3.7-flash]
---

# 在 mac-mini 用 Colima 部署 Sub2API，并用订阅额度调用 Gemini 3.7 Flash

## Context

要在家里的 `mac-mini` 上自建 [Wei-Shaw/sub2api](https://github.com/Wei-Shaw/sub2api)，把 Google AI Pro / Antigravity 订阅收成 OpenAI 兼容的 `sk-` Key，给局域网客户端用。约束是：**不另付 Gemini Developer API / Vertex token 费**，只用订阅额度。

官方镜像 `weishaw/sub2api` 的 `0.1.177` 能跑通 2.5 Flash，但目录里没有 3.7 变体；3.7 Flash 实际走 Antigravity，且当前 daily 端点只认 `gemini-3.7-flash-tiered`。部署计划见 [2026-08-16-001-ops-mac-mini-sub2api-deploy-plan.md](../../../plans/2026-08-16-001-ops-mac-mini-sub2api-deploy-plan.md)，逐步操作见 [mac-mini 运维时间线](../../../operations/mac-mini.md)。

## Guidance

### 栈怎么放

- 引擎用现有 Colima（`vz` / 6 CPU / 12 GiB），不要再起一套 Lima / Docker Desktop。
- 目录跟本机惯例：mac-mini 上的 `~/stacks/sub2api`，数据在同级的 data、postgres_data、redis_data 卷。
- Postgres **自己带一小套**（`postgres:18-alpine` + `redis:8-alpine`）。不要挂到 `sonar-postgres` 或 `richer-postgres`。
- 宿主 `*:8080` 已被 `hon` 的 `colima-multica` SSH 转发占用，对外绑 **`0.0.0.0:18080`**。
- `RUN_MODE=standard`，管理员邮箱用部署时确定的那个。
- 官方 `.env.example` 的连接池是按独立 8G 机器写的，原样套到这台共享 Colima 会和 Sonar 抢内存；内存上限压到小几百 MiB 即可。
- 改配置前备份 compose / `.env`（`.env` 权限 600，不进 git）。只重建 `sub2api`，不要顺手动 Sonar / Grafana。

### 三种 Gemini「账号」不要混

| Sub2API 平台 / 类型 | 实际吃的额度 | 这台机器上能打到的模型 |
| --- | --- | --- |
| `antigravity` OAuth | Google AI Pro / Antigravity 订阅 | `gemini-2.5-flash`；3.7 用 `gemini-3.7-flash-tiered` |
| `gemini` + `oauth_type=google_one`（Code Assist） | Cloud AI Companion（`cloudaicompanion.googleapis.com`） | 实测只有 `gemini-2.5-flash` / `gemini-2.5-pro` |
| Gemini Developer API / Vertex `AIza` Key | **按 token 付费** | 不要为了 3.7 去开这条 |

给 GCP 项目启用 `cloudaicompanion.googleapis.com` 只是开门，**不是**控制台那张 $75/月企业包，也不是 Vertex 按量计费。启用后要把账号上残留的 `error` / `schedulable=false` 清掉，否则调度仍会跳过。

3.7 Flash 的订阅额度在 **Antigravity**，不在 Code Assist。Key 必须绑 `platform=antigravity` 的分组，组里要有可用的 Antigravity 账号。

Google 账号的**国家/地区不能是中国**。国家设成中国时，OAuth 能加上，调用会 403 `Validation required`，网关把账号标 `error` 并关掉调度。改国家是 Google 账号设置，不是 Sub2API 的 GCP Project ID。改完后在账号行末点 **恢复状态**，并打开 **参与调度**。

### 客户端怎么打

OpenAI 兼容客户端（ai-sdk / 医生助手等）的 `base_url` 是：

```text
http://mac-mini:18080/v1
```

局域网也可用 `http://192.168.2.170:18080/v1`。`model` 写成：

```text
gemini-3.7-flash-tiered
```

不要用 `http://mac-mini:18080/antigravity` 当 OpenAI `base_url`：那条前缀没有 `/antigravity/v1/chat/completions`，会 404。原生 Gemini 路径是 `/antigravity/v1beta/...` 或 `/antigravity/v1/messages`，和 OpenAI 兼容层不是一回事。

`/v1/models` 列出的是网关目录，不是上游真实可调用集合。目录有名字、上游 404，是正常现象。

### 3.7 要自打 PR，并切 daily 端点

官方 `0.1.177` 不认识 `gemini-3.7-flash-*`。需要 [PR #5640](https://github.com/Wei-Shaw/sub2api/pull/5640)（gemini 3.7 功能分支）。本机做法：

1. 在 mac-mini 取该 PR 分支，打 `linux/arm64` 镜像，例如 `sub2api:pr5640-3.7`。
2. compose `image:` 改成本地标签，只 `up -d sub2api`。
3. `.env` 加 `GATEWAY_ANTIGRAVITY_FORWARD_BASE_URL=daily`（家里出口已是美国时再开）。
4. 用 `-version` 确认字符串类似 `0.1.177-pr5640`，并确认容器里有 `daily`。

当前 daily 端点实测：

| 模型 | 结果 |
| --- | --- |
| `gemini-3.7-flash-tiered` | 200，订阅额度 |
| `gemini-3.7-flash` / `-high` / `-medium` / `-low` | 上游 404 `Requested entity was not found` |
| `gemini-2.5-flash` | 200（回归对照） |

`max_tokens` 太小（例如 16）时，3.7 可能 200 但 `content` 空、`finish_reason=length`（thinking 吃光额度）。客户端给到几百 token。

计费表可能还没收 `gemini-3.7-flash-tiered`（日志 `pricing not found`），不影响转发。

回滚：compose 的 image 改回官方 `weishaw/sub2api` 的 `0.1.177` 标签，或拷回 mac-mini 上换镜像前的 compose bak。

### 报错先这样读

| 表象 | 常见真因 |
| --- | --- |
| `503` / `No available accounts` | 分组空，或账号没进组 |
| `/antigravity` 404 | 把专用前缀当成了 OpenAI `base_url` |
| `All available accounts exhausted` | 网关把「候选全失败」翻成这句话，经常是上游 429，或账号被标了 `error` |
| 上游 403 `Validation required` | Google 要验证，或账号国家/地区是中国。不是缺 GCP Project ID |
| Grok 400 `include_server_side_tool_invocations` | Grok 同时带了 `web_search` 和其它 function。当前镜像把搜索当客户端 function，不再混 Gemini 内置搜索 |
| 上游 404 `Requested entity was not found` / `Resource not found` | 模型名上游不认。Code Assist 没有 3.7；Antigravity 上不要用基础名 |
| 后台「测试连接」404 | 它默认探 `gemini-2.0-flash`，可忽略 |

## Why This Matters

Sub2API 的 `/v1` 只是一层调度。账号类型、分组、上游端点、模型变体名四件事对不齐，就会在 503 / 404 / exhausted 之间打转，还容易误开付费 API。先认准「订阅额度在 Antigravity，客户端打 `/v1` + `gemini-3.7-flash-tiered`」，再动镜像和端点。

## When to Apply

- 在 `mac-mini` 上重装、升级或排查 Sub2API。
- 客户端要 Gemini 3.7 Flash，且明确只用订阅、不走付费 API。
- 升级官方镜像后 3.7 又 404：先看目录有没有变体名，再看上游是不是只认 `-tiered`。

## Examples

**错误：Code Assist 号 + 基础模型名**

```text
账号: gemini / google_one / project my-openclaw-super-xxk
Key 分组: Gemini
POST /v1/chat/completions  model=gemini-3.7-flash
→ 上游 404 Resource not found
```

**错误：Google 账号国家是中国**

```text
账号: antigravity OAuth，国家/地区 = 中国
→ 上游 403 Validation required；清 error 再打仍会 403
```

**错误：OpenAI 客户端打专用前缀**

```text
base_url=http://mac-mini:18080/antigravity
→ 404（没有 /antigravity/v1/chat/completions）
```

**正确：Antigravity 组 + 变体名**

```text
账号: antigravity OAuth（Google AI Pro）
Key 分组: antigravity
GATEWAY_ANTIGRAVITY_FORWARD_BASE_URL=daily
镜像: 含 PR #5640 的本地标签（官方 0.1.177 不够）
base_url=http://mac-mini:18080/v1
model=gemini-3.7-flash-tiered
→ 200，走订阅额度
```

## Related

- 部署计划：[2026-08-16-001-ops-mac-mini-sub2api-deploy-plan.md](../../../plans/2026-08-16-001-ops-mac-mini-sub2api-deploy-plan.md)
- 操作时间线：[mac-mini.md](../../../operations/mac-mini.md)
- 上游：[Wei-Shaw/sub2api](https://github.com/Wei-Shaw/sub2api)、[PR #5640](https://github.com/Wei-Shaw/sub2api/pull/5640)（截至 2026-08-16 未合入官方 `0.1.177`）
