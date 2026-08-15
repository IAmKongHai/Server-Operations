---
title: 在 mac-mini 用 Colima / Docker Compose 部署 Sub2API
type: ops
status: proposed
date: 2026-08-16
server: mac-mini
---

# 在 mac-mini 用 Colima / Docker Compose 部署 Sub2API

## Summary

在家里的 `mac-mini` 上，用**现有 Colima Docker 引擎**部署 [Wei-Shaw/sub2api](https://github.com/Wei-Shaw/sub2api)（AI 订阅账号 → 统一 API Key 网关）。栈是官方三件套：`sub2api` + PostgreSQL 18 + Redis 8。

本计划只覆盖评估与推荐路径。真正 `docker compose up`、写 `.env`、拉镜像必须用户确认后再做。

**推荐默认（未确认前不执行）：**

| 项 | 推荐 |
| --- | --- |
| 引擎 | 现有 Colima（不要 Apple `container`，不要再开 Docker Desktop） |
| 目录 | `~/stacks/sub2api/`（与 `sonarqube` / `richer` 同级） |
| compose | 官方 `docker-compose.local.yml`（数据落本地目录，方便 tar 备份） |
| 镜像 | 钉死 `weishaw/sub2api:0.1.177`（有 `linux/arm64`，约 75MB） |
| 端口 | 宿主 `8080`（当前空闲）；Postgres / Redis **不**映射到宿主 |
| 暴露 | 只绑 Tailscale `100.108.64.126:8080`，不进公网、不绑 LAN `0.0.0.0` |
| 模式 | `RUN_MODE=simple` + `SIMPLE_MODE_CONFIRM=true`（个人/家庭自用，跳过计费） |
| 资源 | 整栈预算约 1.0–1.5 GiB，**不**扩大 Colima 12 GiB 配额 |

---

## 1. 项目是什么

Sub2API 是一个自建 AI API 网关：把 Claude / OpenAI / Gemini / Grok 等订阅账号或官方 API Key 收进管理后台，再给客户端发平台自己的 `sk-` Key。客户端（Claude Code、Codex、Gemini CLI、Grok CLI、OpenCode）只改 `base_url` + Key。

技术栈：Go + 内嵌 Vue 前端、PostgreSQL 15+、Redis 7+。官方提供四种装法：

| 方法 | 适用 | 本机结论 |
| --- | --- | --- |
| Docker Compose | 官方推荐的完整栈 | **采用** |
| 一键 `install.sh` 二进制 | Linux + systemd | macOS 不适用 |
| Apple `container` | macOS 26 本机实验 | 不采用：刚把引擎统一到 Colima；官方也写「生产仍走 Compose」 |
| 源码编译 | 开发 | 不采用 |

上游仓库自己也写了：**使用本项目可能违反 Anthropic 等服务商条款**，风险自负。本仓库只记部署，不讨论如何绕过风控。

当前上游版本：`v0.1.177`（2026-08-15）。Docker Hub `weishaw/sub2api:0.1.177` 是 multi-arch，含 `linux/arm64`。

---

## 2. mac-mini 现场（2026-08-16 只读）

| 项 | 现状 |
| --- | --- |
| 机器 | Apple Silicon，macOS 26.5.2，10 核 / 32 GiB，磁盘剩余约 715 GiB |
| Docker 引擎 | Colima `vz` / 6 CPU / **12 GiB** / 100 GiB 盘，LaunchDaemon `system/com.konghai.colima` |
| context | `default` → Colima；Engine 29.5.2 |
| 已在跑 | `sonarqube` + `sonar-postgres`（约 2.4 GiB）、`richer-grafana` + `richer-postgres`（约 80 MiB） |
| Colima 盘 | `/mnt/lima-colima` 98G 用了 15G |
| 已占用宿主端口 | `9000` Sonar、`3001` Grafana、`5432` richer-postgres（`0.0.0.0`） |
| `8080` / `6379` | **空闲** |
| 栈目录惯例 | `~/stacks/sonarqube`、`~/stacks/richer` |
| Tailscale | `100.108.64.126`，MagicDNS `mac-mini` / `mac-mini.taila93443.ts.net` |
| 宿主出站 | `api.anthropic.com` / `api.openai.com` / `api.x.ai` / `generativelanguage.googleapis.com` / Docker Hub 均可在约 1s 内打通（无系统代理） |

补充约束：

- `hon` 另有一套 `colima-multica` VM（约 11 GiB RSS）。宿主机两套 Lima 已经偏满，**不要**为 Sub2API 再加大 `konghai` 的 Colima。
- Docker Desktop 的 `com.docker.vmnetd` 仍在，但不跑业务容器。不要把它拉回来。
- 官方 `.env.example` 的连接池按「独立 8G 服务器」写（`DATABASE_MAX_OPEN_CONNS=256`、`REDIS_POOL_SIZE=4096`、`POSTGRES_SHARED_BUFFERS=1GB`）。原样套到这台 12 GiB 共享 VM 上会和 Sonar 抢内存。

---

## 3. 推荐架构

```text
Tailnet 客户端
  Claude Code / Codex / Gemini CLI / 浏览器
           │
           │  http://mac-mini:8080
           │  （仅 100.108.64.126:8080）
           ▼
   mac-mini 宿主端口 8080
           │  Colima 端口转发
           ▼
   ┌─────────────────────────────────────┐
   │  compose project: sub2api           │
   │  network: sub2api-network（内部）   │
   │                                     │
   │  sub2api          :8080             │
   │    ├─ postgres:18-alpine（不映射）  │
   │    └─ redis:8-alpine（不映射）      │
   └─────────────────────────────────────┘
           │
           │  容器出站走 Colima/vz → 宿主网络
           ▼
   Anthropic / OpenAI / Google / xAI
```

数据落在宿主目录，不进 named volume：

```text
~/stacks/sub2api/
  docker-compose.yml          # 官方 local 版，改两处：钉镜像 + 补 SIMPLE_MODE_CONFIRM
  .env                        # 600，不进本仓库
  .env.example
  data/                       # 应用 config.yaml + 日志
  postgres_data/
  redis_data/
```

这样整目录 `tar` 就能备份/迁移，和官方推荐一致。

---

## 4. 为什么不照抄官方一键脚本

```bash
curl -sSL .../deploy/docker-deploy.sh | bash
docker compose up -d
```

脚本会下载 `docker-compose.local.yml`、生成三个密钥、建目录。问题：

1. 镜像写死 `weishaw/sub2api:latest`，升级不可复现。
2. 不改 `BIND_HOST`，默认 `0.0.0.0:8080`，家里局域网任意设备都能打到管理后台和 API。
3. 不改连接池，默认按大规格。
4. 不传 `SIMPLE_MODE_CONFIRM`，`RUN_MODE=simple` 在 release 模式下会起不来。
5. 密钥打到终端，容易进 shell history。

采用「官方 compose 当底板 + 本机定制 `.env` + 两处补丁」。

---

## 5. 必须改的配置

### 5.1 compose 补丁（相对官方 `docker-compose.local.yml`）

1. `sub2api.image`：`weishaw/sub2api:latest` → `weishaw/sub2api:0.1.177`
2. `sub2api.environment` 增加：
   - `SIMPLE_MODE_CONFIRM=${SIMPLE_MODE_CONFIRM:-}`
   - `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY`（先留空；若容器出站失败再填）
3. 三个服务都加内存上限，避免和 Sonar 抢：
   - `sub2api`：`mem_limit: 768m`
   - `postgres`：`mem_limit: 384m`
   - `redis`：`mem_limit: 128m`
4. `restart: unless-stopped`（官方已是；与 Sonar 一致，不要改成 `always` 以外的花活）

Postgres / Redis **继续不映射宿主端口**。`richer-postgres` 已经占了宿主 `5432`，Sub2API 的库只走 compose 内部 DNS 名 `postgres`。

### 5.2 `.env`（本机生成，chmod 600）

```bash
# 绑定：只给 Tailscale，不给 LAN / 公网
BIND_HOST=100.108.64.126
SERVER_PORT=8080
SERVER_MODE=release
RUN_MODE=simple
SIMPLE_MODE_CONFIRM=true
TZ=Asia/Shanghai

# 密钥：openssl rand -hex 32，四套都写死
POSTGRES_USER=sub2api
POSTGRES_PASSWORD=<generated>
POSTGRES_DB=sub2api
REDIS_PASSWORD=<generated>
JWT_SECRET=<generated>
TOTP_ENCRYPTION_KEY=<generated>

ADMIN_EMAIL=admin@sub2api.local
ADMIN_PASSWORD=<generated-and-kept-offline>

# 共享 12 GiB Colima，压连接池
POSTGRES_MAX_CONNECTIONS=50
POSTGRES_SHARED_BUFFERS=128MB
POSTGRES_EFFECTIVE_CACHE_SIZE=512MB
POSTGRES_MAINTENANCE_WORK_MEM=64MB
DATABASE_MAX_OPEN_CONNS=20
DATABASE_MAX_IDLE_CONNS=5
REDIS_POOL_SIZE=32
REDIS_MIN_IDLE_CONNS=4

# 家用收紧一点
SECURITY_URL_ALLOWLIST_ALLOW_INSECURE_HTTP=false
```

`AUTO_SETUP=true` 已在官方 compose 里：首次启动会建库、跑 migration、写 `data/config.yaml`、按 `ADMIN_*` 建管理员。不需要打开 Setup Wizard。

---

## 6. 访问与客户端

部署完成后：

| 用途 | 地址 |
| --- | --- |
| 管理后台 | `http://mac-mini:8080`（Tailscale MagicDNS） |
| 健康检查 | `http://mac-mini:8080/health` |
| OpenAI 兼容 | `http://mac-mini:8080/v1` |
| Anthropic 兼容 | `http://mac-mini:8080/v1/messages` |

客户端在后台「使用 Key」页按官方指引改 `base_url`。OAuth 加账号走「复制回调 URL 贴回后台」，远程打开管理页也可以，不依赖本机 `localhost` 浏览器。

**本期不做：**

- 公网域名 / HTTPS / Nginx / Caddy / Tailscale Funnel
- 经 `tizi` / `rao-tizi` 反代
- `datamanagementd`（后台「数据管理」可选组件）
- 支付（EasyPay / Stripe）

需要外网 HTTPS 时另开计划。官方 `deploy/EDGE_SECURITY.md` 要求反代关闭 gzip 对 `text/event-stream`、`proxy_read_timeout` ≥ 1800s、`underscores_in_headers on`。

---

## 7. 资源与风险

| 风险 | 处理 |
| --- | --- |
| Colima 12 GiB 里 Sonar 已占 ~2.4 GiB | 整栈上限约 1.3 GiB；不扩 VM |
| 宿主两套 Colima 已接近 32 GiB | 不新增 VM、不拉 Desktop |
| 默认 `0.0.0.0` 把后台暴露给家里 Wi-Fi | 绑 `100.108.64.126` |
| `:latest` 某天拉到不兼容版本 | 钉 `0.1.177` |
| 空 `JWT_SECRET` / `TOTP_ENCRYPTION_KEY` 重启后全员掉线、2FA 失效 | `.env` 写死 |
| 容器出站被墙 | 宿主现已通；启动后用 `docker compose exec` 再测；不行再给容器加代理 |
| 条款 / 封号 | 只自用；不公开面板 |
| 备份 | 数据在本地目录；首次成功后 `tar` 一份到 `~/backups/sub2api-YYYYMMDD/` |

回滚：`docker compose down`（不加 `-v`，本地目录还在）。要清干净再删 `data/` `postgres_data/` `redis_data/`。不影响 Sonar / richer。

---

## 8. 执行步骤（确认后才做）

1. **预检（只读）**：再确认 Colima 在、`8080` 空、Sonar `UP`、磁盘 > 10 GiB。
2. **建目录**：`mkdir -p ~/stacks/sub2api/{data,postgres_data,redis_data}`。
3. **落文件**：下载官方 `docker-compose.local.yml` 和 `.env.example`，打上 §5 补丁；生成本机 `.env`（600）。密钥只留在 mac-mini，不写进本仓库。
4. **拉镜像**：`docker compose pull`（`weishaw/sub2api:0.1.177`、`postgres:18-alpine`、`redis:8-alpine`）。
5. **启动**：`docker compose up -d`。预期影响：多三个容器，占用约 1 GiB；不重启 Colima、不动现有四个容器。
6. **验证**：
   - `docker compose ps` 三个都 healthy
   - `curl -sS http://100.108.64.126:8080/health`
   - 浏览器登录管理后台
   - 从容器内再测一遍上游 HTTPS
   - Sonar `http://mac-mini:9000/api/system/status` 仍是 `UP`，Grafana `:3001` 仍 200
7. **备份**：`tar czf ~/backups/sub2api-$(date +%Y%m%d).tar.gz -C ~/stacks sub2api`（`.env` 会打进包，备份目录 `chmod 700`）。
8. **记时间线**：追加 `docs/operations/mac-mini.md` 并 commit。

升级以后：改 compose 里的 tag → `pull` → `up -d`。不要用管理后台「在线更新」去拉 `latest`。

---

## 9. 需要你拍板的两件事

1. **暴露范围**
   - **A（推荐）**：只绑 Tailscale `100.108.64.126:8080`。办公室 / 手机开 Tailscale 就能用，家里没加 tailnet 的设备打不到。
   - B：和 Sonar 一样绑 `0.0.0.0:8080`，局域网也能直接访问。
2. **运行模式**
   - **A（推荐）**：`simple`，隐藏 SaaS 计费，适合自己或家人共用额度。
   - B：`standard`，完整计费 / 余额 / 充值，以后要给外人发卡再用。

管理员邮箱默认为 `admin@sub2api.local`，密码本机生成后只告诉你一次。

---

## 10. 非目标（除非另说）

- 现在就 `compose up`
- 扩 Colima CPU / 内存 / 磁盘
- 卸 Docker Desktop 残留 `vmnetd`
- 动 `hon` 的 Multica / `colima-multica`
- 公网域名、证书、反代
- 往本仓库提交真实 `.env` 或密码
- 帮你导入具体订阅账号 / OAuth（部署通了再在后台加）
