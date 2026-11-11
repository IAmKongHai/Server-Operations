---
artifact_contract: "ce-handoff/v1"
created_at: "2026-11-11T09:46:00Z"
title: "tovo.sh (new-api) 经 DO-1 Nginx 透明反代继续接入 Claude 等官方 LLM 供应商"
summary: "已完成 DO-1 sub2api (OpenAI 28 模型) 与 Nginx /groq/ 透明反代 (Groq 12 模型，含 TTS/STT) 上线验收；下阶段按同一模式继续接入 Claude 等官方 API Key"
keywords: ["nyh-prod-2026", "do-1", "new-api", "sub2api", "tovo.sh", "sub.tovo.sh", "groq", "claude", "anthropic", "nginx-relay"]
cwd: "/Users/konghai/code/Project/Server"
resume_focus: "按 DO-1 Nginx 无状态美区透明反代 + nyh-prod-2026 new-api 主备双渠道模式，继续接入 Claude 官方 API Key 及其他 LLM 供应商官方 Key"
repository: "github.com/IAmKongHai/Server-Operations"
repo_root_sha: "105e22b22e8936b9788d571dd0dd845a4cf8424d"
branch: "main"
head: "cb911fba30dc4d8fdb1aad748f19e82107339a6a"
---

# tovo.sh 经 DO-1 透明反代接入官方 LLM 供应商交接

## 背景与目标（用户意图）

`nyh-prod-2026`（阿里云香港 `8.217.145.133`，公网域名 `https://tovo.sh`）上的 `new-api` 是对外给下游业务与同事统一供货的 AI API 网关。由于香港出口 IP 被多家海外官方供应商锁区（已实测 `api.groq.com` 与 `api.anthropic.com` 从 `nyh-prod-2026` 直连均返回 `403`），用户在 2026-11-11 明确选定并落地了以下三层生产架构：

1. **`nyh-prod-2026`（`new-api`）**：全站唯一的统一网关，集中负责鉴权、人民币计费、多 Key 轮询与主备自动故障切换。
2. **`do-1`（旧金山 `137.184.127.196` / Tailscale `100.86.92.103`，`sub2api`）**：只承担其本职工作——将订阅账号 / OAuth（如 ChatGPT Codex）转换为标准 API。
3. **`do-1`（`Nginx` 无状态透明反代）**：复用已配好严格 IP 白名单与自动续期的 `https://sub.tovo.sh`（主，`:443`）与 `http://100.86.92.103:8080`（备，Tailscale），按路径前缀（如 `/groq/`、后续 `/anthropic/` 等）为锁香港区的**官方 API Key** 提供零状态美区出口。

此外，用户明确声明原 `/Users/konghai/code/Project/DigitalOcean`（machine-local）仓库准备废弃，`do-1` 的所有配置源码与运维时间线统一只维护在本仓库。下一会话用户的明确目标是：**继续添加 Claude 官方 API Key 及其他 LLM 供应商官方 Key**。

## 先读这些（权威指针）

- `do-1/nginx/sites-available/sub2api.conf`（第 1–50 行 `:8080` 备入口与 `/groq/` 反代块；第 84–140 行 `:443` `sub.tovo.sh` IP 白名单、ACME 续期豁免与 `/groq/` 反代块）及 `do-1/nginx/upstreams/groq-upstream.conf`：新增官方供应商反代时的直接配置模板。
- `do-1/README.md`（第 9–41 行）：大陆本机 SSH 登录方式（直连公网易超时，必须走 Tailscale `ssh -i ~/.ssh/id_ed25519 root@100.86.92.103`）、`sub2api` 蓝绿槽位机制与 `certbot` 自动续期约束。
- `nyh-prod-2026/README.md`（第 64–65 行）与 `nyh-prod-2026/docker/new-api/compose.yaml`（第 11–18 行）：`new-api` 固定镜像 `calciumion/new-api:v1.0.0-rc.49`，宿主机回环监听 **`127.0.0.1:3200`**（非 `:3000`）。
- `/Users/konghai/code/Project/Server/nyh-prod-2026/secrets.local.md`（machine-local，gitignored）：存有 `tovo.sh` `root` 后台密码、RDS/Redis 凭据及现有渠道 `#1..#5` 密钥留档；后续新增的供应商官方 Key 同样只追加到此文件，严禁写入 Git 跟踪文件。
- `docs/operations/nyh-prod-2026.md`（第 1–95 行，2026-11-11 四条记录）与 `docs/operations/do-1.md`（第 1–50 行，2026-11-11 两条记录）：跨洋延迟/吞吐实测数据、计费换算推导与远端备份路径。
- `/Users/konghai/code/Project/new-api`（machine-local，本地源码仓）：接入新供应商前用于核实该渠道类型的 `GetRequestURL` 路径拼接规则及特殊计费逻辑（例如 `relay/channel/claude/adaptor.go` 第 76–90 行、`service/quota.go` 第 49–86 行）。
- 本会话相关提交：`64e2368`、`5feb07b`、`1a6e196`、`311e97d`、`cb911fb`。

## 当前线上状态（已上线并完成端到端对账）

- **跨洋底层与连接保活（已完成）**：
  - `nyh-prod-2026` 与 `do-1` 双端对称开启 `bbr` + `fq`、`tcp_slow_start_after_idle=0`、32MiB TCP buffer（`nyh-prod-2026/sysctl/98-cross-ocean-tcp.conf`、`do-1/sysctl/98-cross-ocean-tcp.conf`）。
  - `do-1` `/etc/nginx/nginx.conf` 已开 `underscores_in_headers on;`；`sub2api.conf` `keepalive_timeout 120s` 大于 `nyh-prod-2026` `/opt/stacks/new-api/.env` 的 `RELAY_IDLE_CONN_TIMEOUT=60`（配 `RELAY_HTTP2_PING_IDLE_TIMEOUT=30`），消除跨洋空闲连接复用 502/EOF 竞态。
- **`tovo.sh` 统一计费基线与现有 `default` 组渠道（已完成）**：
  - 站内启用人民币口径：`1 内部单位 = ¥1.00 = 500,000 quota`，`USDExchangeRate = 1`；`ModelRatio = 1.0` 对应 `¥2.00 / 1M tokens`（汇率按 `1 USD = ¥7.30` 折算，故 100% 官方价公式为 `ModelRatio = USD_in × 3.65`，150% 官方价公式为 `ModelRatio = USD_in × 5.475`）。
  - 渠道 `#1`：通天云 Seedance 视频（`type=54`，优先级 `0`，官方价 ×1）。
  - 渠道 `#2` / `#3`：`do-1` `sub2api` OpenAI 28 模型（`type=1`，主 `https://sub.tovo.sh` 优先级 `10` / 备 `http://100.86.92.103:8080` 优先级 `0`，`test_model=gpt-6-luna`，按官方价 100% × `7.3` 计费）。
  - 渠道 `#4` / `#5`：Groq 官方 12 模型（`type=1`，主 `https://sub.tovo.sh/groq` 优先级 `10` / 备 `http://100.86.92.103:8080/groq` 优先级 `0`，`test_model=openai/gpt-oss-20b`，按用户指定的官方价 **150%** × `7.3` 计费；LLM、Responses、Orpheus 双语 TTS、Whisper STT 均已实测通过且账单精确吻合）。
- **现有用户与测试边界**：
  - `root`（`id=1`）、`aozhuo-test`（`id=2`，客户测试账号，余额 `¥50.00` `quota=25,000,000` 零消费，**自测时切勿动用该账号或令牌**）、`hon`（`id=3`，同事，已调通）。
- **远端备份目录（machine-local）**：
  - `do-1:/root/sub2api-tovo-20261111/`（含 `nginx.conf.bak`、`sub2api.conf.bak`、`sub2api.conf.before-groq.bak`）
  - `nyh-prod-2026:/root/sub2api-tovo-20261111/`（含 `new-api.env.bak`、`new-api-billing-options.before.json`、`new-api-before-groq.json`）

## 下一步接入 Claude 及其他官方供应商的准备情况与SOP

### 1. 已完成的 Claude（Anthropic）只读预检事实
- **锁区与延迟**：`nyh-prod-2026` 直连 `https://api.anthropic.com/v1/messages` 返回 `403`；`do-1` 直连返回 `405`（GET 探活预期响应，RTT 仅 `72 ms`）。
- **`new-api` URL 拼接核实**：`/Users/konghai/code/Project/new-api/relay/channel/claude/adaptor.go`（第 76–90 行）直接执行 `fmt.Sprintf("%s/v1/messages", info.ChannelBaseUrl)` 并保留 `?beta=true` 及 Anthropic 原生请求头。
- **标准接入动作（待用户提供 Key、目标模型范围与定价倍率并确认执行后落地）**：
  1. 向用户确认三件事：官方 API Key、开放模型范围（全量或指定列表）、对客计费倍率（如 100% 还是 150% 官方价；注：OpenAI 用了 100%，Groq 用户指定了 150%，**不可自行假设，须由用户拍板**）。
  2. 在本仓库新增 `do-1/nginx/upstreams/anthropic-upstream.conf`（`api.anthropic.com:443 max_fails=0; keepalive 16; keepalive_timeout 55s;`），并在 `do-1/nginx/sites-available/sub2api.conf` 的 `:8080` 与 `:443` 各加一段 `location ^~ /anthropic/`（`proxy_pass https://anthropic_api/;`，头处理同 `/groq/`）；先备份 `do-1` 原文件，再推送并 `nginx -t && systemctl reload nginx`。
  3. 先备份 `nyh-prod-2026` `new-api` 当前 `options` 与 `channels` JSON；再合并更新 `ModelRatio`、`CompletionRatio`、`CacheRatio`（Claude 读缓存通常 `0.1`）、`CreateCacheRatio`（Claude 5m 写缓存通常 `1.25`），创建 Anthropic 类型（`type=14`）主备双渠道（`https://sub.tovo.sh/anthropic` 优先级 `10`、`http://100.86.92.103:8080/anthropic` 优先级 `0`，归入 `default` 组）。
  4. 用 `root` 临时令牌做公网端到端实测（可同时验证 `/v1/messages` 原生格式与 `/v1/chat/completions` 转换格式）及日志扣费对账，测完删除临时令牌，把密钥留档进 `secrets.local.md`，更新 `README.md` 与 `docs/operations/{do-1,nyh-prod-2026}.md` 并在 `main` 提交。
- **接入其他官方供应商（如 Gemini / xAI / OpenAI 官方 Key 等）**：先在 `/Users/konghai/code/Project/new-api/relay/channel/` 查清对应渠道 `Adaptor.GetRequestURL` 的路径拼接前缀（避免双写或漏写 `/v1`），其余流程完全一致。

### 2. 未决背景项（非阻塞，未经用户明确指示勿动）
- `do-1` 上旧的 `new-api@blue.service` 及 `/etc/nginx/sites-enabled/new-api.conf`（迁移前的旧 `tovo.sh` 实例）目前仍处于运行状态。我们曾在方案对比中提议后续可停用回收内存，但**用户尚未下达停用指令**，切勿顺手停掉。

## 不要重走的路与易踩的坑

- **不要用 `sub2api` 转发官方 API Key，也不要做双 `new-api` 串联**：用户已明确否决这两条路，`sub2api` 不支持 `/v1/audio/*` 且增加协议转换层，双 `new-api` 增加双倍维护成本；统一走 `do-1` Nginx 无状态路径反代。
- **`do-1` Nginx 新增反代块必须剥离客户端源 IP 头并开启 SNI**：务必设置 `proxy_set_header X-Real-IP ""; proxy_set_header X-Forwarded-For "";` 以及 `proxy_ssl_server_name on; proxy_ssl_name <upstream_host>; proxy_set_header Host <upstream_host>;`，防止把 `nyh-prod-2026` 的香港 IP 暴露给上游风控或触发 Cloudflare TLS 握手失败。
- **切勿破坏 `sub.tovo.sh` 的 IP 白名单与 ACME 豁免**：`:443` 顶层 `allow 8.217.145.133; allow 100.64.0.0/10; allow 127.0.0.1; allow ::1; deny all;` 保护所有反代子路径不被外网扫作免费代理；同时 `:80` 与 `:443` 的 `location ^~ /.well-known/acme-challenge/` 必须保留 `allow all;`，否则 Let's Encrypt 自动续期会 `403` 失败。
- **`new-api` v1.0.0-rc.49 管理接口的 4 个细节坑**：
  1. 登录 `POST http://127.0.0.1:3200/api/user/login` 返回 JWT 在 `data.access_token`，后续调用需同时带 `Authorization: Bearer <jwt>` 与 `New-Api-User: 1`。
  2. 修改 `ModelRatio` / `CompletionRatio` / `CacheRatio` / `CreateCacheRatio` / `AudioCompletionRatio` 时，必须先 `GET /api/option/` 读取现有 JSON map 合并后再 `PUT /api/option/`，直接写局部字典会清空既有模型定价。
  3. `PUT /api/channel/` 更新渠道时 payload **不能包含 `"status"` 字段**（后端会报错拒绝）。
  4. `GET /api/token/` 返回的 `key` 是带 `*` 掩码的脱敏串；自测创建临时令牌后必须调 `POST /api/token/{id}/key` 获取真实 48 位明文密钥，验收后立即 `DELETE /api/token/{id}`。
- **TTS / 音频模型计费防坑**：`new-api` 对未配置 `AudioCompletionRatio` 的模型默认按 `1` 额外计入输出音频时长 token（Groq Orpheus 流式 WAV 头 `0xFFFFFFFF` 尤其会放大误差），凡按输入字符计费的 TTS 模型必须同步设置 `"AudioCompletionRatio": 0`。
- **生产操作红线（`AGENTS.md`）**：`nyh-prod-2026` 与 `do-1` 均为生产服务器。执行 Nginx reload 或写入 `new-api` 数据库前，必须先向用户说明变更、影响与回滚方式，先落盘备份，**经用户确认后再执行**；执行完成后无需再问，直接追加 `docs/operations/<server>.md` 并在 `main` 分支提交中文 `git commit`。
