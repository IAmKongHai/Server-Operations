# mac-mini 运维时间线

## 2026-08-16 17:16 CST - 账号 3 因 Google 国家=中国被拒；账号 4 已通

- 服务器：`mac-mini`
- 操作人：用户排查；`Grok` 只读核对后记录
- 原因：`hxf.xxk@gmail.com`（账号 3）走完验证仍 403。用户确认该 Google 账号国家设为中国，上游不允许调用。另加 `geogle7733@gmail.com`（账号 4）。
- 影响：未改镜像、分组、Key。账号 3 仍 `error` / 不可调度，等改国家后再恢复。
- 验证：
  - 账号 4：`antigravity` / `active` / `schedulable`，进分组 5。
  - `17:16:18` `POST /v1/chat/completions` `gemini-3.7-flash-tiered` 走账号 4 → **200**。
  - 账号 1 调度已重新打开；账号 3 仍是 `Validation required (403)`。
- 结论：Antigravity 订阅号的 Google 账号国家不能是中国。403 先看国家/地区，不要先怀疑 Project ID。改国家后再对账号 3 点「恢复状态」并打开调度。

## 2026-08-16 16:56 CST - 新 Antigravity 号 exhausted：403 验证 + 旧号被关掉

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户新加 `hxf.xxk@gmail.com` 后再调 `/v1`，客户端报 `All available accounts exhausted`，怀疑是没填 GCP Project ID。
- 影响：只读。未改账号、分组、镜像。
- 验证：
  - 16:45:24 后台把账号 1（`konghai007` Antigravity）`schedulable` 关掉；16:37:41 关掉账号 2。
  - 16:45:55 请求只剩账号 3，上游 **403** `Validation required`（Google 要验证该账号），网关把账号 3 标 `error` / 不可调度。
  - 分组 5 里两个 Antigravity 号此后都不可调度，后续再打就会 exhausted。
  - 账号 3 的 `project_id` 实际已有自动值 `celestial-monument-psf6z`；缺的是 `antigravity_project_id`。源码只在 `project_id` 为空时才要求填，这次失败文案不是缺项目。
- 结论：先让 `hxf.xxk` 在浏览器走完 Google 验证 / 打开过 Antigravity，再清 error 并打开调度。要立刻恢复调用，把账号 1 的调度重新打开即可。

## 2026-08-16 16:30 CST - 自打 PR #5640 镜像换上，3.7 Flash 已通

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：官方 `weishaw/sub2api:0.1.177` 没有 Gemini 3.7 变体目录；用户要求用 PR `#5640`（`feat/gemini-3.7` @ `f2a7aeb`）自打镜像换上。
- 选型 / 影响：
  - 源码：`~/src/sub2api-pr5640`（仅该 PR 分支）。
  - 镜像：`sub2api:pr5640-3.7`（`linux/arm64`），版本字符串 `0.1.177-pr5640`。
  - compose `image:` 从 `weishaw/sub2api:0.1.177` 改为本地 `sub2api:pr5640-3.7`。
  - 只重建 `sub2api`。Postgres / Redis / Sonar / richer 未动。
  - 仍保留 `GATEWAY_ANTIGRAVITY_FORWARD_BASE_URL=daily`。
- 备份：`~/stacks/sub2api/docker-compose.yml.bak.pr5640`（换镜像前）、`docker-compose.yml.bak.20260816`。
- 回滚：把 compose `image:` 改回 `weishaw/sub2api:0.1.177`（或拷回 bak），`docker compose up -d sub2api`。数据卷不动。
- 验证：
  - 容器 healthy；`/app/sub2api -version` = `Sub2API 0.1.177-pr5640 (commit: f2a7aeb)`；`GET /health` ok。
  - `/v1/models` 已出现 `gemini-3.7-flash` 及 `-high/-medium/-low/-tiered`。
  - Key `konghai` 仍绑分组 5 `antigravity`。
  - `POST /v1/chat/completions`：
    - `gemini-2.5-flash` → **200**（回归未坏）
    - `gemini-3.7-flash-tiered` → **200**，回复 `OK`（订阅额度，走 Antigravity daily）
    - `gemini-3.7-flash` / `-high` / `-medium` / `-low` → 上游 **404** `Requested entity was not found`
- 结论：客户端把 `model` 改成 **`gemini-3.7-flash-tiered`** 即可。high/medium/low 在当前 daily 端点不存在，不是网关目录问题。计费表尚未收录该模型（日志 `pricing not found`），不影响调用。

## 2026-08-16 16:22 CST - 加上 Antigravity daily 端点后 2.5 通、3.7 仍 404

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户要试 `GATEWAY_ANTIGRAVITY_FORWARD_BASE_URL=daily`，看 3.7 Flash 是否因此可用。
- 影响：
  - `.env` / compose 增加该变量，值为 `daily`。
  - 只重建 `sub2api` 容器。Postgres / Redis / Sonar / richer 未动。
- 备份：`~/stacks/sub2api/docker-compose.yml.bak.20260816`、`.env.bak.20260816`（600）。
- 回滚：把两个 bak 拷回，`docker compose up -d sub2api`。
- 验证：
  - 容器内 `GATEWAY_ANTIGRAVITY_FORWARD_BASE_URL=daily`；healthy。
  - Key 已在分组 `antigravity`。`gemini-2.5-flash` 在 `/v1/chat/completions` 和 `/antigravity/v1beta/...` 均为 **200**。
  - `gemini-3.7-flash` 上游 **404**；`-high/-medium` 被 0.1.177 目录拒掉（404/503）。
- 结论：daily + 美国出口已生效。3.7 要等合入 PR `#5640` 的版本，或自打该 PR。

## 2026-08-16 16:10 CST - 结论：3.7 Flash 不在 Code Assist，要走 Antigravity 变体名

- 服务器：`mac-mini`
- 操作人：`Grok`（资料 + 只读探测）
- 原因：用户目标是 `gemini-3.7-flash`，怀疑 Cloud AI Companion 没开这个模型。
- 影响：只读。未改账号映射、分组、镜像。
- 验证：
  - Gemini `google_one` 号实测只有 2.5 Flash/Pro；3.7-flash 上游 404。
  - Antigravity 账号映射里已有 `gemini-3.7-flash`→同名；Key 当前绑在 Gemini 组，打 `/antigravity/v1beta` 为 503（组里没有 Antigravity 号）。
- 资料：Sub2API PR `#5640`（未合入 0.1.177）写明 Antigravity 上 3.7 要用 `gemini-3.7-flash-high/medium/low/tiered`，基础名 404；建议 `GATEWAY_ANTIGRAVITY_FORWARD_BASE_URL=daily` + 美国出口。

## 2026-08-16 16:00 CST - 实测 Gemini google_one 账号仅 2.5 Flash / 2.5 Pro 可用

- 服务器：`mac-mini`
- 操作人：`Grok`（只读探测）
- 原因：用户问该 Gemini 账号能用哪些模型；`gemini-3.7-flash` 报 Resource not found。
- 影响：只读。对 Key 发了十余次短请求。
- 备份：无。
- 回滚：无变更。
- 验证：`POST /v1/chat/completions` 仅 `gemini-2.5-flash`、`gemini-2.5-pro` 返回 200；`gemini-2.0-flash`、全部 Gemini 3.x（含 3.7-flash）及别名均为上游 404。
- 结论：`/v1/models` 列出的是 Sub2API 默认目录，不是 Code Assist / Google AI Pro 这条线上真实可用的模型。

## 2026-08-16 15:52 CST - 启用 Cloud AI Companion 后 Gemini 调用已通

- 服务器：`mac-mini`
- 操作人：`Grok`（清账号残留 error 后实测）
- 原因：用户已启用 `cloudaicompanion.googleapis.com`，要确认 `/v1/chat/completions` 能否用订阅号。
- 影响：把账号 2 的旧 403 状态清成 `active` / `schedulable=true`。未改分组、Key、容器。
- 备份：无。
- 回滚：账号若再被上游打成 error，后台会自己标红。
- 验证：
  - `POST /v1/chat/completions` 模型 `gemini-2.5-flash` → **200**，回复 `sub2api-ok`。
  - `POST /v1beta/models/gemini-2.5-flash:generateContent` → **200**。
  - 后台「测试连接」仍默认打 `gemini-2.0-flash`，上游 404，可忽略。
- 结论：API 启用有效。客户端继续用 `http://mac-mini:18080/v1`。

## 2026-08-16 15:35 CST - 复查 Sub2API Gemini 账号：GCP 项目未开 Cloud AI Companion API

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户新加 Gemini 账号后，`/v1/chat/completions` 仍报 `All available accounts exhausted`。
- 影响：只读。未改账号、分组、Key、容器。
- 备份：无。
- 回滚：无变更。
- 验证：
  - Key `konghai` 已改绑分组 6 `Gemini`；账号 2 已进该组。
  - 账号 2：`platform=gemini` / `oauth` / `oauth_type=google_one` / `project_id=my-openclaw-super-xxk`，状态 **`error`**、`schedulable=false`。
  - 上游 403：`Gemini for Google Cloud API has not been used in project my-openclaw-super-xxk`，需在该项目启用 `cloudaicompanion.googleapis.com`。
  - 15:34 的客户端请求（`ai-sdk/openai-compatible`，模型 `gemini-3.7-flash`）因此被记成 exhausted。
- 结论：调度已选到 Gemini 账号。失败在 Google 侧 API 未启用，不是 Key 或分组。

## 2026-08-16 15:25 CST - 复查 Sub2API：分组已绑上，404 是路径，exhausted 是上游 429

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户建了 `antigravity` 分组并绑上账号和 Key，仍报 `/antigravity` 404 与 `/v1` `All available accounts exhausted`。
- 影响：只读。未改分组、账号、Key、容器。
- 备份：无。
- 回滚：无变更。
- 验证：
  - `account_groups`：账号 1 → 分组 5；Key `konghai` 的 `group_id=5`。绑定正确。
  - 用户客户端是 `ai-sdk/openai-compatible`，打的是 `POST /v1/chat/completions` 模型 `gemini-3.7-flash`。
  - `POST /antigravity/v1/chat/completions` 和 `/antigravity/chat/completions` 为 **404**（该前缀只接 Anthropic `/v1/messages` 和 Gemini `/v1beta/`）。
  - 绑定后同一 Key 的 `/v1/chat/completions` 已能选到 Antigravity 账号，上游返回 **429**，网关对外写成 `All available accounts exhausted`。
  - `POST /antigravity/v1/messages` 同样打到上游 429。
- 结论：调度已通。404 是 OpenAI 客户端不该用 `/antigravity` 当前缀；exhausted 是 Google/Antigravity 限流，不是 Key 或分组错了。

## 2026-08-16 14:45 CST - 只读探测 Sub2API Antigravity Key：鉴权通、推理 503

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户已登录 Antigravity，要用自己的 Key 验证能否真实调用。
- 影响：只读。未改账号、分组、Key、容器。
- 备份：无。
- 回滚：无变更。
- 验证：
  - `GET /v1/models` 200，列出 10 个 Claude 模型。
  - `POST /v1/messages`、`/antigravity/v1/messages`、`/v1/chat/completions`、`/antigravity/v1beta/...generateContent` 均为 **503** `No available accounts`。
  - 库内：Antigravity OAuth 账号 `id=1` 为 `active` / `schedulable`，但 `account_groups` 为空；Key `konghai` 绑在分组 `default`（`anthropic`）。
- 结论：网关和 Key 可用，缺的是「账号进组」。`base_url=http://mac-mini:18080/v1` 还要开 Antigravity 混合调度，否则 Claude 应走 `http://mac-mini:18080/antigravity`。

## 2026-08-16 02:04 CST - 用 Colima 部署 Sub2API 0.1.177（自带小 Postgres + Redis）

- 服务器：`mac-mini`
- 操作人：`Grok`（远程部署），用户确认方案 A 及暴露/模式
- 原因：在家里用 Docker 跑 Sub2API，统一接入 Claude / OpenAI / Gemini / Grok 订阅。
- 选型：官方 compose 本地目录版；镜像钉 `weishaw/sub2api:0.1.177`；Postgres / Redis 跟在同一 compose，不共用 `sonar-postgres` / `richer-postgres`。
- 影响：
  - 新增容器 `sub2api` / `sub2api-postgres` / `sub2api-redis`，`restart: unless-stopped`。
  - 宿主端口 **`0.0.0.0:18080`**。原计划 8080，但 `hon` 的 `colima-multica` SSH 转发已占 `*:8080`（Multica `/healthz`）；未动 hon 的端口。
  - 内存实测约 73 MiB（上限 768/384/128 MiB）。Sonar / richer 未改。
- 备份：`~/backups/sub2api-20260816.tar.gz`（600，含 `.env`）。
- 回滚：`cd ~/stacks/sub2api && docker compose down`。数据在 `data/` `postgres_data/` `redis_data/`，不要加 `-v`。清干净再删这三个目录。
- 变更时序：
  1. `~/stacks/sub2api/` 落 compose + 600 `.env`（`RUN_MODE=standard`，管理员 `konghai007@gmail.com`）。
  2. `docker compose pull` + `up -d`。AUTO_SETUP 建库、建管理员、拉定价数据。
  3. 发现宿主 8080 打到 Multica，改 `SERVER_PORT=18080` 后只重建 `sub2api` 容器。
- 验证：
  - 三容器 healthy；`http://127.0.0.1:18080/health`、`/setup/status`、UI `/`、局域网 `192.168.2.170:18080`、Tailscale `100.108.64.126:18080` 均为 200。
  - 管理员登录 API `POST /api/v1/auth/login` 返回 200。
  - 容器内可访问 Anthropic / OpenAI / xAI。
  - Sonar `UP` 26.3.0；Grafana `:3001` 200；`127.0.0.1:8080/healthz` 仍是 Multica。
- 计划：`docs/plans/2026-08-16-001-ops-mac-mini-sub2api-deploy-plan.md`
- 访问：`http://mac-mini:18080` 或 `http://192.168.2.170:18080`。客户端 `base_url` 指 `http://mac-mini:18080/v1`。

## 2026-08-15 02:51 CST - runner LaunchDaemon 已装上；全员注销后 GitHub 仍 online

- 服务器：`mac-mini`
- 操作人：`konghai`（sudo 安装脚本后注销）、`Grok`（远程核对）
- 原因：让 CI runner 和 Colima / Tailscale 一样，不依赖图形登录。
- 影响：`mac-mini-sonar-1..4` 现为 `system/actions.runner.cypressoai.mac-mini-sonar-N`，以 `konghai` 跑 `runsvc.sh`。旧 Agent plist 仍在 `~/Library/LaunchAgents.disabled-20260815/`。
- 备份：上述 disabled 目录。
- 回滚：`sudo launchctl bootout system/actions.runner.cypressoai.mac-mini-sonar-N` 并删对应 `/Library/LaunchDaemons` plist；需要时把 disabled 目录里的 Agent 移回 `~/Library/LaunchAgents`。
- 验证（控制台用户 `root`，`who` 空）：
  - 四个 job `state=running`，各有 `Runner.Listener --startuptype service`。
  - GitHub：四个均为 `online`；当时 1 和 3 `busy=true`（已在接活）。
  - Sonar 仍 `UP`，Tailscale 仍 `100.108.64.126`。

## 2026-08-15 02:46 CST - 准备把 mac-mini-sonar-1..4 改成 LaunchDaemon

- 服务器：`mac-mini`
- 操作人：`Grok`（挪走 Agent、写脚本）、待 `konghai` 本机 sudo
- 原因：全员注销后 runner 不在，和 Colima 同一类问题。
- 影响：四个 LaunchAgent plist 已移到 `~/Library/LaunchAgents.disabled-20260815/`（登录也不会再拉）。Daemon 尚未装，runner 仍停。
- 备份：上述 disabled 目录里的原 plist。
- 回滚：把 plist 移回 `~/Library/LaunchAgents`，不要装 Daemon。
- 脚本：`~/Downloads/install-mac-mini-runner-daemons.sh`。恢复脚本已改为 kickstart `system/…`。不要再用 `./svc.sh install`。
- 验证：安装脚本尚未执行。

## 2026-08-15 02:44 CST - 全员注销后验证：Tailscale + Colima + 4 个容器仍在

- 服务器：`mac-mini`
- 操作人：`konghai`（跑完 daemon 脚本后注销所有用户）、`Grok`（远程验证）
- 原因：确认不再依赖任何人的图形会话。
- 影响：只读。`/dev/console=root`，`who` 为空。
- 备份：无。
- 回滚：无变更。
- 验证：
  - `ssh mac-mini`（`100.108.64.126`）通；`tailscaled` LaunchDaemon 在线，MagicDNS `mac-mini`。
  - `system/com.konghai.colima` running；四个容器 healthy / Grafana 200；Sonar `UP` 26.3.0。
  - `mac-mini-sonar-1..4` 的 `Runner.Listener` **不在**（仍是 LaunchAgent，注销后会停）。这是预期，尚未改 runner。

## 2026-08-15 02:38 CST - 仅迁正在跑的 4 个容器到 Colima；Sonar / richer 已 UP

- 服务器：`mac-mini`
- 操作人：`Grok`（导出/导入、切引擎）、`konghai`（本机开过 Docker Desktop 以便导出）
- 原因：Docker Desktop 绑 GUI；只把当前在跑的服务迁到 Colima（vz / 6 CPU / 12 GiB / 100 GiB 盘）。
- 影响：
  - 迁了 `sonarqube`、`sonar-postgres`、`richer-grafana`、`richer-postgres`。其它已停用容器未迁。
  - 备份在 `~/backups/colima-migrate-20260815/`（pg_dump + named volume tar，600）。
  - richer 补了 `~/stacks/richer/docker-compose.yml`；postgres 改为 named volume `richer_pg_data`。
  - Docker context 默认 `colima`。Desktop 已强制退出，`AutoStart` 保持 false。App 先留着回滚。
  - `~/.zshenv` 把 `/opt/homebrew/bin` 提前，并默认 `DOCKER_HOST` 指向 Colima socket。
- 备份：上述目录。Desktop 侧原容器只是 stop，未 rm。
- 回滚：`colima stop` → 开 Docker Desktop → `docker context use desktop-linux` → `docker start` 原来的四个容器。
- 验证：
  - `http://127.0.0.1:9000/api/system/status` → `UP` / 26.3.0.120487
  - Grafana `:3001/login` HTTP 200
  - sonar 库 125 张表；richer 库 15 张表
- 未完成：Colima 还不是 LaunchDaemon。安装脚本已放到 `~/Downloads/install-colima-daemon.sh`，需本机 `sudo` 执行（会短暂停一下再由 launchd 拉起）。

## 2026-08-15 02:22 CST - MagicDNS 短名 mac-mini 已收回

- 服务器：`mac-mini`
- 操作人：`konghai`（管理后台改名）、`Grok`（验证）
- 原因：把 `mac-mini-1` 改回 `mac-mini`，恢复 CI / 文档里的 `http://mac-mini:9000`。
- 影响：只读验证 + 文档。未改 daemon。
- 备份：无。
- 回滚：无变更。
- 验证：`DNSName=mac-mini.taila93443.ts.net`；本机 `dscacheutil` 解析到 `100.108.64.126`；`tailscale ping mac-mini` 约 3ms（直连局域网）。`mac-mini-1` 已不存在。

## 2026-08-15 02:20 CST - 节点 IP 已改回 100.108.64.126；MagicDNS 仍是 mac-mini-1

- 服务器：`mac-mini`
- 操作人：`konghai`（管理后台改 IP、删旧节点）、`Grok`（改 hostname、ssh config、验证）
- 原因：用户已删除旧机器，并把新节点 IPv4 改回原来的 `100.108.64.126`，避免改文档和 CI 里的硬编码。
- 影响：本机 `Host mac-mini` 改回 `100.108.64.126`；`ssh mac-mini` 测通。`tailscale set --hostname=mac-mini` 已执行，但控制面显示名仍是 `mac-mini-1`，MagicDNS `mac-mini` 尚无法解析。
- 备份：无。
- 回滚：IP 已回到原值，无需回滚。
- 验证：
  - `tailscale ip -4` = `100.108.64.126`，`Online=true`，`WantRunning=true`
  - `ssh mac-mini` → `SSH_OK`
  - `tailscale ping mac-mini` → `lookup mac-mini: no such host`；`mac-mini-1` 可 ping
- 下一步：在管理后台把机器名从 `mac-mini-1` 改成 `mac-mini`，短名才会回到 `http://mac-mini:9000`。然后装 Colima。Docker Desktop 当前未在跑。

## 2026-08-15 02:15 CST - Homebrew tailscaled 已登录；新 IP 100.86.35.24，短名暂为 mac-mini-1

- 服务器：`mac-mini`
- 操作人：`konghai`（本机 `sudo brew services start` + `tailscale up`）、`Grok`（装 formula、改本机 ssh config、验证）
- 原因：换成登录前也能跑的开源 `tailscaled`，妻子解 FileVault 后办公室仍能经 Tailscale SSH。
- 影响：
  - GUI Standalone 已卸。Homebrew `tailscale` 1.102.2 以 LaunchDaemon `homebrew.mxcl.tailscale` 跑（root，`KeepAlive` + `RunAtLoad`，含 `System`/`LoginWindow`）。
  - 新节点 `100.86.35.24`，`WantRunning=true`，`--operator=konghai`，`--hostname=mac-mini`，`CorpDNS=true`。
  - 旧节点 `100.108.64.126` / DNS `mac-mini` 仍在 tailnet（offline）。新机因此叫 `mac-mini-1`。未删旧节点前，MagicDNS `mac-mini` 和 CI 的 `http://mac-mini:9000` 会指到已死的旧 IP。
  - 本机 `~/.ssh/config` 的 `Host mac-mini` 已改为 `100.86.35.24`；`ssh mac-mini` 已测通。
- 备份：无（新节点重新登录，未搬 GUI 状态）。
- 回滚：停 daemon：`sudo brew services stop tailscale`；重装 GUI 前先卸 formula。旧 IP 不可用。
- 验证：
  - `launchctl`：`system/homebrew.mxcl.tailscale` running，pid 12650。
  - 本机 `tailscale ping mac-mini-1` → `100.86.35.24` 约 14ms（走局域网）。
  - `ssh mac-mini`（新 IP）返回 `SSH_OK`。
- 下一步：在 [Tailscale 机器列表](https://login.tailscale.com/admin/machines) 删除旧的 `mac-mini`（`100.108.64.126`），再 `tailscale set --hostname=mac-mini`，让短名回到 `mac-mini`。然后才迁 Colima。

## 2026-08-15 02:05 CST - 用户确认 ziyi 已在 FileVault；GUI Tailscale 必须人在本机卸

- 服务器：`mac-mini`
- 操作人：`Grok`（只读 + 本机加 SSH 兜底）+ 用户决策
- 原因：用户确认妻子账户已启用文件保险柜，同意 Colima + Homebrew `tailscaled`，并问 GUI 版要不要手动卸载。
- 影响：未卸 Tailscale、未装 Colima。仅在**本机** `~/.ssh/config` 增加 `Host mac-mini-lan`（`ProxyJump pve` → `192.168.2.170`），供切换窗口断 Tailscale 时从办公室绕回家。
- 备份：改 ssh config 前可从 Time Machine / 编辑器撤销；未动服务器。
- 回滚：删掉 `Host mac-mini-lan` 段。
- 结论：
  - GUI Standalone（`/Applications/Tailscale.app` + 系统扩展）和 brew `tailscaled` **不能并存**，必须卸 GUI。
  - 官方步骤要拖 App 进废纸篓、确认卸扩展、清空废纸篓、重启。系统扩展对话框和重启必须有人在机前；远程无 passwordless sudo。
  - `Host mac-mini` 现指向 `100.108.64.126`；重装 OSS daemon 后节点 IP 预期会变，切完要改 HostName，并用 `--hostname=mac-mini` 保住短名。
- 尚未执行卸载或 `brew install`。等用户约定窗口（妻子在家或本人回家）再切。

## 2026-08-15 01:48 CST - 只读确认：ziyi 登录后当前 Tailscale 不会为公司 SSH 自动起来

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户在办公室只靠 Tailscale 连回家，问掉电后妻子登 `ziyi`、再注销，挂在 `konghai` 下的 Tailscale 会不会起来。
- 影响：只读。未改 Tailscale / FileVault / 登录项。
- 备份：无。
- 回滚：无变更。
- 验证：
  - 装的是 Standalone `com.tailscale.ipn.macsys` 1.102.2，不是 App Store。
  - 两个进程：root 的 `io.tailscale.ipn.macsys.network-extension`（数据面）、`konghai` 的 `Tailscale.app`（菜单栏）。`WantRunning=true`，`LoggedOut=false`，节点 `100.108.64.126` / `k@cypresso.ai`。
  - 今日 `kern.boottime=00:15:33`，两进程均 `00:16:36` 启动，与 `konghai` 控制台 00:16 登录对齐。
  - 官方 [macos-variants](https://tailscale.com/docs/concepts/macos-variants)：Standalone `Run before login = no`；开源 `tailscaled` 才是 `yes`。[unattended](https://tailscale.com/docs/how-to/run-unattended) 写明 macOS 还不能当系统服务跑。
- 结论：妻子只登她的账户，办公室经 Tailscale SSH 回家不可靠。08-13 GUI 崩了还能打到 `100.108.64.126`，是因为隧道当时已经建好。要「解完盘就能从公司连」，需另把 Tailscale 改成 `tailscaled` LaunchDaemon。
- 计划已更新：`docs/plans/2026-08-15-001-ops-mac-mini-headless-docker-plan.md`

## 2026-08-15 01:35 CST - 敲定 Colima 仍用 konghai；掉电不能 SSH 解 FileVault

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）+ 用户决策
- 原因：用户确认不建专用 Colima 用户；掉电由 `ziyi` 在开机屏解锁；并问能否 SSH 进 `konghai` 远程解 FileVault。
- 影响：只读。未建用户、未改 FileVault、未装 Colima。
- 备份：无。
- 回滚：无变更。
- 结论：
  - Colima 计划维持「装在 `konghai` + LaunchDaemon `UserName=konghai`」。
  - 冷启动 / 掉电：**不能** SSH 解锁。盘未开时 sshd 不在。`ziyi`（或任何已启用的 FileVault 用户）必须在机前输一次密码；解完后可 SSH `konghai`，LaunchDaemon 即可拉 Colima。
  - `pmset autorestart=1`：来电会自动开机，然后停在 FileVault 屏等人口令。
  - 远程看不到 `ziyi` 的 AuthenticationAuthority（无 sudo / `fdesetup list`）。执行迁移前要在本机确认她已在解锁名单，否则开机屏只有 `konghai`。
- 计划已更新：`docs/plans/2026-08-15-001-ops-mac-mini-headless-docker-plan.md`

## 2026-08-15 01:10 CST - 只读评估：Docker Desktop 无法无登录常驻，推荐换 Colima

- 服务器：`mac-mini`
- 操作人：`Grok`（只读排查 + 写计划）
- 原因：用户要把 mac-mini 当服务器用——开机后不登录图形界面，容器也要起来；并嫌 Docker Desktop GUI 费资源。结合 2026-08-13 WindowServer 崩溃后 Desktop 连带掉线、以及今天 00:15 重启后部分容器没起来。
- 影响：只读。未改 Docker / 容器 / FileVault / 登录项 / runner。
- 备份：无。
- 回滚：无变更。
- 做了什么：
  1. 核对引擎、socket、Desktop 设置、FileVault、自动登录、容器 restart policy、compose 归属、runner LaunchAgent。
  2. 把结论写成 `docs/plans/2026-08-15-001-ops-mac-mini-headless-docker-plan.md`。
- 验证（只读快照，约 01:05 CST）：
  - Docker Desktop 4.82.0，VM **8 CPU / 24 GiB**，`AutoStart=true` 但会弹出 GUI；`/var/run/docker.sock` 链到 `konghai` 的 Desktop socket，`hon` 在 `docker` 组。
  - FileVault **开着**，自动登录未开。冷启动必须有人在登录窗解锁，这不是 Docker 能绕开的。
  - 当时在跑：`sonarqube` / `sonar-postgres`（healthy）、`richer-grafana` / `richer-postgres`。`acquilang-postgres`、`multica-*`、`cypresso-okr-*` 虽有 restart policy，重启后未保持运行。
  - 四个 `mac-mini-sonar-*` runner 仍是 LaunchAgent（`ProcessType=Interactive`），和 Desktop 一样绑 GUI 会话。
- 结论：Docker Desktop 没有 headless / LaunchDaemon 模式，不能靠「开机脚本 + 登录自启」解决注销或 WindowServer 崩溃。推荐换成 **Colima + LaunchDaemon**，有状态卷导出导入后卸 Desktop。未执行迁移，等用户确认。
- 计划：`docs/plans/2026-08-15-001-ops-mac-mini-headless-docker-plan.md`

## 2026-08-15 00:42 CST - 重启后复查：ToDesk 未回潮；SonarQube 容器未自动拉起

- 服务器：`mac-mini`
- 操作人：`konghai`（重启）、`Grok`（只读复查）
- 原因：卸载 ToDesk 后用户重启，确认残留是否被 launchd 拉回，并看 CI 相关服务是否起来。
- 影响：只读。未启动容器、未改配置。
- 备份：无。
- 回滚：无变更。
- 验证：
  - `kern.boottime` = `2026-08-15 00:15:33`，uptime 约 27 分钟；控制台用户 `konghai` 于 `00:16` 登录。
  - ToDesk 进程、App、plist、PrivilegedHelper、HAL 驱动、pkgutil 收据、声音设备名均不存在。默认输出仍是 LG UltraFine。
  - launchd 仍有三条 `com.youqu.todesk.* => disabled` 空标签，无对应文件，重启后也未启动。
  - `mac-mini-sonar-1..4` 的 `Runner.Listener` 均在 `00:16` 拉起。
  - Docker Desktop 已起来；当时在跑的只有 `acquilang-postgres`、`richer-grafana`、`richer-postgres`。
  - `sonarqube` 为 `Exited (137)`（重启被 SIGKILL），`sonar-postgres` 为 `Exited (0)`，本机 `127.0.0.1:9000` connection refused。未代为 `docker start`。
- 结论：ToDesk 卸载在重启后仍然干净。SonarQube 需手动拉起后 CI 才能扫。

## 2026-08-15 00:12 CST - ToDesk 已彻底卸载，复查通过

- 服务器：`mac-mini`
- 操作人：`konghai`（本机 `sudo /tmp/uninstall-todesk.sh --apply`）、`Grok`（远程核对日志）
- 原因：清掉自 2026-07-21 起常驻、累计约 890 小时 CPU 的 ToDesk 服务，避免快切用户时再截鼠标。
- 影响：`ToDesk.app`、系统服务、LoginWindow Session Proxy、虚拟声卡、各用户配置和安装收据已删除。默认输出仍是 LG UltraFine。Docker / SonarQube / runner 未动。
- 备份：`/Library/Preferences/Audio/com.apple.audio.SystemSettings.plist.bak.20260815`
- 回滚：重装 ToDesk；音频可用上述 bak 还原后再 `killall coreaudiod`。
- 日志要点（`/tmp/uninstall-todesk.log`，`00:12:05` 起 `uid=0`）：
  - bootout 成功：`system/com.youqu.todesk.{service,UninstallerHelper,UninstallerWatcher}`、`gui/501` 的 desktop/startup
  - 删除 App、5 个 plist、PrivilegedHelper、HAL `ToDeskOutputDriver.driver`、系统 Application Support/Logs，以及 `claw_bot` / `coding` / `hon` / `konghai` / `ziyi` 家目录里的 ToDesk 数据
  - forget：`com.youqu.todesk.mac` / UninstallerClient / UninstallerHelper
- 验证（00:13 CST 远程复查）：
  - 进程无 `ToDesk_Service` / `ToDesk_Session_Proxy`
  - `/Applications/ToDesk.app`、HAL 驱动、pkgutil 收据均不存在
  - 声音设备列表无 ToDesk；默认输出 LG UltraFine
  - launchd 仅剩三条 `disabled` 空标签，无对应 plist，不会再启动
- 建议：方便时重启一次 mac-mini，让 launchd 空标签和 coreaudiod 状态彻底掉干净。重启前确认 Sonar / runner 窗口可接受。

## 2026-08-15 00:09 CST - 图形密码框通过后脚本未以 root 执行，改为走 sudo

- 服务器：`mac-mini`
- 操作人：`Grok`（改脚本）、`konghai`（在图形界面多次输入密码）
- 原因：用户在终端跑 `~/Downloads/uninstall-todesk.sh`，图形密码框弹出且密码正确，但脚本仍报「无法弹出密码框或你取消了」。
- 影响：ToDesk 仍在跑，尚未删除。已覆盖下载目录和 `/tmp` 里的脚本。
- 备份：无。
- 回滚：无卸载发生。
- 排查：`/tmp/uninstall-todesk.log` 只有 `mode=auto` / `user=konghai` 的扫描，没有任何 `mode=apply` 或 `uid=0`。说明密码过了，但 `osascript with administrator privileges` 没能执行位于「下载」的脚本（TCC / `com.apple.macl`）。错误信息把所有 osascript 失败都说成「取消密码框」，是误导。
- 修复：脚本改为终端里 `exec sudo ... --apply`；图形提权只跑 `/tmp` 副本，并打印系统原始错误。
- 用户下一步：
  ```bash
  sudo /tmp/uninstall-todesk.sh --apply
  ```

## 2026-08-15 00:00 CST - 把 ToDesk 卸载脚本放到下载目录

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户要在图形界面自己执行卸载，需要在「下载」里能看到脚本。
- 影响：只新增 `~/Downloads/uninstall-todesk.sh`（755），未跑卸载、未改服务。
- 备份：无。
- 回滚：删掉该文件即可。家目录和 `/tmp` 里先前那两份仍在。
- 验证：`ls` 显示 `-rwxr-xr-x`，SHA-256 与仓库脚本一致。
- 用户下一步：打开终端执行 `~/Downloads/uninstall-todesk.sh`，在密码框输入本机登录密码；卸完建议重启。

## 2026-08-14 23:58 CST - 扫到完整 ToDesk 仍在跑，脚本已就位，远程 sudo 未执行

- 服务器：`mac-mini`（SonarQube 宿主、self-hosted runner；macOS 26.5.2）
- 操作人：`Grok`
- 原因：本机 MacBook Air 已确认 ToDesk 残留会导致快切用户后鼠标卡死；用户要求在 `mac-mini` 上同样彻底卸载。
- 影响：本次**未改** ToDesk、Docker、SonarQube、runner 或音频。只把卸载脚本拷到该机。
- 备份：无（尚未删除任何文件）。
- 回滚方式：无变更。
- 只读扫描：
  - `/Applications/ToDesk.app` 仍在；`ToDesk_Service` pid 604 自 2026-07-21 起运行，CPU 累计约 890 小时。
  - `ToDesk_Session_Proxy` 挂在 `konghai`；launchd 还为 uid 501/503/505（`konghai` / `ziyi` / `coding`）注册了 `ToDesk_Service_*`。
  - 系统 plist、PrivilegedHelper、HAL `ToDeskOutputDriver.driver`、pkg `com.youqu.todesk.mac` 均在。当前默认输出已是 LG UltraFine，设备列表里没有 ToDesk 虚拟声卡名。
  - 远程 `osascript` 提权返回「管理员用户名或密码不正确」(-60007)，SSH 也无 passwordless sudo。
- 脚本位置（该机，2026-08-15 00:00 已再拷到下载目录）：`/Users/konghai/Downloads/uninstall-todesk.sh`（与仓库 `scripts/uninstall-todesk.sh` 相同）。在 mac-mini 图形会话的「终端」执行：
  ```bash
  ~/Downloads/uninstall-todesk.sh
  ```
  或 `sudo ~/Downloads/uninstall-todesk.sh --apply`。卸完建议重启再确认进程和 HAL 都消失。
- 验证结果：卸载尚未执行。背景见 `docs/solutions/best-practices/todesk-incomplete-uninstall-fast-user-switch-mouse-lag-2026-08-14.md`。

## 2026-08-13 10:49 CST - 只读确认 SonarQube 正常，CI 首跑失败在 runner 的 Tailscale 链路

- 服务器/设备：`mac-mini`（SonarQube 宿主）；对照 `umacbook-pro-1`
- 操作人：`Codex`
- 原因：排查 [iCare-public-frontend attempt 1 Job 94327015274](https://github.com/cypressoai/iCare-public-frontend/actions/runs/31661331203/job/94327015274) 在 Web 页面可访问时仍报 Sonar server connect timeout 的原因。
- 影响：仅通过 GitHub API / Job 日志和 SSH 检查 SonarQube 容器状态、HTTP/访问日志及 runner 的 DNS、路由和 Tailscale 历史日志；未改 Docker、SonarQube、Tailscale、runner、workflow 或业务代码，未触发重跑。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：
  1. 检查 `sonarqube` / `sonar-postgres` 当前状态、`sonarqube` start time、restart count、容器健康探针及 10:35–10:45 UTC 访问日志。
  2. 对照 `umacbook-pro-1` 在失败时刻的 TCP SYN、Tailscale DERP/peer 日志与当前 HTTP 连通性。
  3. 核对同一 workflow attempt 2 的 [Job 94327302116](https://github.com/cypressoai/iCare-public-frontend/actions/runs/31661331203/job/94327302116) 和服务端 ScannerCLI 访问记录。
- 验证结果：
  - `sonarqube` 自 `2026-08-12 17:26:12Z` 起持续运行，检查时 `healthy`、`RestartCount=0`；10:35–10:45 UTC 每 15 秒的 `/api/system/status` 健康探针均为 HTTP 200，故障窗口没有服务重启或失活证据。
  - attempt 1 的 ScannerCLI 于 `10:40:08` 从 `umacbook-pro-1` 发起连接，但 Tailscale 记录目标 peer `lastRecv=6h19m1s`，5 秒内 6 个 SYN 均无响应；Sonar access log 没有收到对应请求。因此报错发生在 HTTP 建连前，不涉及 token、Quality Gate 或项目扫描。
  - Tailscale 在该连接窗口将 runner 的 home DERP 从 `derp-900` 切到 `derp-17`；attempt 2 扫描前重新为目标 peer 建立 `derp-900` 连接。服务端于 `10:42:17` 收到同版本 ScannerCLI 的 `/api/v2/analysis/version` 并返回 HTTP 200，attempt 2 最终 Quality Gate `PASSED`、workflow 成功。
  - 当前宿主本地访问 API 约 `0.006s`、runner 经 Tailscale 约 `0.39s` 均能立即获得 HTTP 响应。结论：**SonarQube 服务端在本次 10:40 失败窗口内正常；失败由 `umacbook-pro-1 → mac-mini` 的 Tailscale peer/DERP 瞬断触发，链路随后自动恢复。**

## 2026-08-13 01:35 CST - 恢复 Docker Desktop 并确认并非整机重启

- 服务器：`mac-mini`（SonarQube 宿主、self-hosted runner `mac-mini-sonar-1..4`）
- 操作人：`konghai`（现场登录并启动 Docker Desktop）、`Codex`（只读排查与验证）
- 原因：00:55 CST 起 iCare SonarQube CI 无法连接；现场重新登录 macOS 后启动 Docker Desktop，SonarQube 恢复，但观察到类似机器重启后的登录界面，需确认是否发生整机重启及其原因。
- 影响：
  - `2026-08-13 00:37:46`，macOS `WindowServer` 被内核终止，`konghai` / `coding` / `ziyi` 三个 GUI session 被强制注销；依赖 `konghai` GUI session 的 Docker Desktop 与 `mac-mini-sonar-1..4` LaunchAgent runner 随之停止。
  - Docker Desktop 停止期间 `sonarqube` / `sonar-postgres` 不可用，导致至少 iCare-backend run `31617573433` 与 `31617651468` 的 SonarScanner 无法查询 server version；本机四个 runner slot 也退出调度池。
  - macOS 内核、SSH 和主机网络始终在线，未发生整机重启或断电。
- 备份：无（现场仅启动既有 Docker Desktop；后续调查均只读，未改配置或数据）。
- 回滚方式：可退出 Docker Desktop 回到故障前状态，但会再次停止 SonarQube 及本机所有 Docker 容器，不建议作为常规回滚。
- 变更时序：
  1. `00:37:46.369`，内核记录旧 `WindowServer`（PID 445）已分配 **305,834 Mach ports**：`caught allocating too many mach ports`，随即触发 fatal exception，并以 signal 9 强制结束进程。
  2. 三个 `loginwindow` session 同时记录 `directLogoutReason:WindowServerExited`，证明是 WindowServer 先退出、系统再强制注销用户，并非用户主动注销。
  3. Docker Desktop 日志同步记录 `terminated signal received`，随后显式关闭 Docker API socket、请求 VM poweroff，并记录 `dockerd exited due to explicit Stop() call`；因此 Docker 是 GUI session 退出的受害者，不是 WindowServer 故障发起者。
  4. `00:37:46` 后系统自动拉起新 `WindowServer` / `loginwindow`，停留在登录界面；`01:21` 远程检查时 `/dev/console=root`、无 Docker socket、TCP 9000 无监听。
  5. `01:25`，`konghai` 现场登录并启动 Docker Desktop；Docker backend、四个 runner listener 与 Sonar 容器相继恢复。
- 根因判断：
  - **不是整机重启**：`kern.boottime` 仍为 `2026-07-21 08:53:53`，uptime 22 天以上；`last reboot`、`pmset` 与 panic / shutdown reports 均无本时段重启记录。
  - **直接根因**：运行 22 天的 WindowServer 累计耗尽 Mach port 配额，被内核保护机制 SIGKILL，造成全部 GUI session 重建。
  - **不是 OOM / 电源故障**：内核明确报 port exhaustion；无 jetsam、memory-pressure kill、panic 或掉电证据，swap 使用仅约 6.69MB。
  - **底层泄漏源暂不能唯一定位**：故障前 SkyLight 持续报 `CGXRegisterForPortNotification: mach_port_request_notification: invalid argument`，临近退出又每秒报 `_CGXPackagesSetWindowConstraints: Invalid window`，说明 WindowServer 的 port / window bookkeeping 已异常；但保留日志未携带具体客户端身份。`konghai` / `coding` / `ziyi` 三个长期 Fast User Switching session 会扩大图形状态面，只能视为风险放大因素，不能据此认定某个用户或 App 是泄漏源。
- 验证结果：
  - 新 `WindowServer` PID 29298 当前约 **2,349 ports**，已从异常的 305,834 回到正常低位。
  - `sonar-postgres`、`sonarqube` 均为 `healthy`；本机 `http://127.0.0.1:9000/api/system/status` 与 `mas-go-dev` 经 `http://mac-mini:9000/api/system/status` 均返回 HTTP 200、`status=UP`。
  - `mac-mini-sonar-1..4` 的 `Runner.Listener` 均于 `01:25:54–01:25:55` 拉起。
  - 本次未重跑失败的 GitHub Actions Job，避免在诊断之外改变 PR check 状态。
- 后续建议（未执行）：定期采样 WindowServer port 数；若持续增长，保留增长窗口内的进程 / WindowServer 连接快照以定位泄漏客户端；尽量减少长期并存的 Fast User Switching session。由于 Docker Desktop 和 runner 均绑定 GUI session，还应另行评估登录会话退出后的自动恢复与告警，避免 Sonar 静默下线。

## 2026-08-13 01:21 CST - 只读确认 SonarQube 因 Docker Desktop 未运行而不可达

- 服务器：`mac-mini`（SonarQube 宿主；对照 `mas-go-dev-ci-2`、`umacbook-pro-2`）
- 操作人：`Codex`
- 原因：排查 [iCare-backend Job 94190148086](https://github.com/cypressoai/iCare-backend/actions/runs/31617573433/job/94190148086) 的 SonarScanner server version 查询失败。
- 影响：只读检查 Docker API、相关进程、TCP 9000、SonarQube HTTP 状态、宿主机 uptime 与 Actions 对照日志；未启动 Docker Desktop、未启动或重启容器、未改 runner / Sonar / workflow / 代码，未重跑 Job。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：
  1. 从 `mas-go-dev` 验证 `mac-mini` MagicDNS 解析正常，但 `http://mac-mini:9000/api/system/status` connection refused。
  2. 在本机检查 Docker CLI socket、Docker / SonarQube 进程、TCP 9000 listener 与最近 reboot 记录。
  3. 对照 `umacbook-pro-2` 上 run `31617651468`：另一台 runner 同样在测试与 coverage 成功后无法查询 SonarQube server version。
- 验证结果：
  - 宿主机已连续运行 22 天，本次故障不是 mac-mini 重启造成。
  - Docker Desktop 主进程不在；`/Users/konghai/.docker/run/docker.sock` 不存在，Docker API 无法连接，TCP 9000 无监听，`curl http://127.0.0.1:9000/api/system/status` connection refused；仅 `com.docker.vmnetd` 特权 helper 仍在。
  - 2026-08-12 23:53 CST 前的 run `31614002062` 可成功完成 Sonar 扫描；2026-08-13 00:55 CST 的目标 Job 及 01:17 CST 的 `umacbook-pro-2` Job 均报相同连通性错误。结论：**mac-mini 上 Docker Desktop 在该窗口内停止运行，连带 SonarQube 容器下线，是本次 CI 失败的直接原因；不是业务代码或某一 runner 故障。**
  - 恢复需启动 Docker Desktop，并验证 `sonar-postgres` / `sonarqube` healthy 与 `/api/system/status` 返回 `UP` 后再重跑 CI；本次未执行，等待用户确认。

## 2026-08-12 09:43 CST - 只读排查 iCare-mobile-app CI Quality Job 93874987093 失败

- 服务器：`mac-mini`（self-hosted runner `mac-mini-sonar-2`）
- 操作人：Codex（只读）
- 原因：排查 GitHub Actions [CI Quality Job 93874987093](https://github.com/cypressoai/iCare-mobile-app/actions/runs/31520169797/job/93874987093) 是 runner 环境还是代码侧导致失败。
- 影响：仅读取 GitHub Actions 日志和 runner 配置/进程/工作目录；未修改 runner、LaunchAgent、工作目录或仓库代码，未重启服务。
- 做了什么：
  1. 读取 Job 日志，失败点为 `pnpm install --frozen-lockfile`：`ERR_PNPM_ENOENT ... mkdir '.../node_modules'`。
  2. 查询 PR #128 的文件变更与 Git tree，确认其新增的根目录 `node_modules` 是 mode `120000` 的符号链接，内容为开发者本机绝对路径 `/Users/hon/code/Ai/iCare/mobile-app/node_modules`。
  3. 核对 `mac-mini-sonar-2` 的 `workFolder=/Users/konghai/gha/s2`、四个 `Runner.Listener` 进程与 LaunchAgent，均正常运行。
- 结论：**代码/PR 侧问题，非 runner 故障。** runner 上不存在该开发者本机路径，`pnpm` 无法在已被该失效符号链接占用的 `node_modules` 路径下创建依赖目录。应从 PR 删除该符号链接（并确认 `.gitignore` 继续忽略 `node_modules`）后重跑 CI。
- 备份：无（只读）。
- 回滚：无变更。
- 验证结果：checkout、Node 20.20.2 与 pnpm 初始化均成功；失败发生在依赖写入前，后续 lint / type check / jest 均未执行。

## 2026-08-07 13:37 CST - mac-mini Mini Shai-Hulud IoC **full 重扫**（补齐先前 FAIL）

- 服务器/设备：`mac-mini`
- 操作人：`Grok`
- 原因：同日首轮并行 full 扫描中 `mac-mini` 记录为 `DONE mac-mini FAIL rc=255`（05:14:55Z，无界 `find` 过大树导致 SSH 中断）；验收要求补齐与 lemon-imac 同结构的 full 只读日志，不得仅用浅扫冒充完成。
- 影响：只读；未改配置、未重启、未删文件、未轮换凭证。
- 先前失败：`remote-scan-progress.txt` → `START mac-mini mode=full 05:08:15` / `DONE mac-mini FAIL rc=255 05:14:55`；中间仅有浅扫摘要，已作废为正式结论。
- 重扫方法（05:32:31Z–05:37:14Z UTC）：`mdfind` 全机文件名 + `find` 高价值根（`~/gha` `~/actions-runner` `~/Code` Desktop Documents `/opt`）+ `rg` 扫 preinstall/lock/hooks；`ServerAliveInterval=15`；SSH exit 0。
- 结果：
  - `IOC_FILENAME_HIT_COUNT=10`：均为 `motion-dom/.../setup.mjs`（hash `c2f397ef…`）或 `regenerate-unicode-properties/.../Math_Symbol.js`（hash `b66c1e0b…`），**非** Aikido 恶意哈希。
  - `MALICIOUS_HASH_COUNT=0`，`PREINSTALL_HIT_COUNT=0`，`LOCKFILE_HIT_COUNT=0`，`HOOK_HIT_COUNT=0`。
  - gha/actions-runner 下存在正常 `keyv`/`flat-cache`/`file-entry-cache` 目录，**目录内无** `setup.mjs`/`Math_Symbol.js`/`math_init.js`。
  - 结论：`VERDICT=CLEAN_FALSE_POSITIVE_NAME_COLLISION`（与 lemon-imac / umacbook-pro 同类误报）。
- 备份：无（只读）。
- 回滚：无变更。
- 证据：`scan-mac-mini.log`（含 `PRIOR_FULL_FAIL` / `RESCAN_OK=1`）。

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`mac-mini`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN。浅扫 30 个 keyv/flat-cache 等 risk 包目录，无恶意文件/preinstall/hook/lock 命中。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-08-05 23:24 CST - 补回 mac-mini-sonar-1..4 的 `self-hosted` label

- 服务器：`mac-mini`（org runner `mac-mini-sonar-1..4`，id 22–25）
- 操作人：`Grok`
- 原因：backend CI workflow 使用 `runs-on: [self-hosted, backend-ci]`；`mac-mini-sonar-*` 虽有 `backend-ci` 但缺默认 label `self-hosted`，GitHub 调度硬匹配两边都要满足，导致 4 台闲置也永远进不了 backend 池。任务只能在 `mas-go-dev-ci` + `lemon-imac` + `umacbook-pro` 之间轮转，经常看起来都堆在 `mas-go-dev-ci-1`。
- 影响：`mac-mini-sonar-1..4` 重新进入 `[self-hosted, backend-ci]` 调度池；不动任何 workflow；前端 `mac-mini-sonar` / `frontend-*-ci` 匹配不受影响。
- 选型：方案 A（推荐）——只修 runner label，与 lemon / umac / mas-go-dev-ci 一致；不改业务仓 workflow。
- 备份：操作前 API 快照（4 台均无 `self-hosted`）：
  - id 22–25 labels：`mac-mini-sonar, macos, arm64, backend-ci, frontend-sonar-ci, frontend-tests-ci, frontend-quality-ci`
- 回滚方式：
  ```bash
  for id in 22 23 24 25; do
    gh api --method DELETE "orgs/cypressoai/actions/runners/${id}/labels/self-hosted"
  done
  ```
- 做了什么：
  ```bash
  for id in 22 23 24 25; do
    gh api --method POST "orgs/cypressoai/actions/runners/${id}/labels" -f 'labels[]=self-hosted'
  done
  ```
- 验证结果：
  - `mac-mini-sonar-1..4` labels 均含 `self-hosted` + `backend-ci`，status=`online`
  - 全 org `backend-ci` 池（10 slot：mac-mini×4 + lemon×2 + umac×2 + mas-go-dev-ci×2）`has_self_hosted=true`
- 补完后注意：
  1. **同机并发**：4 slot 若同时接 Go 全量 coverage + 前端 Vitest，会抢 CPU/磁盘；可接受，但别期望 4 路 backend 全开还很快。
  2. **能力**：本机已是重活机（gpg/dirmngr、CGO、per-slot GOCACHE 等见 `docs/runbooks/ci-runner-pools.md`）；建议观察接下来 1～2 个落到 mac-mini 的 Sonar job。
  3. **容量预期**：真正该多吃 backend 的是 mac-mini（10 核 / 32GB）；lemon/umac 的 8GB 适合轻中负载，修好 label 后分布应更健康。

## 2026-08-03 15:42 CST - CI 池加固：PNPM store + 日/周维护 + 四 slot 重启

- 服务器：`mac-mini`
- 操作人：`Grok`（iCare 自托管 runner 运维加固任务）
- 原因：质量门迁自托管后并发更高；需减 npm/pnpm 重复下载流量，并防止 `_work` / go-build 撑盘。
- 影响：
  - 四 slot `.env` 增加 `PNPM_STORE_PATH=~/gha/cache/pnpm-store`（保留 per-slot `GOCACHE` + 共享 `GOMODCACHE=~/gha/cache/go-mod`）
  - 部署脚本：`~/gha/scripts/{gha-runner-maintenance.sh,prune-gocache.sh}`
  - crontab：每日 03:15 清 work + 修剪 go-build；周日 04:30 weekly（pnpm prune / gomod 超 10G）
  - 即时维护：stale workFolder 清理（s1–s4 各约 4.0G→2.4–2.8G）；四 slot `svc.sh` 重启以加载 `.env`
- 备份：`~/actions-runner/mac-mini-sonar-N/.env.bak.<timestamp>`
- 回滚方式：恢复各 slot `.env.bak.*` 后 `./svc.sh stop && ./svc.sh start`；`crontab -e` 删除 `gha-runner-maintenance` 两行
- 验证：
  - Data 盘约 **62% / Avail 712Gi**（1.8T）
  - 四 `Runner.Listener` Started；GitHub `mac-mini-sonar-1..4` online
  - 日志：`~/Library/Logs/gha-runner-maintenance.log`
- 关联：`docs/runbooks/ci-runner-pools.md`；仓库 `scripts/gha-runner-maintenance.sh`

## 2026-07-29 09:27 CST - 恢复 mac-mini-sonar-1..4

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户要求启动本机 org runner。
- 影响：`mac-mini-sonar-1..4` 重新 online，可领取 `mac-mini-sonar` / `frontend-tests-ci` / `frontend-quality-ci` / `backend-ci` 等 job。
- 备份：无配置改动；沿用已有 LaunchAgent 与 `~/bin/mac-mini-runner-resume.sh`。
- 回滚 / 再次停止：
  ```bash
  for n in 1 2 3 4; do (cd ~/actions-runner/mac-mini-sonar-$n && ./svc.sh stop); done
  ```
- 做了什么：执行 `ssh mac-mini '~/bin/mac-mini-runner-resume.sh'`，四 slot 均为 Started；4 个 `Runner.Listener` 在跑。
- 验证结果：
  - 本机：`svc.sh status` → Started（PID 47565 / 47582 / 47599 / 47616）
  - GitHub API：`mac-mini-sonar-1..4` 均为 `online`；其中 `mac-mini-sonar-2` 已 busy
- 启停 runbook：`docs/runbooks/mac-mini-runner-start-stop.md`

## 2026-07-28 19:37 CST - 临时停止 mac-mini-sonar-1..4（用户占用主机）

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户需要本机桌面使用，要求暂停 org runner。
- 影响：`mac-mini-sonar-1..4` 离线，不再领取 `mac-mini-sonar` / `frontend-tests-ci` / `frontend-quality-ci` / `backend-ci` 等 job；匹配任务会落到 lemon-imac / umacbook-pro / mas-go-dev（按 label）。**未** disable LaunchAgent，仅 `svc.sh stop`。
- 备份：无配置改动；plist 与 runner 目录完整保留。
- 回滚 / 手动恢复：
  ```bash
  ssh mac-mini '~/bin/mac-mini-runner-resume.sh'
  # 或
  for n in 1 2 3 4; do (cd ~/actions-runner/mac-mini-sonar-$n && ./svc.sh start); done
  ```
- 做了什么：确认无 `Runner.Worker` 后，对 `mac-mini-sonar-1..4` 依次 `./svc.sh stop`（均为 Stopped）；`ps` 无 Listener/Worker。
- 验证结果：本机四 slot status Stopped。GitHub online→offline 可能延迟数分钟。
- 启停 runbook：`docs/runbooks/mac-mini-runner-start-stop.md`

## 2026-07-28 18:36 CST - 恢复 mac-mini-sonar-1..4；确认 `at` 定时未生效

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户 13:01 用 `at` 预约 16:01 自动恢复，到点未执行；手动恢复并落盘教训。
- 影响：四 slot 重新 online；安装固定脚本 `~/bin/mac-mini-runner-resume.sh`（日志 `~/Library/Logs/mac-mini-runner-resume.log`）；取消残留 `at` job。
- 根因：macOS 默认 **`com.apple.atrun` Disabled**，`at` 只入队不执行；另 `svc.sh` 必须 `cd` 到 runner 根再调用。
- 做了什么：
  1. 对 `mac-mini-sonar-1..4` 分别 `cd` + `./svc.sh start` → Started；4 个 `Runner.Listener` 在跑。
  2. GitHub API：`mac-mini-sonar-1..4` 均为 `online`。
  3. 写入 `~/bin/mac-mini-runner-resume.sh`；`atrm` 清理 job。
- 文档：
  - 取证：`docs/solutions/mac-mini/workflow-issues/macos-at-disabled-do-not-schedule-runner-resume-with-at-2026-07-28.md`
  - 启停 runbook：`docs/runbooks/mac-mini-runner-start-stop.md`
- **红线**：以后定时恢复 runner **不要用 `at`**，用 crontab / launchd。

## 2026-07-28 13:18 CST - 只读：确认 `com.apple.Virtualization.VirtualMachine` 归属

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户点名进程 `com.apple.Virtualization.VirtualMachine`，怀疑是某个 App 的虚拟机。
- 影响：无变更。
- 结论：该进程是 **Apple Virtualization.framework 的 XPC 服务**，当前唯一客户端是 **Docker Desktop**（不是 UTM / VMware / 独立 Win 虚机）。
- 证据：
  - PID **1495**（自 7/21 起常驻，约 8% 内存 / ~2.6GiB RSS）：路径 `.../Virtualization.framework/.../com.apple.Virtualization.VirtualMachine`
  - `lsof` 打开：`Docker.app/.../linuxkit/kernel`、`desktop.img`、`~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`（逻辑上限约 926G，实际占用约 **172G**）、Rosetta for Linux
  - 配对进程 PID **1463** `com.docker.virtualization`：`--cpus 8 --memoryMiB 24576`，父进程为 `com.docker.backend`
- 用途：给 Docker 容器提供 Linux 内核环境；关 Docker Desktop 后该 VirtualMachine 进程应随之退出。

## 2026-07-28 13:10 CST - 只读排查：本机「虚拟机程序」用途

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户忘记本机虚拟机相关程序在做什么，要求确认用途。
- 影响：无变更。
- 发现：
  1. **VMware Fusion** + 虚机 `~/虚拟机/Windows 11 x64.vmwarevm`：本意跑 Windows 11（挂载 `Nano 11 （Chinese）.iso`）以使用仅 Windows 软件；共享目录 `~/虚拟机/虚拟机共享` 含通达信、能旺 ERP、杏雨梨云、Maycad、钱包/回单等。**当前未运行**。磁盘仅 ~8.5MB（空稀疏盘，未装成系统）；最近一次开机（2026-01-31）失败，错误为 **x86 虚机与 Arm 主机不兼容**（Apple Silicon Mac mini）。ISO 已不在 `Downloads`。
  2. **Docker Desktop**（`com.docker.virtualization` LinuxKit 虚机）：常驻，8 vCPU / 24GiB；承载 SonarQube、AcquiLang Postgres、cypresso-okr、richer Grafana/Postgres 等 compose 服务。活动名单进程即 `com.apple.Virtualization.VirtualMachine`（见上条）。
- 验证：`vmrun list` → 0 running；`docker ps` 见 sonarqube / acquilang / okr / richer 等 Up。

## 2026-07-28 13:01 CST - 临时停止 mac-mini-sonar-1..4（用户占用主机，约 3 小时）

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：用户需要本机桌面使用，要求暂停 org runner 约 3 小时。
- 影响：`mac-mini-sonar-1..4` 离线，不再领取 `mac-mini-sonar` / `frontend-tests-ci` / `frontend-quality-ci` / `backend-ci` 等 job；匹配任务会落到 lemon-imac / umacbook-pro / mas-go-dev（按 label）。**未** disable LaunchAgent，仅 `svc.sh stop`。
- 备份：无配置改动；plist 与 runner 目录完整保留。
- 回滚 / 手动提前恢复：
  ```bash
  # 推荐（固定脚本，见 18:36 条目）
  ~/bin/mac-mini-runner-resume.sh
  # 或
  for n in 1 2 3 4; do cd ~/actions-runner/mac-mini-sonar-$n && ./svc.sh start; done
  ```
- 做了什么：
  1. 确认无 `Runner.Worker` 后，对 `mac-mini-sonar-1..4` 依次 `./svc.sh stop`（均为 Stopped）；`ps` 无 Listener/Worker。
  2. 写入 `/tmp/mac-mini-runner-resume.sh`，用 `at now + 3 hours` 预约 **2026-07-28 16:01 CST** 自动 `svc.sh start` 四 slot；日志 `/tmp/mac-mini-runner-resume.log`；`atq` job **1**。
- 验证结果：本机四 slot status Stopped；`atq` 显示 job 1 @ 16:01。GitHub online→offline 可能延迟数分钟。
- **事后**：16:01 **未执行**——macOS 默认禁用 `atrun`。见当日 18:36 恢复条目与 `docs/solutions/mac-mini/workflow-issues/macos-at-disabled-do-not-schedule-runner-resume-with-at-2026-07-28.md`。

## 2026-07-23 18:55 CST - 只读：go-build 近空，无清理（CYP-1547 全池核对）

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：A+B 实施前四机复测；mac-mini 四 slot `cache/go-build` 各 **8.0K**（仅 trim 元数据），盘 Avail **~552Gi**，**无同样膨胀**。
- 影响：无变更；策略文档统一为 2 天修剪 + coverage job-local GOCACHE。
- 验证：四 Listener Started；当时有 Worker（承接 CI），未动 cache。
- 关联：**CYP-1547**

## 2026-07-21 12:24 CST - 恢复 mac-mini-sonar-1..4

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：lemon/umac 已完成 Spotlight 隐私排除验证；用户要求恢复 mac-mini runner，结束临时分流。
- 影响：四 slot 重新 online，可再领取 `mac-mini-sonar` / `frontend-tests-ci` / `frontend-quality-ci` / `backend-ci` 等匹配 job。
- 备份：无配置改动。
- 回滚：`for n in 1 2 3 4; do cd ~/actions-runner/mac-mini-sonar-$n && ./svc.sh stop; done`
- 做了什么：对 `mac-mini-sonar-1..4` 依次 `./svc.sh start`；本机均为 Started，4 个 `Runner.Listener` 在跑。
- 验证结果：本机 status Started；GitHub API 见同条后续确认 online。

## 2026-07-21 10:55 CST - 临时停止 mac-mini-sonar-1..4（分流 CI 到 lemon/umac）

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：排查 lemon-imac / umacbook-pro 上是否同样有 Spotlight/`fseventsd` 问题；需让用户重跑的 Frontend Tests 落到那两台，避免继续被 mac-mini 抢走。
- 影响：本机 4 个 org runner 离线，不再领取 `frontend-tests-ci` / `frontend-quality-ci` / `backend-ci` / `mac-mini-sonar` 等 job；队列会落到 lemon-imac / umacbook-pro / mas-go-dev（按 label 匹配）。**未** `disable` LaunchAgent（仍为 enabled），仅 `svc.sh stop`。
- 备份：无配置改动；plist 与 runner 目录完整保留。
- 回滚方式：四 slot 分别 `cd ~/actions-runner/mac-mini-sonar-N && ./svc.sh start`（N=1..4），或登录会话内 `launchctl bootstrap gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-N.plist`。
- 做了什么：
  1. 确认无 `Runner.Worker` 后，对 `mac-mini-sonar-1..4` 依次执行 `./svc.sh stop`（均 Reported Stopped）。
  2. 本机 `ps` 无 Listener/Worker；`./svc.sh status` 均为 Stopped。
- 验证结果：本机服务已停。GitHub API 可能延迟数分钟才从 online→offline（stop 后立即查时部分 slot 仍显示 online）。
- 备注：lemon / umac 基线见同日 `docs/operations/lemon-imac.md` / `umacbook-pro.md`——两机 **Spotlight 仍为 Indexing enabled**，空闲/半忙时已有 `mds`/`mds_stores`/`mdworker` 占 CPU。

## 2026-07-21 10:44 CST - 只读：四 slot 全忙 Frontend Tests 时 fseventsd

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户要求再看一眼；本轮本机 4 个 `mac-mini-sonar-*` 全部 busy。
- 影响：无变更。
- 做了什么：进程快照 + 45s/2s 采样 load / fseventsd / mds / vitest forks；Worker 日志核对 Install 耗时。
- 当时状态（10:44–10:45 CST）：
  - **4 Worker** 同时跑 `Frontend Tests`：s1=3/4、s2=1/4、s3=2/4、s4=3/4（两 run 重叠可见双份 3/4）。
  - 均为 `vitest run --maxWorkers=2` → 合计 **4 vitest + 8 forks**；node 族 CPU 合计约 **770–890%**；load **9.5–11.2**（10 核满载）。
  - **fseventsd：45s 内几乎全程 0.0%**（偶见 0.2–0.6）；**mds 多数 0**，偶见 ~2%。
  - **npm ci**（本轮 4 路重叠安装，02:42:32–02:43:00 UTC）：s1 **17.6s**、s2 **16.2s**、s3 **16.7s**、s4 **9.2s**（并发写盘略慢于单路 7–12s，仍属热 cache）。
- 验证结果：即使 **4 shard 同机 Vitest 满载**，在已禁用 Spotlight 的前提下 **fseventsd 不再是 CPU 瓶颈**；瓶颈是 **node/vitest 本身**。昨天截图里 fseventsd ~98% 更可能是未关索引前或别的写盘洪峰场景，与当前配置下的稳态不同。
- 回滚方式：无。

## 2026-07-21 10:39 CST - 只读：用户重跑 job 后二次采样 fseventsd

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户重启若干 CI job，要求再核对 fseventsd / npm ci / vitest。
- 影响：无变更。
- 做了什么：90s 间隔 3s 采样 load / Worker / node 合计 CPU / fseventsd / mds；读四 slot 最新 Worker 日志的 Install 耗时；对照 GitHub runner busy 与 `iCare-frontend-mas` 进行中的 Sonar run。
- 当时状态（10:39–10:41 CST）：
  - 本机仅 **`mac-mini-sonar-3` busy**，跑 `Frontend Tests 1/4`（PR CYP-1428 / run 侧 in_progress；同 run 其它 shard 落在共享池其它机器）。
  - 命令：`vitest run ... --maxWorkers=2 --shard=1/4`（run-once）。
  - **npm ci**：slot3 本轮 **7.06s** exit 0；slot1 重跑 **10.79s** 后 job **Canceled**；slot2 上一次为 Sonar 路径 Checkout 失败后 Install 异常（exit 127），**Failed**。
  - **90s 内 fseventsd 全程 ~0.0%**；mds 偶发尖峰 23% / 8.7% / 4.5%，多数采样 0。
  - load ~3.0–3.4；Vitest 两 worker 合计约 200–250% CPU 属正常。
- 验证结果：重跑后仍看不到「fseventsd 吃满」；热 `npm ci` 更短（7–11s）。本机此轮并发只有 1 个 frontend test job，**未形成多 slot 同时解压** 的最坏写盘窗口。
- 回滚方式：无。

## 2026-07-21 10:30 CST - 只读：CI 运行中核对 fseventsd/mds 与 npm ci / vitest

- 服务器：`mac-mini`
- 操作人：`Grok`（只读排查）
- 原因：用户已排除 Spotlight 整盘索引后 mds 基本消失，但仍关心 fseventsd；需在 runner 实际跑 job 时核对 prefer-offline 与 `vitest run` 是否生效。
- 影响：无变更（只读）。
- 做了什么：
  1. SSH 采样进程 / load / 内存 / 磁盘 / `~/.npm` / 四 slot workFolder。
  2. 从 `mac-mini-sonar-2/3` 当前 Worker 日志读 `Install Dependencies` 耗时。
  3. `mdutil -s` 确认索引状态；`mdfind` 在 `~/gha` 下无 node_modules 索引命中。
- 当时状态（约 10:30 CST）：
  - 主机 uptime ~1h37m（当日早些时候重启过）；load ~5.5–5.8（10 核）。
  - 4 个 Listener 在线；**仅 slot2 + slot3 有 Worker**（Frontend Tests `shard=1/4` 与 `3/4`）。
  - 实测命令：`vitest run ... --maxWorkers=2 --shard=N/4`（run-once，非 watch）。
  - **npm ci**：两 slot 均 `npm ci --prefer-offline --no-audit --fund=false`，elapsed **~12.0–12.3s**，exit 0 → 本机 `~/.npm` 热缓存生效。
  - **fseventsd / mds**：Vitest 阶段连续采样 **~0% CPU**（对比用户昨日截图 fseventsd ~98% 的峰值场景；本次未撞上双 slot 同时 `npm ci` 的写盘洪峰窗口，install 已在 10:25 结束）。
  - Spotlight：`mdutil` 显示 `/` 与 Data 卷 **Indexing and searching disabled**。
  - `~/.npm` **9.5G**（`_cacache` 8.2G）；各 slot `node_modules` ~777–783M；workdir `~/gha/s1..s4` 各约 2.3G。
  - Data 卷 1.8T 已用 1.3T / 可用 468G（75%）。
- 验证结果：与 frontend-mas 配置一致——prefer-offline 热路径约 12s；CI 为 `vitest run`；mds 已压住；**当前 Vitest 中 fseventsd 不占 CPU**。若仍见 fseventsd 飙高，更可能集中在 **多 slot 并发 `npm ci` 解压** 或 4 shard 同时写盘，而非 Vitest watch。
- 回滚方式：无（只读）。

## 2026-07-20 19:48 CST - CI 缓存基线：共享 GOMODCACHE + 修剪 per-slot go-build

- 服务器：`mac-mini`
- 操作人：`Grok`（ce-work U4）
- 原因：四 slot 各有一份 ~1.5G `GOMODCACHE` 重复；go-build 单 slot 已 21–28GB。
- 影响：
  - 种子 `~/gha/cache/go-mod`（自 slot1 rsync），四 slot `.env` 的 `GOMODCACHE` 统一指向该路径；`GOCACHE` 仍 per-slot。
  - 对四 slot 执行 `go clean -cache`（阈值 >20GB），go-build 清空后靠 job 回填。
  - 重启 `mac-mini-sonar-1..4`。
  - 清理 login 用户闲置 `~/Library/Caches/go-build`（~3.4G）。
- 备份：`~/actions-runner/mac-mini-sonar-*/.env.bak.*`
- 回滚：还原 `.env.bak`（旧 per-slot go-mod 目录可能仍在但权限杂乱，优先用共享路径）。
- 验证：四 slot `GOMODCACHE` 相同、`GOCACHE` 各异；LaunchAgent Started。
- 参考：`docs/plans/2026-07-20-001-ops-ci-runner-cache-baseline-plan.md`

## 2026-07-20 13:45 CST - CI 池：加入 frontend-quality-ci（重活仍钉 mac-mini-sonar）

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：统一 PR 质量池与测试分片池；Coverage / 完整 Sonar 仍仅 32GB 本机。
- 影响：`mac-mini-sonar-1..4`（id 22–25）追加 `frontend-quality-ci`；保留 `frontend-tests-ci` / `backend-ci` / `mac-mini-sonar`。
- 回滚：`gh api -X DELETE orgs/cypressoai/actions/runners/{22..25}/labels/frontend-quality-ci`
- 参考：`docs/runbooks/ci-runner-pools.md`



## 2026-07-09 00:10 CST - 收敛 frontend-mas CI 队列吞吐到 mac-only 四 runner

- 原因：继续优化 `iCare-frontend-mas` `SonarQube Analysis` 的整体队列吞吐，指标改为同一配置下并发触发两条 PR run 后折算的 `SonarQube Analysis/hour`，重点优化 `Frontend Tests` 阶段而不是单条 run 的最短耗时。
- 影响：
  - `mac-mini` 最终保留 `mac-mini-sonar-1..4` 四个 GitHub Actions runner 在线。
  - `frontend-mas` 最终候选配置：`Frontend Tests` 4 shards，全部跑 `[mac-mini-sonar, frontend-tests-ci, macos, arm64]`，每 shard `VITEST_MAX_WORKERS=2`，即 mac-mini 总 Vitest workers=8。
  - `lemon-imac` / `lemon-imac-2` 不参与最终 `Frontend Tests` shard；保留其 runner 在线但不在最终 workflow 中引用。
  - 前端分支 `optimize/CYP-1246-frontend-ci-queue` / `optimize/CYP-1246-frontend-ci-queue-b` 均推送到最终 commit `122e7088`，用于 PR 双跑验证。
- 回滚方式：
  - 如需回到双 runner 四 worker方案：`launchctl disable gui/501/actions.runner.cypressoai.mac-mini-sonar-{3,4}` 后 `launchctl bootout gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-{3,4}.plist`，并把 workflow 的 `VITEST_MAX_WORKERS` 改回 `4`。
  - 如需恢复 lemon 混合实验：把 workflow 拆成 mac shards `1..4/6`（`VITEST_MAX_WORKERS=2`）和 lemon shards `5..6/6`（`VITEST_MAX_WORKERS=1`）。
- 做了什么：
  - 复测 mac-only 4 runner × 2 workers × 4 shards：run `28948596797` / `28948599595` 双绿，吞吐 `7.045/h`。
  - 测试 mac-only 4 runner × 2 workers × 8 shards：首次 run `28949983957` / `28949988495` 一绿一红；修复 `BenefitPlanCreateInnerIllnessLimitsDrawer.test.tsx` 高负载等待边界后，run `28951878491` / `28951882286` 双绿但吞吐仅 `6.44/h`，低于 4 shards。
  - 复测 mac-only 4 shards 最新状态：run `28953384903` / `28953388341` 双绿，吞吐 `6.723/h`。
  - 测试 mac + lemon 混合 6 shards：run `28954798224` / `28954802865` 双绿，吞吐 `6.642/h`；`lemon-imac` 的 `5/6` shard 两次约 12 分钟，形成长尾。
  - 最终回到 mac-only 4 shards 并验证：run `28956235734` / `28956241233` 双绿，批次窗口 1005 秒，吞吐 `7.164 SonarQube Analysis/hour`。
- 验证结果：
  - `mac-mini` `launchctl list` 显示 `actions.runner.cypressoai.mac-mini-sonar-1..4` 均在线；`launchctl print-disabled gui/501` 显示四个 service 均 enabled。
  - GitHub runner API 显示 `mac-mini-sonar-1..4`、`lemon-imac`、`lemon-imac-2` 均 online 且空闲。
  - 最终 workflow 校验 `npm run check:ci-workflows` 通过。
  - 最终结论：当前最高实测方案是 `mac-mini 4 runner × 每 shard 2 workers × 4 shards`。8 shards 单条 run 可更快，但 GitHub 调度会优先消化同一 run 的剩余 shards，B run 等待变长；lemon 混合池能让 B 更早起跑，但 8GB lemon shard 长尾抵消收益。

## 2026-07-08 21:58 CST - 验证 frontend-mas CI 双 runner 四 worker 吞吐

- 原因：用户希望以“60 分钟内完成多少个 `SonarQube Analysis`”作为 CI 配置优劣指标，并要求同一方案至少同时触发两条 `SonarQube Analysis`，验证真实队列吞吐；目标配置为 `mac-mini` 2 个 runner，每个 frontend test shard 使用 `maxWorkers=4`，总计 8 个 Vitest worker。
- 影响：
  - `mac-mini` 保持仅 `mac-mini-sonar-1`、`mac-mini-sonar-2` 在线，`mac-mini-sonar-3`、`mac-mini-sonar-4` 继续禁用。
  - `frontend-mas` 分支 `optimize/CYP-1246-frontend-ci-queue` 和 `optimize/CYP-1246-frontend-ci-queue-b` 均推送到 commit `48c4d457`，用于并发触发 PR CI。
  - workflow 目标状态为 4 个 frontend test shard 跑在 `[mac-mini-sonar, frontend-tests-ci, macos, arm64]`，`VITEST_MAX_WORKERS=4`。
- 回滚方式：
  - runner 侧如需恢复 4 runner 并发，执行 `launchctl enable gui/501/actions.runner.cypressoai.mac-mini-sonar-{3,4}`，再 `launchctl bootstrap gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-{3,4}.plist` 或 `launchctl kickstart -k`。
  - 仓库侧可把 `frontend-mas/.github/workflows/sonar.yml` 回滚到前一版 shard/worker 配置，或恢复到仅按 `[frontend-tests-ci, macos, arm64]` 调度。
- 做了什么：
  - 修复两处高负载下暴露的测试 flaky：LOA diagnosis drawer 延迟 open callback 清空草稿，以及 Inner/Illness Limits drawer 提交前 AntD Form/useWatch 状态尚未同步。
  - 本地验证 `BenefitPlanCreateInnerIllnessLimitsDrawer.test.tsx` 单文件 7 个测试通过；`VITEST_MAX_WORKERS=4 npm run test:ci -- --shard=2/4` 通过，247 个文件、1579 个测试通过。
  - 顺序推送两个 PR 分支，触发并发 run `28947113047` 和 `28947119750`。
- 验证结果：
  - `mac-mini` 本机 `launchctl list` 仅显示 `actions.runner.cypressoai.mac-mini-sonar-1`、`actions.runner.cypressoai.mac-mini-sonar-2`；`launchctl print-disabled gui/501` 显示 runner3/4 为 disabled。
  - run `28947113047` 成功：A run 创建于 `2026-07-08T13:39:47Z`，完成于 `13:49:57Z`。
  - run `28947119750` 成功：B run 创建于 `2026-07-08T13:39:54Z`，完成于 `13:57:21Z`。
  - 双 run 批次窗口 1055 秒，折算吞吐为 `6.825 SonarQube Analysis/hour`；8 个 frontend shard 全部成功，`frontend_test_step_sum_seconds=1436`，最大 frontend job 排队 864 秒。
  - 队列行为符合预期：A run 先占用两个 mac-mini frontend runner，A 释放 slot 后 B 的 shard 无缝接上；B 初期 queued 不是 runner 卡死，而是双 runner 容量限制下的正常排队。

## 2026-07-08 18:09 CST - 收敛 frontend-mas CI 到 mac-mini 双 runner

- 原因：排查 `iCare-frontend-mas` PR #1036 的 `Frontend Tests` flaky。失败 run 中 `frontend-tests-ci` 同时调度到 `lemon-imac`、`lemon-imac-2`、`mac-mini-sonar-1..2`，而 `lemon-imac` 只有 8GB 内存；在 `maxWorkers=4` 下 jsdom/AntD 测试明显变慢并触发默认 `waitFor/findBy` 1s 等待边界，出现断言/元素查找 flaky。
- 影响：
  - `mac-mini` 仅保留 `mac-mini-sonar-1`、`mac-mini-sonar-2` 两个 GitHub Actions runner 在线。
  - `mac-mini-sonar-3`、`mac-mini-sonar-4` 的 LaunchAgent 已 `disable` 并 `bootout`，不删除 runner 目录、不移除 GitHub runner 注册、不改 token。
  - `frontend-mas` 分支 `feature/CYP-1241-test-ci-maxworkers-6` 保留 PR frontend test 4 片，但让 shard 只匹配 `[mac-mini-sonar, frontend-tests-ci, macos, arm64]`，在两个在线 mac-mini runner 上分批执行，避免继续落到 `lemon-imac`；汇总 `Frontend Tests` job 改到 `mas-go-dev`，避免空 echo job 排队占 Mac runner。
- 备份：
  - 操作前 `launchctl print gui/501/actions.runner.cypressoai.mac-mini-sonar-{1,2,3,4}` 已读出当前 plist 路径、工作目录、stdout/stderr 路径和运行状态。
  - 操作前 GitHub API 显示 `mac-mini-sonar-1..4` 均为 `online` 且 `busy=false`，标签均包含 `mac-mini-sonar,macos,arm64,backend-ci,frontend-sonar-ci,frontend-tests-ci`。
- 回滚方式：
  - 重新启用 runner3/4：`launchctl enable gui/501/actions.runner.cypressoai.mac-mini-sonar-3`、`launchctl enable gui/501/actions.runner.cypressoai.mac-mini-sonar-4`。
  - 再拉起服务：`launchctl bootstrap gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-3.plist`、`launchctl bootstrap gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-4.plist`；如已加载但未运行，可用 `launchctl kickstart -k gui/501/actions.runner.cypressoai.mac-mini-sonar-3` 和 `-4`。
  - 仓库侧回滚：把 `frontend-mas/.github/workflows/sonar.yml` 的 frontend test runner 标签恢复为原 `[frontend-tests-ci, macos, arm64]`；如需恢复 4 个 mac-mini runner 同机并发，再启用 runner3/4。
- 做了什么：
  - 通过 GitHub run 日志确认失败 run `28932383075` 中 2/4 在 `mac-mini-sonar-2` 失败、4/4 在 `lemon-imac` 失败，失败点分别是 `BenefitPlanCreateInnerIllnessLimitsDrawer.test.tsx:246` 的 `saveMutate` 等待未满足、`SpecializationTemplatePage.test.tsx:220` 找不到 `Change` 按钮。
  - 本地在 `frontend-mas` 运行两个失败测试文件，`maxWorkers=4` 下 15 个测试全部通过；再运行 `npm run test:ci -- --shard=1/2`，489 个文件、3025 个测试通过。
  - 执行 `launchctl disable gui/501/actions.runner.cypressoai.mac-mini-sonar-{3,4}` 和对应 `launchctl bootout`，停用 runner3/4。
- 验证结果：
  - `mac-mini` 本机 `launchctl list` 仅剩 `actions.runner.cypressoai.mac-mini-sonar-1`、`actions.runner.cypressoai.mac-mini-sonar-2`。
  - `ps` 仅显示 runner1/2 的 `runsvc.sh` 与 `Runner.Listener`，无 runner3/4 进程。
  - `launchctl print-disabled gui/501` 显示 runner1/2 为 `enabled`，runner3/4 为 `disabled`。
  - GitHub API 显示 `mac-mini-sonar-1`、`mac-mini-sonar-2` 为 `online`，`mac-mini-sonar-3`、`mac-mini-sonar-4` 为 `offline`。
  - 最终验证 run `28935448141` 通过：`Frontend Tests 1/4..4/4`、`Typecheck`、`SonarQube Scan`、汇总 `Frontend Tests` 均为 `success`；实际测试 shard 使用 `--maxWorkers=4 --shard=N/4`，两个在线 mac-mini runner 分批执行。

## 2026-07-08 02:23 CST - 只读盘点 frontend-mas runner 本地缓存现状

- 原因：用户询问 frontend test runner 的缓存方案是在 workflow 侧还是 runner 侧配置，以及 `lemon-imac` 与 `mac-mini` 当前缓存现状。
- 影响：仅读取 workflow 配置和本机 runner 目录大小；未修改 runner、workflow、缓存目录或服务。
- 观察结果：
  - `frontend-mas/.github/workflows/sonar.yml` 未使用 `actions/cache`，`actions/setup-node` 未配置 `cache: npm`；依赖安装通过 `npm ci --prefer-offline --no-audit --fund=false` 使用本机 npm cache。
  - `mac-mini` 四个 runner slot 分别使用 `/Users/konghai/gha/s1..s4`，工作目录互相隔离。
  - 用户级 npm cache `/Users/konghai/.npm` 约 `9.5G`，由同一 macOS 用户下的四个 runner slot 共享。
  - 四个 slot 各自有独立 Node tool cache：`_tool/node/24.16.0/arm64`，每个 runner root 的 `_tool` 约 `730M`。
  - 四个 slot 的 `iCare-frontend-mas` workspace 各自保留 `.git` 约 `130-134M`；`s2..s4` 当前保留 `node_modules` 约 `755-765M`，`s1` 当前未见可统计的 `node_modules`。
- 结论：当前缓存主要是 self-hosted runner 的本机持久缓存，不是 GitHub 远端 cache；同机共享的是用户级 npm tarball cache，workspace / Node tool cache 仍按 runner slot 独立。

## 2026-07-08 01:22 CST - 为 mac-mini sonar runner 加入 frontend-tests-ci 共享测试池

- 原因：`frontend-mas` PR 的 `Frontend Tests` 是合并排队主要瓶颈。单纯把一个 PR 的测试拆到 `mac-mini` + `lemon-imac` 混合 6 片收益不稳定；新策略改为提升整体吞吐量：保留 4 片测试，但让 `mac-mini` 4 个 slot 与 `lemon-imac` 2 个 slot 共同接同一类 frontend test shard。
- 影响：
  - GitHub 组织 `cypressoai` 中 `mac-mini-sonar-1..4` 新增自定义标签 `frontend-tests-ci`。
  - `frontend-mas` PR 分支的 `sonar.yml` 已把 `Frontend Tests` shard job 和汇总 job 的 `runs-on` 改为 `[frontend-tests-ci, macos, arm64]`。
  - 未 SSH 登录 `mac-mini`，未修改本机 runner 文件，未重启 runner。
- 回滚方式：
  - 从 `mac-mini-sonar-1..4` 的 GitHub runner labels 中移除 `frontend-tests-ci`。
  - `frontend-mas/.github/workflows/sonar.yml` 恢复为 `[mac-mini-sonar, macos, arm64]`。
- 验证结果：
  - GitHub API 显示 `mac-mini-sonar-1..4` 均包含 `frontend-tests-ci`、`macos`、`arm64`。
  - `frontend-mas` workflow 校验通过：`npm run check:ci-workflows`、`actionlint -ignore 'label ".*" is unknown' .github/workflows/sonar.yml`、YAML parse。

## 2026-06-10 17:49 CST

- 原因：单 runner 串行化后 CI 队列大量积压，用户要求恢复 4 个 runner 并发以消化排队任务。
- 影响：`mac-mini-sonar-1..4` 全部重新在线，恢复同机最多 4 个 job 并发；重 CPU job 并发时会重新出现互相抢核的情况（见 17:05 审计）。`icare-sql-edge` 保持停止，本次未改动。
- 回滚方式：如需回到单 runner 串行化，分别在 `~/actions-runner/mac-mini-sonar-{2,3,4}` 执行 `./svc.sh stop`（停止前确认对应 slot 无 active `Runner.Worker`）。
- 做了什么：按 17:20 记录的回滚方式，在 `~/actions-runner/mac-mini-sonar-{2,3,4}` 依次执行 `./svc.sh start`，重新启动三个 launch agent；`mac-mini-sonar-1` 一直在线未动。
- 验证结果：`launchctl list` 显示 `actions.runner.cypressoai.mac-mini-sonar-1..4` 均为 Started（退出码 0）；`ps` 显示 4 个 `Runner.Listener` 全部运行，其中 runner1 已有 active `Runner.Worker` 在跑 job，2..4 listener 就绪等待领取排队任务。

## 2026-06-10 17:20 CST

- 原因：优化 `iCare-frontend-mas` PR CI 的 `Frontend Tests` 单 job 耗时。前一轮审计确认 4 个 `mac-mini-sonar-*` runner 可同机并发，重 CPU Vitest job 会互相抢核；用户决定牺牲少见的多 job 并发，优先让单 job 独占主机资源。同时用户确认 `icare-sql-edge` 已不重要，可以停止以释放内存。
- 影响：`mac-mini` 当前只保留 `mac-mini-sonar-1` 一个 GitHub Actions runner 在线；同一时间只会有一个匹配 `mac-mini-sonar` / `macos` / `arm64` 的 job 在该主机运行，其它 job 会排队。`icare-sql-edge` 容器已停止，且不会随 Docker Desktop / 主机重启自动拉起。未删除 runner 注册、runner 工作目录、tool cache、npm cache、容器或卷。
- 回滚方式：如需恢复 4 runner 并发，分别执行 `cd ~/actions-runner/mac-mini-sonar-2 && ./svc.sh start`、`cd ~/actions-runner/mac-mini-sonar-3 && ./svc.sh start`、`cd ~/actions-runner/mac-mini-sonar-4 && ./svc.sh start`。如需恢复 SQL Edge，执行 `docker update --restart=always icare-sql-edge && docker start icare-sql-edge`。
- 做了什么：预检时 `mac-mini-sonar-1` 正在跑一个既有 `iCare-frontend-mas` Vitest job，`mac-mini-sonar-2..4` 没有 active `Runner.Worker`；因此只停止 `2..4`，未打断正在 runner1 上执行的 job。
- 做了什么：在各 runner 目录执行 `./svc.sh stop`，停止 `mac-mini-sonar-2`、`mac-mini-sonar-3`、`mac-mini-sonar-4` 三个 launch agent。
- 做了什么：记录 `icare-sql-edge` 原状态为 `restart=always status=running`，执行 `docker update --restart=no icare-sql-edge` 后停止容器。
- 验证结果：`launchctl list` 仅显示 `actions.runner.cypressoai.mac-mini-sonar-1`；`ps` 仅显示 runner1 的 `Runner.Listener`，无 active `Runner.Worker` / `vitest` / `forks.js`；`docker inspect` 显示 `/icare-sql-edge restart=no status=exited`。停止后 `docker stats` 不再列出 `icare-sql-edge`，`sonarqube` 约占 `3.8GiB`；load average 从操作前约 `13.85 12.32 16.11` 逐步回落到约 `4.34 8.05 12.78`，swap 使用从约 `5290MiB` 小幅降到约 `5258MiB`。
- 后续建议：runner 侧已完成“单 runner 串行化”。前端仓的 `--maxWorkers` 是 `package.json` 中的脚本参数，不属于 runner 配置；建议前端项目侧先把 `test:ci` 从 `--maxWorkers=2` 提到 `8` 做 PR 验证，`10` 作为后续对照压测候选。若队列等待时间变得不可接受，再恢复 `2..4` 或改为专用 label 分流。

## 2026-06-10 17:05 CST

- 原因：评估 `iCare-frontend-mas` PR CI 中 `Frontend Tests` 耗时较长的问题，确认 self-hosted GitHub Actions runner 的并发模型和主机负载，以决定是否能安全提高 Vitest `--maxWorkers`。
- 影响：仅做只读 SSH 查询，未修改 runner、workflow、容器或系统配置；不影响正在运行的 CI。
- 回滚方式：无配置变更，无需回滚。如后续按建议调整 runner label / service，需要在执行前另行备份并确认。
- 做了什么：确认 `mac-mini` 当前只有 4 个 GitHub Actions runner service，分别为 `mac-mini-sonar-1..4`，均通过 `launchctl` 运行；对应 `workFolder` 分别为 `/Users/konghai/gha/s1..s4`。
- 做了什么：确认当前 4 个 runner slot 可并发执行 job。审计时 4 个 slot 同时在跑 `iCare-frontend-mas` 的 Vitest：每个 job 脚本为 `vitest run --reporter=dot --maxWorkers=2 --testTimeout=30000`，总计约 8 个 Vitest worker fork 同机并发。
- 做了什么：采样主机资源：`hw.ncpu=10`，其中性能核 4 个、能效核 6 个；审计时 load average 约 `32.49 25.26 18.97`，CPU `0.0% idle`，内存 `31G used`，swap 已使用约 `5.3G`。Docker Desktop VM 常驻运行，容器包括 `sonarqube`、`sonar-postgres`、`icare-sql-edge` 等，其中 `icare-sql-edge` 约占 `8.8GiB`，`sonarqube` 约占 `3.6GiB`。
- 验证结果：瓶颈不是 runner 空闲核心未被单 job 使用，而是 4 个独立 runner 允许同一台主机并发跑多个重 CPU 的 frontend test job。若不调整 runner / workflow 调度，安全的 `vitest --maxWorkers` 上限仍应保持 `2`；直接改为 `4` 会把最坏情况推到 `4 job × 4 workers = 16` 个 CPU 密集 worker，超过该机器实际可承受并发，容易让整体更慢或触发 Vitest watchdog。
- 后续建议：若目标是缩短单个 PR 的 `Frontend Tests` 延迟，应先做资源隔离，例如给 1 个 runner slot 增加专用 label（如 `mac-mini-frontend-test`）并让 frontend test job 只调度到该 label，再把 `--maxWorkers` 提到 `4`；其余 `mac-mini-sonar-*` slot 继续服务 SonarQube Scan / 轻量 job。若继续让 4 个 slot 都承接 frontend test job，则不建议提高 `--maxWorkers`。

## 2026-06-09 14:03 CST

- 原因：`backend` / `frontend-mas` pin 到含 SQSCANGHA-135 修复的 `SonarSource/sonarqube-scan-action` commit 后，Scanner CLI 8.1.0.6389 默认启用 GPG 签名校验。mac-mini 已安装 `/opt/homebrew/bin/gpg`，但 4 个 GitHub Actions runner service 的 `.path` 不包含 `/opt/homebrew/bin`，导致 CI 报 `GPG is not available`。修复 PATH 后又暴露出第二层问题：默认 `workFolder: _work` 生成的 `RUNNER_TEMP` 路径过深，Sonar action 的临时 `GNUPGHOME` 下 `S.gpg-agent` / `S.dirmngr` socket 接近 macOS 路径限制，导致 `File name too long` / `gpg-agent: IPC connect call failed`。
- 影响：两轮重启 `mac-mini-sonar-1..4` runner service。第一次修改 `.path` 时先重启空闲的 `1/2/4`，等待 `mac-mini-sonar-3` 的 `Runner.Worker` 退出后再重启 `3`；第二次确认无 `Runner.Worker` 后统一重启 4 个 runner。期间一个 frontend PR run 的 `Frontend Tests` 被 runner2 重启打断，已通过 GitHub `force-cancel` 结束，并重新触发 PR run。
- 回滚方式：把对应 runner 目录的 `.path.bak.20260609-140142` 复制回 `.path`，把 `.runner.bak.20260609-142350` 复制回 `.runner`，再执行该 runner 目录下的 `./svc.sh stop && ./svc.sh start`。
- 做了什么：备份并修改 4 个 runner 的 `.path`，在原 PATH 前追加 `/opt/homebrew/bin`。

```text
/opt/homebrew/bin:/Users/konghai/.cargo/bin:/Users/konghai/.volta/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

- 做了什么：备份并修改 4 个 runner 的 `.runner`，把 `workFolder` 改到短路径。

```text
mac-mini-sonar-1: /Users/konghai/gha/s1
mac-mini-sonar-2: /Users/konghai/gha/s2
mac-mini-sonar-3: /Users/konghai/gha/s3
mac-mini-sonar-4: /Users/konghai/gha/s4
```

- 验证结果：4 个 `Runner.Listener` 进程的实际 `PATH` 均包含 `/opt/homebrew/bin`；以各自进程 PATH 执行 `command -v gpg` 均返回 `/opt/homebrew/bin/gpg`，`gpg --version` 返回 `gpg (GnuPG) 2.5.18`；短路径下 `S.gpg-agent` 路径长度约 68；`launchctl list` 显示 `actions.runner.cypressoai.mac-mini-sonar-1..4` 均为 Started；`backend` PR SonarQube Scan 重跑成功；`frontend-mas` PR SonarQube PR Scan 重跑成功。后续抽样多个 PR run，4 个 slot 均已写入 `/Users/konghai/gha/s{1..4}/_tool/sonar-scanner-cli/8.1.0-build.6389/macosx-aarch64` 且有 `.complete` 标记；`mac-mini-sonar-1`、`2`、`4` 已在日志中出现 `Using cached Sonar Scanner CLI from:`，确认缓存命中；`mac-mini-sonar-3` 已完成冷下载和缓存写入，等待下一次同 slot Sonar job 观察二次命中。
