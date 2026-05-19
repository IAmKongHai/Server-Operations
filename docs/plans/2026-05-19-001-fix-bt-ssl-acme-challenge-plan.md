---
title: 修复 nyh-prod 宝塔站点 SSL 续期挑战路由
type: fix
status: active
date: 2026-05-19
---

# 修复 nyh-prod 宝塔站点 SSL 续期挑战路由

## Summary

`nyh-prod` 上 7 个在用域名（acquilangai 及 ddricher/acquilangai 相关站点、`duowei.konghai.me`、`m.acquilangai.com`）的续期失败，核心因为 `/.well-known/acme-challenge/` 请求仍被主站业务入口吞掉。该计划目标是恢复挑战文件路由、让续期可自动通过，并把修复结果可回放地沉淀。

## Problem Frame

- 站点续期日志与现场探测显示，目标域名的 `well-known` include 文件为空或未生效，导致 HTTP-01 验证不再直接命中 ACME 处理逻辑。
- `/.well-known/acme-challenge/` 直接走到了业务层（返回 301 跳转到 404、Next.js 页面、API 404 或 502）。
- 当前排除的 3 个域名（`pgadmin.konghai.me`、`test-center.nanyahui.com`、`test-vip.nanyahui.cn`）本次不再修复。

## Requirements

- R1. 仅恢复并固定 7 个在用域名的 ACME-01 可达性，不修改其余 3 个废弃域名续签状态。
- R2. 对目标域名保证 `/.well-known/acme-challenge/` 不再被业务 `location ^~ /` 或其他应用级路由抢占。
- R3. 在不改动现有业务入口和高风险配置的前提下，恢复宝塔站点证书自动续期链路。
- R4. 续期可恢复后，输出可验证结果（证书到期时间更新、端口证书有效期一致、续期日志记录）。
- R5. 形成最小化操作记录，便于将来回放和责任审计。

## Scope Boundaries

- 本计划只处理 `nyh-prod` 的宝塔网站续期链路。
- 不改：
  - `pgadmin.konghai.me`
  - `test-center.nanyahui.com`
  - `test-vip.nanyahui.cn`
- 不处理：
  - 证书吊销、DNS 供应商迁移、全站 HTTPS 策略重构。
  - 既有业务代码与数据库结构。
- 不执行：大规模重启除 Nginx 外的服务。

### Deferred to Follow-Up Work

- 为其它已下线域名统一清理证书目录与站点绑定是否可用，需另起计划。
- 为所有站点补充周期化证书状态巡检脚本，作为长期运维自动化任务。

## Context & Research

- 先前只读核查已确认：7 个在用域名全部存在同类异常特征（HTTP 请求进入 404/502 分支）。
- 仅发现目标域名的 `well-known` include 文件存在但为空；该目录未提供可返回 token 的 ACME 内容。
- 该仓的既有实践中已有 `nyh-prod` 证书加载问题的处理经验，问题本质是“续签到磁盘但进程/配置未及时按新路径响应”。
- 关键约束：生产环境下操作应可回滚且不扩大影响面。

## Key Technical Decisions

- 采用“恢复现有宝塔标准 `well-known` include 模板”而非重写 location 规则，减少误伤。
- 保持 `/.well-known/acme-challenge` 处理最小化，只修复挑战请求入口，不改动业务主入口缓存、CORS、重定向等既有逻辑。
- 将修复动作分为“写配置 + 只重载 Nginx + 触发续期 + 验证 + 记录”，顺序固定，避免边改边验证导致状态不一致。
- 按“先回滚备份再变更”执行，确保单域名/全量回退可行。

## Open Questions

- 哪个域名在 7 个中先续期？
  - 决议：优先按到期时间倒序，先处理 `acquilangai.com` 与其管理/API 系列域名，再处理 `duowei.konghai.me`、`m.acquilangai.com`。
- 是否需要在此阶段立即加入巡检脚本？
  - 决议：本计划不包含新脚本，留在 Follow-Up。

## Implementation Units

### U1. 对 7 个目标域名恢复 ACME challenge include 内容

**Goal:** 把目标域名的 `well-known` include 从空文件恢复为可直接返回 challenge 的标准模板。

**Requirements:** R1, R2, R3

**Dependencies:** 无

**Files:**
- Modify: `docs/solutions/nyh-prod/integration-issues/baota-panel-stale-ssl-cert-in-memory-2026-05-11.md`（补充本次修复预防建议）
- Add (后续执行阶段): `docs/solutions/nyh-prod/integration-issues/baota-ssl-acme-challenge-routing-fix-2026-05-19.md`

**Approach:**
- 对 7 个域名逐一确认对应 include 文件：
  - `acquilangai.com`
  - `admin.acquilangai.com`
  - `admin.ddricher.ai`
  - `api.acquilangai.com`
  - `api.ddricher.ai`
  - `duowei.konghai.me`
  - `m.acquilangai.com`
- 使用同一标准模板填充空的 include 文件（与当前系统中可用的同类模板一致），并保留原文件备份。
- 覆盖前后记录变更清单，确保可回滚。
- 避免触碰其他域名或全局 Nginx include。

**Test scenarios:**
- Happy path: 对目标域名的 `/.well-known/acme-challenge/` 响应不再走到业务 404/502 分支（无论真实 token 是否存在）。
- Edge case: 任一域名 include 文件当前缺失，执行前先补全并走单域名回滚。
- Error path: 模板写入后若出现语法问题，则立即恢复备份并中止下一域名。
- Integration: 多个域名在同一台 Nginx 上共存，模板恢复不影响其他站点的静态资源与主入口路由。

**Verification:**
- 7 个 include 文件恢复为非空且可读；单域名回滚脚本有效。
- 无重启场景下，变更动作完成且无配置丢失。

### U2. 重载 Nginx 并做挑战路径可达性回归

**Goal:** 让更改生效并确认每个域名的挑战请求不被业务路由吸收。

**Requirements:** R2, R4

**Dependencies:** U1

**Files:**
- Modify: `docs/operations/README.md`（如执行时新增标准流程备注，按约定可选）
- Add/Update: `docs/operations/nyh-prod.md`（本次变更记录）

**Approach:**
- 在变更后仅执行配置语法校验与 Nginx reload。
- 对 7 个域名进行挑战路径验证：请求头路径必须明确落在 `/.well-known` 处理逻辑而非主入口返回分支。
- 对异常响应（仍为 301/302 跳转、5xx、站点级 404/Next 页面）做域名级阻断，回到 U1 处理。

**Test scenarios:**
- Happy path: 重载后，各域名挑战路径返回用于 ACME 场景的预期路径分派，不再出现应用 404 页面或 API 404/502。
- Edge case: 一个域名仍异常时，不影响其余域名的重试策略。
- Error path: reload 失败时保留回退窗口，避免误把新流量送入未验证状态。
- Integration: reload 不影响现网站点主页面可访问性（主入口返回不应退化）。

**Verification:**
- 所有 7 个域名在挑战路径层面通过行为校验。
- Nginx reload 可成功完成并保持服务可达。

### U3. 执行并验证 7 个域名续签

**Goal:** 让在用域名的证书重新进入自动续期周期并更新到磁盘。

**Requirements:** R1, R3, R4

**Dependencies:** U2

**Files:**
- Modify: `docs/solutions/nyh-prod/integration-issues/baota-ssl-acme-challenge-routing-fix-2026-05-19.md`

**Approach:**
- 在宝塔站点证书管理中对 7 个目标域名逐一触发续期。
- 关注续约任务日志的成功/失败明细，优先修复失败原因再复试。
- 确认更新后的证书文件时间戳和有效期发生变化，满足 7 个域名在用要求。

**Test scenarios:**
- Happy path: 7 个域名都能成功生成新证书且到期日超过当前日期明显可见提升。
- Edge case: 某个域名续签成功后，其他域名可能仍失败，继续留存失败域名清单和下一次复试计划。
- Error path: 若仍有验证失败，回到 U2 做逐步定位，确认是否为 DNS 与网络入口问题。
- Integration: 多域名批量续签后，Nginx 仍服务 443 流量且不影响其他站点。

**Verification:**
- 续期结果通过 `fullchain.pem` 时间和有效期核对通过。
- 续期失败明细可复现且有对应修复闭环。

### U4. 形成修复验收与回滚沉淀

**Goal:** 输出可审计结果，并确保未来同类问题可快速复现。

**Requirements:** R5

**Dependencies:** U3

**Files:**
- Add: `docs/solutions/nyh-prod/integration-issues/baota-ssl-acme-challenge-routing-fix-2026-05-19.md`
- Add: `docs/operations/nyh-prod.md`

**Approach:**
- 在 `docs/solutions/nyh-prod/...` 写明：根因、修复动作、验证矩阵、回滚方式。
- 在 `docs/operations/nyh-prod.md` 追加本次时间线，包括：原因、影响、回滚、变更、验证、后续。
- 标注不再维护的 3 个域名为何有意跳过。

**Test scenarios:**
- Happy path: 文档内容覆盖目标域名、步骤、验证与回滚。
- Edge case: 预留字段用于记录可能遗留的异常域名。
- Error path: 任何记录缺项（原因/影响/回滚）直接补齐，避免缺口。

**Verification:**
- 文档链接完整，能覆盖从根因到验收的完整链路。
- 复盘记录可直接用于下次同类巡检。

## Success Criteria

- 七个在用域名的 `/.well-known/acme-challenge/` 验证不再走业务 404/502。
- 这 7 个域名证书续签后显示为新时间线，离到期时间重置。
- 无额外高风险服务重启，生产访问窗口可控。
- 运维记录与解决方案文档完整，复盘可复用。
