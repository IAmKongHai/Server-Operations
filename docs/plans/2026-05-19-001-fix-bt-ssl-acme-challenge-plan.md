---
title: 修复 nyh-prod 宝塔站点 SSL 续期挑战路由
type: fix
status: completed
date: 2026-05-19
---

# 修复 nyh-prod 宝塔站点 SSL 续期挑战路由

## Summary

`nyh-prod` 上 7 个在用域名（acquilangai 及 ddricher/acquilangai 相关站点、`duowei.konghai.me`、`m.acquilangai.com`）的续期失败。现场验证后确认问题分为两层：一是 `/.well-known/acme-challenge/` 请求曾被主站业务入口吞掉；二是 Docker 功能面板里的反代域名未进入宝塔网站模块的 `sites` / `domain` 映射，导致 `renew_v2` 默认扫描与 `--index` 续期会判定域名“不存在”或“未使用”。该计划目标是保留 Docker 面板管理模型，恢复 HTTP-01 通道，并用动态发现的显式 HTTP-01 申请脚本托管这些 Docker 反代域名的证书续期。

## Problem Frame

- 初始续期日志与现场探测显示，目标域名的 `well-known` include 文件为空或未生效，导致 HTTP-01 验证不再直接命中 ACME 处理逻辑。
- `/.well-known/acme-challenge/` 曾直接走到业务层（返回 301 跳转到 404、Next.js 页面、API 404 或 502），现已通过恢复宝塔标准 include 模板验证可达。
- 后续单域名测试确认：`admin.acquilangai.com` 使用 `renew_v2 --index` 会失败在宝塔站点映射层，日志提示“域名不存在 / 没有找到可用的文件验证站点”。该域名存在 Nginx vhost、root 与 cert 目录，但不在宝塔 `domain` 表中。
- 用户明确不希望把 Docker 功能面板域名重新接管到宝塔“网站”列表；因此本计划不再以恢复 `sites` / `domain` 绑定作为主线。
- 当前排除的 3 个域名（`pgadmin.konghai.me`、`test-center.nanyahui.com`、`test-vip.nanyahui.cn`）本次不再修复。

## Requirements

- R1. 仅恢复并固定 7 个在用域名的 ACME-01 可达性，不修改其余 3 个废弃域名续签状态。
- R2. 对目标域名保证 `/.well-known/acme-challenge/` 不再被业务 `location ^~ /` 或其他应用级路由抢占。
- R3. 在不改动现有业务入口、不把 Docker 反代站点迁入宝塔网站列表的前提下，恢复证书续期链路。
- R4. 续期可恢复后，输出可验证结果（证书到期时间更新、端口证书有效期一致、续期日志记录）。
- R5. 形成最小化操作记录，便于将来回放和责任审计。
- R6. 为 Docker 功能面板域名建立独立定时续期脚本，动态发现 Docker/反代 vhost，避免依赖宝塔 `renew_v2` 默认站点扫描，也避免人工维护续期清单。

## Scope Boundaries

- 本计划只处理 `nyh-prod` 的 Docker 功能面板反代域名证书续期链路。
- 保留 Docker 功能面板作为这些反代站点的管理入口，不把目标域名迁入宝塔“网站”列表。
- 不改：
  - `pgadmin.konghai.me`
  - `test-center.nanyahui.com`
  - `test-vip.nanyahui.cn`
- 不处理：
  - 证书吊销、DNS 供应商迁移、全站 HTTPS 策略重构。
  - 既有业务代码与数据库结构。
  - 宝塔面板核心脚本补丁与面板数据库手写绑定修复。
- 不执行：大规模重启除 Nginx 外的服务。

### Deferred to Follow-Up Work

- 为其它已下线域名统一清理证书目录与站点绑定是否可用，需另起计划。
- 为宝塔“网站”模块内的普通站点补充统一证书状态巡检脚本，另起计划处理。
- 研究 DNS-01 自动化作为 Docker 反代域名的长期替代方案，另起计划处理。

## Context & Research

- 先前只读核查已确认：7 个在用域名全部存在同类异常特征（HTTP 请求进入 404/502 分支）。
- 目标域名的 `well-known` include 文件曾为空；恢复为宝塔标准模板后，使用临时 token 验证 `/.well-known/acme-challenge/` 可返回预期内容。
- `admin.acquilangai.com` 的显式 HTTP-01 申请已验证成功：磁盘证书从 2026-05-18 更新到 2026-08-17/18，手动 Nginx reload 后 443 端口返回新证书。
- `renew_v2 --index` 对 `admin.acquilangai.com` 的测试失败原因为宝塔 `domain` 表无该域名映射；该失败发生在文件验证前，不是 HTTP-01 路由失败。
- 用户指出新增 Docker 功能面板站点后人工维护续期清单不可靠；脚本应每次运行时从 Nginx vhost 配置动态发现候选站点，仅保留明确废弃域名的排除清单。
- 宝塔社区存在同类反馈：Docker 功能面板/反代站点在 SSL 续期中被判定为“域名全部未使用，已跳过”，而宝塔“网站”模块站点可进入默认续期流程。
- 该仓的既有实践中已有 `nyh-prod` 证书加载问题的处理经验，问题本质是“续签到磁盘但进程/配置未及时按新路径响应”。
- 关键约束：生产环境下操作应可回滚且不扩大影响面。

## Key Technical Decisions

- 采用“恢复现有宝塔标准 `well-known` include 模板”而非重写 location 规则，减少误伤。
- 保持 `/.well-known/acme-challenge` 处理最小化，只修复挑战请求入口，不改动业务主入口缓存、CORS、重定向等既有逻辑。
- 不把 Docker 功能面板域名重新接管到宝塔“网站”列表；该做法虽能让 `renew_v2` 默认扫描覆盖，但会改变用户期望的管理入口。
- 不手写宝塔 `sites` / `domain` 数据库映射；避免 UI 状态、vhost 文件、证书索引和实际配置之间产生新的不一致。
- 对 Docker 反代域名采用宝塔 `acme_v2.py --domain ... --type http --path ...` 显式 HTTP-01 申请；该路径不依赖 `domain` 表映射，且已在 `admin.acquilangai.com` 上验证可行。
- 定时脚本每次运行时扫描 Nginx vhost 配置动态发现 Docker/反代类站点；判定依据包括 `server_name`、`root`、`ssl_certificate`、`proxy_pass`、`well-known` include，以及该域名是否不属于宝塔普通网站 `domain` 表。
- 将自动化动作分为“动态发现 + 排除废弃域名 + 剩余天数判断 + 证书目录外备份 + 显式 HTTP-01 申请 + Nginx 语法校验 + reload + 端口证书核对 + 记录”，避免每天无条件申请触发 Let’s Encrypt 限速。
- 备份目录必须放在 `/www/server/panel/vhost/cert` 之外；宝塔 `sub_all_cert()` 会扫描该目录并替换同域名旧证书，放在其中的备份也会被覆盖。

## Open Questions

- 哪个域名在 7 个中先续期？
  - 决议：先用 `admin.acquilangai.com` 验证显式 HTTP-01 申请链路；成功后再按相同模式扩展到剩余 6 个目标域名。
- 是否需要在此阶段立即加入巡检脚本？
  - 决议：本计划需要加入 Docker 面板域名的独立续期脚本；普通站点巡检留在 Follow-Up。
- 是否恢复宝塔网站模块站点绑定？
  - 决议：不恢复。保持目标域名只由 Docker 功能面板管理，续期由独立脚本维护。
- 是否人工维护 Docker 域名续期清单？
  - 决议：不人工维护。脚本每次运行动态扫描 Nginx vhost 配置发现候选域名，仅维护废弃域名排除清单。

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

### U3. 用显式 HTTP-01 申请验证 Docker 面板域名续期链路

**Goal:** 在不恢复宝塔网站模块绑定的情况下，证明 Docker 面板反代域名可通过显式 HTTP-01 申请更新证书。

**Requirements:** R1, R3, R4

**Dependencies:** U2

**Files:**
- Modify: `docs/solutions/nyh-prod/integration-issues/baota-ssl-acme-challenge-routing-fix-2026-05-19.md`

**Approach:**
- 以 `admin.acquilangai.com` 为样本，使用显式域名、验证方式和 webroot 申请新证书。
- 申请前备份当前证书目录，备份位置必须在 `/www/server/panel/vhost/cert` 外部，避免被宝塔证书替换逻辑扫描并覆盖。
- 申请成功后确认新证书写入宝塔 Let’s Encrypt 保存目录，并替换当前 Nginx 引用的证书目录。
- 如果宝塔脚本未让当前 Nginx worker 加载新证书，则在配置语法校验通过后 reload Nginx。
- 将 `renew_v2 --index` 的失败原因记录为已排除路径：该路径依赖宝塔 `domain` 表映射，不适合这些 Docker 面板域名。

**Test scenarios:**
- Happy path: `admin.acquilangai.com` 通过显式 HTTP-01 申请成功，磁盘证书有效期从过期时间更新到新的 90 天窗口。
- Edge case: 宝塔 `sub_all_cert()` 自动替换证书文件但未让 443 端口立即加载新证书时，通过 Nginx reload 后端口证书与磁盘证书一致。
- Error path: 如果 HTTP-01 验证失败，回到 U2 核对 token 文件是否可从公网访问；如果申请成功但部署未覆盖目标证书目录，记录保存路径与覆盖失败原因。
- Integration: 单域名续期与 reload 不影响该域名现有 Docker 反代入口和其他站点 443 服务。

**Verification:**
- `admin.acquilangai.com` 的 `fullchain.pem` 有效期更新。
- 443 端口通过 SNI 读取到的新证书有效期与磁盘证书一致。
- 续期日志保留 HTTP-01 验证成功、证书下载、证书替换与 reload 结果。

### U5. 为 Docker 功能面板域名建立动态发现定时续期脚本

**Goal:** 把显式 HTTP-01 续期模式固化为可重复执行的定时任务，并通过扫描 Nginx vhost 配置自动发现 Docker 功能面板反代域名，避免新增站点后人工维护清单。

**Requirements:** R1, R3, R4, R6

**Dependencies:** U3

**Files:**
- Add: `docs/solutions/nyh-prod/integration-issues/baota-ssl-acme-challenge-routing-fix-2026-05-19.md`
- Add/Update: `docs/operations/nyh-prod.md`

**Approach:**
- 每次运行扫描 Nginx vhost 配置，提取 `server_name`、`root`、`ssl_certificate`、`proxy_pass` 和 `well-known` include。
- 将存在 `proxy_pass`、存在证书路径、存在 webroot、具备 `well-known` include，且不在宝塔普通网站 `domain` 表中的 vhost 判定为 Docker/反代类续期候选。
- 维护最小排除清单，仅放入已明确废弃或不应续期的域名，例如 `pgadmin.konghai.me`、`test-center.nanyahui.com`、`test-vip.nanyahui.cn`。
- 从当前证书读取 SAN，生成显式 HTTP-01 申请的完整域名集合；无法读取 SAN 时，降级使用 vhost `server_name` 并在日志中标记需要人工确认。
- 每次执行先读取当前证书剩余天数，仅在剩余天数小于等于阈值时申请，避免无条件重复申请触发 Let’s Encrypt 限速。
- 对 `acquilangai.com` 这类包含 `www` SAN 的证书，显式申请时保持与当前证书域名集合一致，避免新证书 SAN 不匹配导致宝塔自动替换逻辑无法命中目标证书目录。
- 每个域名申请前将当前证书备份到 `/www/backup/ssl-cert/` 这类宝塔证书扫描目录之外。
- 申请成功后执行 Nginx 语法校验；校验通过才 reload Nginx，并核对 443 端口证书有效期。
- 支持 dry-run 模式，打印本次动态发现的候选、排除、跳过和将要续期的域名，作为上线前验收步骤。
- 使用 `flock` 避免定时任务并发执行；日志写入独立文件，便于审计和失败重试。

**Test scenarios:**
- Happy path: 当证书剩余天数小于等于阈值时，脚本对目标域名申请新证书、reload Nginx，并记录新有效期。
- Happy path: 新增 Docker 功能面板反代站点后，只要生成了符合条件的 Nginx vhost 与证书目录，脚本下次运行能自动发现该域名。
- Edge case: 当证书剩余天数大于阈值时，脚本跳过申请并记录跳过原因。
- Edge case: vhost 中多个 `server_name` 或证书 SAN 与 `server_name` 不完全一致时，脚本优先使用当前证书 SAN，并在日志中记录最终申请域名集合。
- Edge case: 多 SAN 证书申请时，脚本使用完整 SAN 列表，申请后目标证书目录被正确替换。
- Error path: vhost 缺少 `well-known` include、webroot 不存在或证书文件缺失时，脚本跳过该 vhost 并记录原因，不尝试申请。
- Error path: 某个域名 HTTP-01 验证失败时，脚本记录失败并继续处理后续域名，不回滚已成功域名。
- Error path: Nginx 语法校验失败时，不执行 reload，并保留新旧证书与失败日志供人工处理。
- Integration: 定时任务重复执行不会并发运行，不会每天消耗 Let’s Encrypt 申请额度。

**Verification:**
- dry-run 输出能展示动态发现的 Docker/反代候选域名、排除域名、跳过原因和计划续期域名。
- 7 个目标域名被动态发现，废弃 3 个域名被排除清单过滤。
- 新增一个符合条件的 Docker 功能面板反代站点后，无需手工编辑脚本清单即可在 dry-run 中出现。
- 运行日志能区分跳过、成功、失败和 reload 结果。
- 每个续期成功域名的磁盘证书与 443 端口证书有效期一致。

### U4. 形成修复验收与回滚沉淀

**Goal:** 输出可审计结果，并确保未来同类问题可快速复现。

**Requirements:** R5

**Dependencies:** U3, U5

**Files:**
- Add: `docs/solutions/nyh-prod/integration-issues/baota-ssl-acme-challenge-routing-fix-2026-05-19.md`
- Add: `docs/operations/nyh-prod.md`

**Approach:**
- 在 `docs/solutions/nyh-prod/...` 写明：双层根因、修复动作、验证矩阵、回滚方式。
- 在 `docs/operations/nyh-prod.md` 追加本次时间线，包括：原因、影响、回滚、变更、验证、后续。
- 标注不再维护的 3 个域名为何有意跳过。
- 记录 `admin.acquilangai.com` 试点成功结果，以及备份目录不能放在宝塔证书扫描目录内的经验。
- 记录 Docker 面板域名与宝塔网站模块域名在续期机制上的差异，避免后续误判为单纯 HTTP-01 路由问题。
- 记录动态发现规则、排除清单维护规则和新增 Docker 反代站点后的自动纳入条件。

**Test scenarios:**
- Happy path: 文档内容覆盖目标域名、步骤、验证、动态发现自动化策略与回滚。
- Edge case: 预留字段用于记录可能遗留的异常域名。
- Error path: 任何记录缺项（原因/影响/回滚）直接补齐，避免缺口。

**Verification:**
- 文档链接完整，能覆盖从根因到验收的完整链路。
- 复盘记录可直接用于下次同类巡检。

## Success Criteria

- 七个在用域名的 `/.well-known/acme-challenge/` 验证不再走业务 404/502。
- 这 7 个域名证书续签后显示为新时间线，离到期时间重置。
- Docker 功能面板域名由动态发现定时脚本维护证书续期，不依赖宝塔 `renew_v2` 默认站点扫描，也不依赖人工维护域名清单。
- 无额外高风险服务重启，生产访问窗口可控。
- 运维记录与解决方案文档完整，复盘可复用。
