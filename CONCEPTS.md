# Concepts

Shared domain vocabulary for this project - entities, named processes, and status concepts with project-specific meaning. Seeded with core domain vocabulary, then accretes as ce-compound and ce-compound-refresh process learnings; direct edits are fine. Glossary only, not a spec or catch-all.

## mac-mini iCare CI

### mac-mini-sonar runner
A named pool of four GitHub Actions self-hosted runner service instances on `mac-mini` used by iCare CI jobs such as SonarQube analysis and frontend tests.

Each runner instance owns its own service environment, work folder, temporary directory, and local tool-cache slot. A fix to PATH, work folder depth, or local tool availability is not complete until all four service instances have been updated and restarted.

### runner slot
One physical member of a mac-mini GitHub Actions runner pool, identified by its runner name and its corresponding short work folder.

Slot-local caches are independent: a tool-cache hit on one slot does not prove another slot is warm. Cache verification needs either a hit log per slot or a confirmed `.complete` marker in each slot's tool cache.

### mobile-preview-ci runner
The dedicated fifth self-hosted runner on `mac-mini` (`mac-mini-mobile-1`, workFolder `~/gha/m1`) that only runs iCare member-app **preview** `eas build --local` for Android and iOS.

It is not a member of the `mac-mini-sonar runner` pool. It must not carry `mac-mini-sonar`, `frontend-quality-ci`, `frontend-tests-ci`, `frontend-sonar-ci`, or `backend-ci`. iOS and Android compiles on this host are serial.

### konghai-friends-lab-1 runner
The org-level GitHub Actions runner on `mac-mini` for `konghai-friends-lab` (`konghai-friends-lab-1`, workFolder `~/gha/kfl1`, label `konghai-friends-lab`). It sits in the Default runner group (`visibility: all`), so every private repo in the org can use it.

It is not a `cypressoai` pool member and must not carry iCare CI labels. Workflows should use `runs-on: [self-hosted, konghai-friends-lab]`.

### mac-mini-acquilang-native-1 runner
The dedicated repo-level GitHub Actions runner on `mac-mini` for `IAmKongHai/AcquiLangAI` (`mac-mini-acquilang-native-1`, workFolder `~/gha/al1`, pool label `acquilang-native-ci`).

It is not a `cypressoai` pool member and must not carry `mac-mini`, `konghai-friends-lab`, or iCare quality labels. Workflows should use `runs-on: [self-hosted, macos, arm64, acquilang-native-ci]`. Do not schedule AcquiLang production native builds onto `mac-mini-mobile-1`.

### mac-mini-acquilang-ci runner 池

`mac-mini` 上为 `IAmKongHai/AcquiLangAI` 注册的日常 CI runner：`mac-mini-acquilang-ci-1` 到 `mac-mini-acquilang-ci-5`。工作目录分别是 `~/gha/alc1` 到 `~/gha/alc5`，label 都是 `acquilang-ci`。

五个 slot 共用 label `acquilang-ci`，另外带 `acquilang-build`。2026-10-10 起 `ci-4` 和 `ci-5` 停用，同时在这台机器上跑的 AcquiLang job 不超过 3 个。`acquilang-build` 也可以由 mas-go-dev 的 `mas-go-dev-acquilang-ci-1` 和 lemon-imac 的 `lemon-imac-acquilang-ci-1` 接。lemon-imac 这一台带 `macos` 和 `arm64`，native 的 Jest 可以落到它或 mac-mini 的在线 slot；它不带 `acquilang-ci`，Sonar 仍只走 mac-mini。这些实例不带 `acquilang-native-ci` 或 cypressoai 池标签；原生打包仍只在 `mac-mini-acquilang-native-1`。在线 slot 和原生 runner 共享 mac-mini 的 CPU、内存与磁盘。lemon-imac 只有一个 slot，避免和已有的 org runner 把 8GB 内存占满。

## 代理服务器流量监控

### VPS Traffic Monitor
A planned standalone Docker service on `mac-mini` for monitoring proxy VPS traffic on `tizi` and `rao-tizi`.

It reads existing `vnstat` data over SSH, calculates billing-cycle usage, shows an internal Web UI, and sends Telegram notifications when traffic or collection-failure thresholds are reached.

### billing reset day
The day of month when a VPS provider resets a server's traffic allowance.

For proxy traffic monitoring, this reset day defines the accounting cycle; calendar-month `vnstat -m` totals are not treated as authoritative when the provider's billing cycle starts on a different day.

## iCare 公网服务

### 公网 profile

iCare 按服务入口划分的运行配置与路由集合。CYP-2600 本次账号隔离范围是 `ecom`、`sup`、`app`、`hr`、`map`：前两者在 backend，后三者在 public-backend。它们各用独立的服务数据库账号，不是每位会员各建 SQL login；同表内不同会员或公司的数据归属仍由应用校验。

以上五个是本次范围，不代表 iCare 的全部公网服务。

## iCare UAT cut

### Protect release
GitHub repository ruleset on `release` that makes `mergeStateStatus=CLEAN` wait for required CI checks.

UAT cut scripts (`uat-cut-tag.sh`) cannot read Checks — `UAT_CUT_TOKEN` has no Checks permission (CYP-2186) — so they only poll `mergeStateStatus`. Without this ruleset, a develop→release sync PR is `CLEAN` immediately and merges in seconds, skipping Sonar.

MAS (`iCare-backend` / `iCare-frontend-mas`) has had it since CYP-1923. Public portal (`iCare-public-backend` / `iCare-public-frontend`) was missing it until 2026-08-24; required checks must match that repo's develop gate, not MAS check names.

## Sub2API / Gemini 订阅网关

### Sub2API
自建 AI API 网关：把 Claude / Gemini / Antigravity 等订阅 OAuth 收成项目自己的 `sk-` Key，再给 OpenAI 兼容客户端用。

客户端只改 `base_url` 和 Key；真正吃哪家额度，由账号平台类型和分组决定，不是由 `/v1/models` 目录决定。

### Antigravity 账号
Sub2API 里一种账号平台，消耗的是 Google AI Pro / Antigravity OAuth 订阅额度。

Gemini 3.7 Flash 的订阅访问在这条线上。OpenAI 兼容调用仍打网关的 `/v1`，不要把 `/antigravity` 前缀当成 OpenAI `base_url`。

Google 账号国家/地区设为中国时，上游会拒调（常见 403 Validation required），即使订阅有效、OAuth 已绑定。这是账号地区限制，不是网关缺 Project ID。

### google_one
Sub2API Gemini OAuth 的一种类型，走 Cloud AI Companion（Gemini for Google Cloud / Code Assist）。

启用该 API 只是项目权限门，不是 Vertex 按 token 计费，也不是控制台里的企业月费包。这条线不提供 Gemini 3.7 Flash 订阅额度。

### Antigravity 变体名
Antigravity 上游认的是带 thinking 档位的模型实体名，不是营销用的基础名。

网关目录里有基础名，不代表上游能创建该实体。订阅 3.7 Flash 要以当时 daily 端点实际返回 200 的变体名为准。

## 菜苗苗 SIT

### sit-api-cmm / sit-admin-cmm
菜苗苗系统集成测试的公网 HTTPS 主机名（`sit-api-cmm.nanyahui.cn` / `sit-admin-cmm.nanyahui.cn`）。TLS 在 `nyh-prod` 终结，应用和 PostgreSQL 18 在 `mas-go-dev`。不是生产域名 `api.caimiaomiao.com` / `admin.caimiaomiao.com`。

### shared-sit 租户
`mas-go-dev` 上合部署 SIT 的隔离单位：独立 PostgreSQL 库和角色、独立 Redis DB 号、可选独立 Garage bucket。应用 compose 加入 Docker 网络 `shared-sit`，目录不放进 `/opt/mas-go-dev/`。菜苗苗 SIT 用库/角色 `cmm`、Redis DB `2`（EVP 已用 `1`），文件仍走腾讯云 COS，不用 Garage。

## 宝塔面板证书

### 面板 SSL
宝塔面板自己的 HTTPS 证书，只给面板端口用，和同域名网站证书不是同一套文件。

站点续期成功不会自动写进面板 SSL。面板进程启动时把证书读进内存，磁盘替换后必须重启面板才会生效。宝塔自带的面板续签任务只处理 Let's Encrypt；TrustAsia LiteSSL 会被静默跳过，任务日志仍可能打印成功。

*Avoid:* 把站点证书到期日当成面板 HTTPS 到期日。

### LiteSSL
宝塔面板可申请的商业 DV 证书品牌，由 TrustAsia 签发，不走 Let's Encrypt ACME 账户。

它不会进入宝塔 `panel_ssl_task.py` 的 Let's Encrypt 续签分支，到期必须人工替换或改走 Let's Encrypt。

## Tailscale

### Exit Node
Tailscale 节点角色：被选中后，客户端（如手机）的默认上网流量经该节点转发并由该节点 SNAT 出公网，源 IP 为该节点公网地址。

与「仅加入 Tailnet 互访 `100.x`」不同；与代理面板（3x-ui / S-UI）的入站也不同。生产机做 Exit 时应 `--accept-dns=false`、`--accept-routes=false`，且服务器自身不选用其他 Exit。

*Avoid:* 把 Exit Node 与 subnet router（宣告内网网段）混为一谈。

## 代理节点（tizi 族）

### 扩容代理节点
只承载代理数据面与管理面板、不接 litellm/Nginx 业务反代的 VPS。公网通常只暴露 SSH 与代理端口（多为 443）；面板只经 Tailscale 访问。

*Avoid:* 把备用 litellm 入口机与纯代理节点混为一谈（例如 `rao-tizi` 兼业务入口时角色不同）。

### 入站（代理）
代理服务端上的一条「门」：监听地址/端口、协议与传输（如 VLESS+REALITY）、伪装目标等。一门可挂多个客户端。S-UI 称入站；3x-ui 侧栏「入站」同义。

### 客户端（代理用户）
使用某条入站的身份与额度：UUID/密钥、Flow、流量与过期。必须关联至少一条入站才有可用连接串。S-UI「用户」与 3x-ui「客户端」对应。

### 分享地址（share address）
写入客户端分享链接 `@` 之后、端口之前的主机名或 IP。应使用对外域名；若落成公网 IP 或 Tailscale IP，客户端仍可能连通但运维成本高且易误发。

### REALITY Flow
VLESS + REALITY 场景下客户端流控取值。需要 vision 时必须显式配置（常见为 `xtls-rprx-vision`）；面板默认「无」会导致有链接却无法正常代理。

## new-api / zzz.konghai.me AI 网关

### new-api
部署在 `dev-cypresso` 上的自建 AI API 网关（QuantumNous/new-api，Go），公网入口 `https://zzz.konghai.me`，栈目录 `/home/ec2-user/stacks/new-api/`。

它是 `shared-postgres` 的一个租户（库与角色均为 `new_api`），Redis 为专用容器 `new-api-redis`，不复用 `shared-redis`。与 mac-mini 上的 Sub2API 同类但互不相关。

### shared-postgres 租户
`dev-cypresso` 共享 PostgreSQL 容器 `shared-postgres` 上的一个独立库 + 同名非超级用户角色（如 `moo_ticket`、`evp`、`new_api`）。

新增租户只允许在运行中的容器上执行 psql DDL；不改 `stacks/infra/` 的 compose 或 `.env`，否则会 recreate 整栈并拉起已停容器。
