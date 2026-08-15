---
title: 在 mac-mini 用 Colima / Docker Compose 部署 Sub2API
type: ops
status: completed
date: 2026-08-16
server: mac-mini
---

# 在 mac-mini 用 Colima / Docker Compose 部署 Sub2API

## Summary

在家里的 `mac-mini` 上，用**现有 Colima Docker 引擎**部署 [Wei-Shaw/sub2api](https://github.com/Wei-Shaw/sub2api)（AI 订阅账号 → 统一 API Key 网关）。栈是 `sub2api` + 自带小规格 PostgreSQL + Redis 8。

**2026-08-16 02:04 CST 已执行完成。** 详见 `docs/operations/mac-mini.md`。

### 已锁定（2026-08-16）

| 项 | 决定 |
| --- | --- |
| 暴露 | `0.0.0.0:18080`（本机 + 局域网）。原计划 8080，但宿主 `*:8080` 已被 `hon` 的 `colima-multica` SSH 转发占用 |
| 运行模式 | `RUN_MODE=standard`（完整计费 / 余额 / 充值） |
| 管理员邮箱 | `konghai007@gmail.com` |
| 现有库 | **不**挂到 `sonar-postgres` 或 `richer-postgres` |
| Postgres 形态 | **A**：Sub2API compose 自带小 Postgres + Redis |
| 引擎 | 现有 Colima |
| 目录 | `~/stacks/sub2api/` |
| 镜像 | `weishaw/sub2api:0.1.177` |
| 资源 | 实测约 73 MiB（18 + 50 + 5），上限 768/384/128 MiB |

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

## 2.1 现有 Postgres 能不能共用、该不该共用

现场两个实例：

| 容器 | 版本 | 内存 | 网络 | 宿主端口 | 用途 |
| --- | --- | --- | --- | --- | --- |
| `sonar-postgres` | 17.11 | **189 MiB** | 仅 `sonar-net` | 不映射 | 团队 CI SonarQube |
| `richer-postgres` | 16.15 | **24 MiB** | `richer_default` | `0.0.0.0:5432` | hon 的 DDRicher |

Sub2API 官方要求 PostgreSQL **15+**。两个版本都满足，技术上可以再 `CREATE DATABASE sub2api`。

**结论：能共用，但不该共用现有这两个。**

原因不是「Postgres 不能多租户」，而是这两个实例各自已经有明确主人和生命周期：

1. **`sonar-postgres`**：CI 关键路径。备份、升级、磁盘打满、错误 migration 都会直接让 `http://mac-mini:9000` 挂。它故意不映射宿主端口，就是为了隔离。
2. **`richer-postgres`**：hon 的栈，密码是开发口令 `richer_dev`，而且已经把 5432 暴露到局域网。把带 OAuth token / API Key 的 Sub2API 库塞进去，等于和别人的监控库、弱密码、同一套备份绑死。
3. **跨 compose 网络**：两个库分别在 `sonar-net` / `richer_default`。要共用就得改对方 compose、加 external network，或走 `host.docker.internal:5432`。后者只对 richer 可行，还把 Sub2API 绑在「richer 必须先于它启动」上。
4. **Sub2API 自己的库不轻**：上游有 50+ 条 migration，含 `usage_logs` 分区、仪表盘预聚合、运维监控表。`standard` 模式会持续写用量。这不是再开一个空库那么简单。
5. **真正的内存账**：`richer-postgres` 现在 24 MiB。一个空的 `postgres:18-alpine` 空闲也大约 30–80 MiB。省下来的不是「一个 Postgres」，而是几十兆。Colima 里真正贵的是 Sonar 那 2.2 GiB。
6. **Redis 没有现成的可借**。Sub2API 调度、会话、API Key 缓存都靠 Redis，这一只必须新建。

「每个项目一个 Postgres 很浪费」这句话，在 **10 个服务、每个都按 1GB `shared_buffers` 启动** 时成立。本机现状不是这个：两个库加起来才 ~210 MiB，而且一个是 CI、一个是别人的业务。浪费来自官方 `.env.example` 的大连接池，不是容器个数。

三种做法对照：

| 做法 | 省内存 | 耦合 | 本期建议 |
| --- | --- | --- | --- |
| 挂到 `sonar-postgres` | 约 0 | 绑死 CI | **否** |
| 挂到 `richer-postgres` | 约 0 | 绑死 hon 的栈 + 弱密码 | **否** |
| Sub2API compose 里自带小 Postgres | 多 30–80 MiB | 无 | **本期采用** |
| 另起一台 `apps-postgres`，专给以后的个人应用 | 中长期少容器 | 自己的库之间耦合，不动 Sonar/richer | 以后有第 2、第 3 个个人应用再做 |

Postgres 主进程、`shared_buffers`、wal writer 是按实例付的。两个库共用一台实例确实比两台实例省。但省的前提是：**这台实例是你自己的、用途同类、升级窗口可以一起排**。Sonar 和 richer 都不符合。

---

## 3. 推荐架构

```text
Tailnet 客户端
  Claude Code / Codex / Gemini CLI / 浏览器
           │
           │  http://mac-mini:18080 或 http://192.168.2.170:18080
           │  （0.0.0.0:18080，本机 + 局域网；8080 被 Multica 占用）
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
   - `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY`（先留空；若容器出站失败再填）
   - 不启用 `SIMPLE_MODE_CONFIRM`（已选 `standard`）
3. 三个服务都加内存上限，避免和 Sonar 抢：
   - `sub2api`：`mem_limit: 768m`
   - `postgres`：`mem_limit: 384m`
   - `redis`：`mem_limit: 128m`
4. `restart: unless-stopped`（官方已是；与 Sonar 一致，不要改成 `always` 以外的花活）

Postgres / Redis **继续不映射宿主端口**。`richer-postgres` 已经占了宿主 `5432`，Sub2API 的库只走 compose 内部 DNS 名 `postgres`。

### 5.2 `.env`（本机生成，chmod 600）

```bash
# 绑定：本机 + 局域网（与 Sonar :9000 同策略；mac-mini 无公网入站）
BIND_HOST=0.0.0.0
SERVER_PORT=18080
SERVER_MODE=release
RUN_MODE=standard
TZ=Asia/Shanghai

# 密钥：openssl rand -hex 32，四套都写死
POSTGRES_USER=sub2api
POSTGRES_PASSWORD=<generated>
POSTGRES_DB=sub2api
REDIS_PASSWORD=<generated>
JWT_SECRET=<generated>
TOTP_ENCRYPTION_KEY=<generated>

ADMIN_EMAIL=konghai007@gmail.com
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
| 管理后台 | `http://mac-mini:18080`（Tailscale）或 `http://192.168.2.170:18080`（局域网） |
| 健康检查 | 同上 `/health` |
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
| 宿主 8080 已被 hon/Multica 占用 | 改绑 `18080`；不要去抢 Multica 的转发 |
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

## 9. 决策状态

已全部锁定并执行：

- 暴露：本机 + 局域网；宿主端口因 Multica 占用改为 **18080**
- 模式：`standard`
- 管理员邮箱：`konghai007@gmail.com`
- Postgres：方案 A，自带小库 + Redis
- 不把库挂到现有 `sonar-postgres` / `richer-postgres`

---

## 10. 非目标（除非另说）

- 现在就 `compose up`
- 扩 Colima CPU / 内存 / 磁盘
- 卸 Docker Desktop 残留 `vmnetd`
- 动 `hon` 的 Multica / `colima-multica`
- 公网域名、证书、反代
- 往本仓库提交真实 `.env` 或密码
- 帮你导入具体订阅账号 / OAuth（部署通了再在后台加）
