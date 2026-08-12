# dev-cypresso 运维时间线

## 2026-08-12 12:20 CST - 补齐 ECOM AUTH_DB 配置并恢复外部 API

- 服务器：`dev-cypresso`（SIT Server）
- 操作人：`Codex`
- 原因：新 ECOM 镜像要求独立的 `AUTH_DB_*` 连接读取 `authprovidermasweb.dbo.oauth_clients`，但既有 `.env.ecom` 未配置，导致容器启动前退出并循环重启。
- 影响：仅更新 `/home/ec2-user/stacks/icare/.env.ecom` 的 8 个 `AUTH_DB_*` 项，并强制重建原本已不可用的 `icare-backend-ecom-api-1`；未改 API、worker、SUP、业务数据、数据库表结构或 OAuth 客户端数据。
- 备份：`/home/ec2-user/stacks/icare/.env.ecom.bak.20260812-1205-authdb`。
- 回滚方式：恢复上述 `.env.ecom` 备份后，以当前 ECOM 镜像执行 `docker-compose -f backend.compose.yaml --profile external-api up -d --no-deps --force-recreate ecom-api`；确认两台 SIT 均不再使用对应独立身份后，由 SA 删除其 `authprovidermasweb` user 与 SQL login（见 `docs/operations/mssql-ref.md` 同时段记录）。
- 变更时序：
  1. 使用独立、最小权限的 ECOM SQL 身份（仅 `CONNECT` + `SELECT dbo.oauth_clients`）替代缺失配置；密码仅写入本机 `.env.ecom`，未输出或提交。
  2. `AUTH_DB_HOST` / `PORT` / `ENCRYPT` 沿用该环境现有数据库链路，`AUTH_DB_NAME=authprovidermasweb`。
  3. 显式复用当前 ECOM 镜像 `ghcr.io/cypressoai/icare-backend-ecom:9e99fc71…`，以 `--no-deps --force-recreate --pull never` 重建单个 ECOM 容器；未清理 compose 提示的 orphan `gotenberg`。
- 验证：HTTP `/api/v1/health` 在第 3 次探测通过且 `auth_database=up`；最终容器 `running`、Docker health `healthy`、`RestartCount=0`。

## 2026-08-12 11:52 CST - 只读确认 ECOM 部署失败为缺失 AUTH_DB 配置

- 服务器：`dev-cypresso`（SIT Server）
- 操作人：`Codex`
- 原因：GitHub Actions 的 ECOM readiness 连续失败；恢复 `iCare backend ECOM deployment failure diagnosis` 交接后，需在目标机取得容器启动错误并核对外部 OAuth 数据库配置契约。
- 影响：只读检查 Docker 容器状态、最近 200 行日志及 `.env.ecom` / `.env` / `.env.docker` 的 `AUTH_DB_*` 键是否存在或非空；未读取或输出密码、连接值，未改配置、未重启或重建容器。
- 备份：无（只读）。
- 回滚：无变更。
- 验证：
  - `icare-backend-ecom-api-1` 镜像为 `ghcr.io/cypressoai/icare-backend-ecom:0dffcd2…`，处于 `Restarting (1)`，检查时 `RestartCount=35`、`ExitCode=1`。
  - 启动日志反复报：`AUTH_DB_ENABLED must be true when APP_SERVICE_PROFILE=ecom`。
  - `.env.ecom`、`.env` 与 `.env.docker` 均未定义 `AUTH_DB_ENABLED`、`AUTH_DB_HOST`、`AUTH_DB_PORT`、`AUTH_DB_USER`、`AUTH_DB_PASSWORD`、`AUTH_DB_NAME`；因此故障确定为部署环境未供应 ECOM 的外部 OAuth 数据库配置，而非本次业务代码变更。

## 2026-08-10 12:56 CST - 修复 App 登录 503：icare-backend 侧遗漏的 7 处旧跳板 IP（12:02 条目的续集）

- 服务器：`dev-cypresso`
- 操作人：`Claude`
- 触发：App 登录页报 `The service is temporarily unavailable. Please try again shortly.`
- 原因：**与 12:02 条目同源（tizi-cyp 换 IP），但出错的服务不同**。12:02 只修了 public-backend 自己的 `.env.{app,hr,map}`，遗漏了 `icare-backend` 的一整组 env 文件，其中仍是旧 IP `100.88.178.78`：
  ```
  App 登录 → public-backend（本身正常，WEBKIT_DB 已在 12:02 修好）
              └→ http://api:8080/internal/public/v1/{members/<id>/auth-context, settings/auth-policy}
                   └→ icare-backend ← DB_HOST 仍是旧 IP
                        └→ dial tcp 100.88.178.78:1433 i/o timeout（15s）
                             └→ public-backend 客户端 10s 先超时 → 对 App 返回 503
  ```
  - `icare-backend` 容器已连续运行 39 小时、healthy，未被当日部署触及，是**带着旧配置一直活着**的，所以 12:02 修复时不会暴露。
  - 关键区分点：从 public-backend 容器手工 `curl http://api:8080/...` **秒回 401**（服务活着、网络通），但业务请求 15s 超时——差别在业务路径要查库。据此可快速排除"容器网络不通"这一错误方向。
- 影响：
  - 改动 `/home/ec2-user/stacks/icare/` 下 3 个 env 文件、共 7 处 `*DB_HOST`
  - 重建 `api` / `worker` / `ecom-api` / `sup-api` 四个容器
- 待修清单（旧 IP → `100.116.91.14`）：

  | 文件 | 处数 | 变量 |
  |---|---|---|
  | `.env`（`.env.docker` 是指向它的软链） | 3 | `DB_HOST`、`WEBKIT_DB_HOST`、`SALESPORTAL_DB_HOST` |
  | `.env.ecom` | 1 | `DB_HOST` |
  | `.env.sup` | 3 | `DB_HOST`、`SALESPORTAL_DB_HOST`、`REPLICATED_DB_HOST` |

- 备份：`/home/ec2-user/stacks/icare/.env{,.ecom,.sup}.bak.20260810-dbhost`
- 回滚方式：
  ```bash
  ssh dev-cypresso 'cd /home/ec2-user/stacks/icare && \
    for f in .env .env.ecom .env.sup; do cp "$f.bak.20260810-dbhost" "$f"; done'
  # 再按下方「变更时序」第 4 步重建容器
  ```
- 变更时序：
  1. 定位：`icare-backend-api-1` 日志刷 `unable to open tcp connection with host '100.88.178.78:1433'`，另有每 30s 一次的 `policy sync: reload failed`（casbin 权限策略同步）
  2. `grep -lE "100\.88\.178\.78" .env*` 找全受影响文件（**注意排除 `.bak.*` 备份，那些不该改**）
  3. 备份后 `sed -i -E "s/^([A-Z_]*DB_HOST)=100\.88\.178\.78[[:space:]]*$/\1=100.116.91.14/"`，锚定行首 + 行尾，避免误伤注释或其他含该 IP 的配置；`diff` 确认恰好只改了预期行数
  4. 重建容器（**必须显式传镜像变量**，见下方「坑」）：
     ```bash
     cd /home/ec2-user/stacks/icare
     export BACKEND_IMAGE=ghcr.io/cypressoai/icare-backend:<sha>
     export ECOM_IMAGE=ghcr.io/cypressoai/icare-backend-ecom:<sha>
     export SUP_IMAGE=ghcr.io/cypressoai/icare-backend-sup:<sha>
     docker-compose -f backend.compose.yaml up -d --no-deps api worker ecom-api sup-api
     ```
     `<sha>` 取自 `docker ps --format '{{.Names}}\t{{.Image}}'`（本次为 `7fa2c2fb07cde5f27af0883c8a96c8f0cc4c7125`，三个镜像仓同一 commit）
- 两个坑（本次实操踩到）：
  - **`.env.docker` 是指向 `.env` 的软链**。`cp -a .env.docker .env.docker.bak` 只会复制出一条软链，**内容根本没备份**，且 `ls -l | grep '^l'` 在该目录下不显示它。要备份必须对真身 `.env` 操作，或用 `readlink -f` 先解析。
  - **`docker-compose up -d` 会尝试从源码构建**：`backend.compose.yaml` 里各服务同时有 `build:` 和 `image:`，`image` 未提供时回退到 `:local` 标签，本地无此镜像即触发 build，而部署机没有 Dockerfile，报 `failed to read dockerfile: open Dockerfile.external-api: no such file or directory`。**必须显式 export `BACKEND_IMAGE`/`ECOM_IMAGE`/`SUP_IMAGE`**。与 12:02 条目里 `PUBLIC_BACKEND_IMAGE` 的坑同源。此次失败未破坏运行中的容器，但会浪费一轮排查。
  - 附带注意：`api` 服务 `depends_on: seed (service_completed_successfully)`，重建时须带 **`--no-deps`** 避免触发 seed 数据迁移（CI 在 `deploy.yml:331` 也是这么做的，那里有同样的注释）。本次只换 IP、不换镜像版本，seed 无关且有风险。
- 验证：
  - **登录端点实测**：`POST :8090/api/v1/app/auth/login` 用无效账号 → `{"code":10001,"message":"msg.auth.invalid_credentials"}`（401，1ms）。能判定"凭据错误"即证明查库正常；故障时此处返回 503 `msg.health.dependency_unavailable`（即 App 页面那句 temporarily unavailable）
  - `:8090`/`:8091`/`:8092` 的 `/api/v1/health/ready` 均由 `down` 转为 `up`
  - 四容器 `RestartCount=0` 且 healthy；`policy sync: reload failed` 停止；`docker exec ... printenv | grep 100.88.178.78` 无残留
- 结论：与 12:02 同一根因的遗漏面。**排查同类问题时，`grep -rl <旧IP> /home/ec2-user/stacks/` 应覆盖全部 stack，而不只是报错服务自己的 env。**
- 待办：CYP-2006 的 pre-flight 目前只保护 `iCare-public-backend` 的部署流程；`icare-backend`（7 处 DB host、3 个 env 文件、4 个容器）尚无任何防护，同一脚本挂到其部署流程即可补齐，需另开 Jira。

## 2026-08-10 12:02 CST - 修复 public-backend 崩溃循环：WEBKIT_DB_HOST 指向已失效的 tizi-cyp 旧 Tailscale IP

- 服务器：`dev-cypresso`
- 操作人：`Claude`
- 触发：iCare-public-backend `Deploy public-backend` workflow 的 `Deploy to dev-cypresso` job 连续失败（run `31350189741`，已是第 4 次 attempt）。同一 run 的 `Deploy to mas-go-dev` job 成功。
- 原因：
  - 2026-08-09 重装 `tizi-cyp` 系统后重新登录 Tailscale，其 Tailscale IP 由 `100.88.178.78` 变为 `100.116.91.14`。
  - `tizi-cyp` 是 dev-cypresso 访问 `mssql-ref` MSSQL 的 socat 转发跳板（直连 mssql-ref 太慢，必须走代理）。
  - dev-cypresso 上 `/home/ec2-user/stacks/icare/public-backend/.env.{app,hr,map}` 里 `WEBKIT_DB_HOST` 仍是旧 IP，三个容器启动时 `dial tcp 100.88.178.78:1433: i/o timeout` 而崩溃，陷入重启循环。
  - 这批 `.env.*` 由宿主机本地维护、不入库，CI 无从校验；部署脚本只能等 60s 健康检查超时后倒 200 行日志，定位成本高。
- 影响：
  - 改动 `.env.app` / `.env.hr` / `.env.map` 三个文件的 `WEBKIT_DB_HOST` 一行
  - 重建 `public-app` / `public-hr` / `public-map` 三个容器（重建前它们已在崩溃循环中，无可用服务，不存在打断正常服务）
- 备份：`/home/ec2-user/stacks/icare/public-backend/.env.{app,hr,map}.bak.20260810`
- 回滚方式：
  ```bash
  ssh dev-cypresso 'cd /home/ec2-user/stacks/icare/public-backend && \
    for f in .env.app .env.hr .env.map; do cp "$f.bak.20260810" "$f"; done'
  # 再按下方「变更时序」第 4 步重建容器
  ```
- 变更时序：
  1. 只读诊断：`tailscale status` 确认 tailnet 内已无 `100.88.178.78`；从 dev-cypresso 测 TCP，旧 IP:1433 timeout、`100.116.91.14:1433` OK
  2. 在 `tizi-cyp` 上确认转发存活且已持久化：`mssql-ref-proxy.service`（active/running），socat `TCP-LISTEN:1433,bind=100.116.91.14 → TCP:100.124.140.78:1433`
  3. 备份三个 env 文件后 `sed -i` 替换 `WEBKIT_DB_HOST`，并确认无旧 IP 残留
  4. 重建容器（注意本机**无 compose v2 CLI 插件**，须用 `/usr/local/bin/docker-compose`，其自身是 v2.24.5）：
     ```bash
     cd /home/ec2-user/stacks/icare/public-backend
     export PUBLIC_BACKEND_IMAGE=ghcr.io/cypressoai/icare-public-backend:<sha>
     export PUBLIC_APP_ENV_FILE=$PWD/.env.app PUBLIC_HR_ENV_FILE=$PWD/.env.hr PUBLIC_MAP_ENV_FILE=$PWD/.env.map
     docker-compose -f public-backend.compose.yaml up -d --force-recreate --pull never \
       public-app public-hr public-map
     ```
     （不带 `PUBLIC_BACKEND_IMAGE` 会回退到 compose 默认值 `icare/public-backend:local` 并报 GHCR `pull access denied`）
- 验证：
  - 复用 workflow 同款探测：`:8090` / `:8091` / `:8092` 的 `/api/v1/health/live` 均**首次尝试**即返回 `"status":"up"`
  - 容器日志近 5 分钟内无 `i/o timeout` / `failed to initialize database` / 旧 IP 记录
  - 观察 45s：三个容器 `RestartCount=0`、状态由 `health: starting` 转为 `Up About a minute (healthy)`，崩溃循环终止
- 结论：本次 CI 失败属 runner 侧环境配置问题，与提交代码无关。
- 待办：~~在部署脚本中增加 pre-flight —— `docker-compose up` 前先探测 `WEBKIT_DB_HOST:WEBKIT_DB_PORT` 连通性，不通则立即失败并打印明确原因，替代当前「等 60s 健康检查超时再倒日志」的排查方式。改动落在 `cypressoai/iCare-public-backend` 仓库（本机未克隆），交接文档见 `docs/handoffs/icare-public-backend-deploy-preflight-2026-08-10.md`。~~ **已完成**（2026-08-10）：CYP-2006 / [iCare-public-backend#120](https://github.com/cypressoai/iCare-public-backend/pull/120)，`scripts/preflight-db-reachable.sh`，已接入 `deploy-dev-cypresso` 与 `deploy-mas-go-dev` 两个 job。首次真实部署（run `31355448734`）三条 `preflight ok`，耗时约 250ms。**失败路径尚未在真机验证过。** 注：该仓其实已克隆在本机 `iCare/public-backend/`，交接文档中"本机未克隆"的判断有误。
- 备注：经确认 `tizi-cyp` 后续不会再重装，`WEBKIT_DB_HOST` 保持裸 IP，不改用 MagicDNS 名（会引入其他问题）。

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`dev-cypresso`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN（误报名碰撞）。actions-runner work 下 motion-dom + regenerate-unicode 名碰撞；preinstall=0。兼 CI+SIT。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-08-07 10:34 CST - 用脚本更新 icare-preview.apk

- 服务器：`dev-cypresso`
- 操作人：`Grok`
- 原因：本地 `icare-preview.apk` 更新，并用新建的一键脚本验证上传流程。
- 影响：
  - 覆盖 `/var/www/mas-icare.cypress.sg/apk/icare-preview.apk`
  - 新体积 `151756214` bytes，SHA256 `b9753ebfeba88ea5613a53ba001101f8b9b720a857b1950a6219cc107133008a`
  - 新增仓库脚本：`scripts/deploy-icare-preview-apk.sh`
- 备份：无（未开 `KEEP_BACKUP=1`）
- 回滚方式：用旧 APK 再跑一次脚本，或从本地历史文件覆盖
- 验证：
  - 脚本比对远端 size / SHA256 一致
  - `curl -I https://mas-icare.cypress.sg/apk/icare-preview.apk` → 200，`Content-Length: 151756214`

## 2026-08-07 09:46 CST - 发布 iCare preview APK 静态下载

- 服务器：`dev-cypresso`
- 操作人：`Grok`
- 原因：需要通过公网域名提供 `icare-preview.apk` 下载。
- 影响：
  - 新增静态文件：`/var/www/mas-icare.cypress.sg/apk/icare-preview.apk`（约 145MB / 151756090 bytes）
  - 公网 URL：`https://mas-icare.cypress.sg/apk/icare-preview.apk`
  - **未**修改 nginx conf（现有 `try_files $uri …` 已能命中真实文件；`Content-Type` 已是 `application/vnd.android.package-archive`）
  - 根路径与其它路径仍返回 SIT 结束说明页
- 备份：无（仅新增文件）
- 回滚方式：
  ```bash
  ssh dev-cypresso 'sudo rm -f /var/www/mas-icare.cypress.sg/apk/icare-preview.apk'
  # 如需整目录：
  # ssh dev-cypresso 'sudo rm -rf /var/www/mas-icare.cypress.sg/apk'
  ```
- 变更时序：
  1. `sudo mkdir -p /var/www/mas-icare.cypress.sg/apk`
  2. `scp` 本地 `icare-preview.apk` → 服务器 `/tmp/`，再 `mv` 到 web root
  3. `chmod 644`、属主 `root:root`
- 验证：
  - `curl -I https://mas-icare.cypress.sg/apk/icare-preview.apk` → **200**，`Content-Length: 151756090`，`Content-Type: application/vnd.android.package-archive`
  - 完整下载 size 与服务器 `stat` 一致
  - 文件头 magic `PK..`（ZIP/APK）

## 2026-08-04 19:49 CST - 修正 public-backend `MAS_INTERNAL_API_HEALTH_PATH` 并恢复容器

- 服务器：`dev-cypresso`
- 操作人：`Grok`
- 原因：同 mas-go-dev——Deploy 推送了 `ghcr.io/cypressoai/icare-public-backend:c2ddf907…` 后容器因旧路径 `/internal/mobile/health` 校验失败而 Restarting。
- 影响：
  - 更新 `/home/ec2-user/stacks/icare/public-backend/.env.{app,hr,map}` 的 `MAS_INTERNAL_API_HEALTH_PATH` → `/internal/public/v1/health`
  - `docker-compose -f public-backend.compose.yaml up -d --force-recreate public-app public-hr public-map`
- 备份：
  - `/home/ec2-user/stacks/icare/public-backend/.env.app.bak.20260804114906`
  - `/home/ec2-user/stacks/icare/public-backend/.env.hr.bak.20260804114906`
  - `/home/ec2-user/stacks/icare/public-backend/.env.map.bak.20260804114906`
- 回滚方式：
  ```bash
  ssh dev-cypresso 'BASE=/home/ec2-user/stacks/icare/public-backend
  for f in .env.app .env.hr .env.map; do cp -a "$BASE/$f.bak.20260804114906" "$BASE/$f"; done
  cd $BASE && PUBLIC_BACKEND_IMAGE=$(docker inspect --format "{{.Config.Image}}" icare-public-backend-public-app-1) \
    PUBLIC_APP_ENV_FILE=$BASE/.env.app PUBLIC_HR_ENV_FILE=$BASE/.env.hr PUBLIC_MAP_ENV_FILE=$BASE/.env.map \
    docker-compose -f public-backend.compose.yaml up -d --force-recreate public-app public-hr public-map'
  ```
- 验证：
  - `8090/8091/8092` live → `{"status":"up"}`
  - 日志 `service starting` version=`c2ddf907…`，webkit connected
- 备注：Deploy workflow job 本身仍记 failure；本机已手工恢复。

## 2026-08-03 15:50 CST - 部署机磁盘治理：work 日清 timer（不动 buildx）

- 服务器：`dev-cypresso`（`ip-172-31-42-99`，label 仅 `dev-cypresso-ci`）
- 操作人：`Grok`（iCare 自托管 runner 运维加固任务）
- 原因：部署机也需防 `_work` 堆积；**不做** 质量门 pnpm/go store 策略（与 CI 池分离）。
- 影响：
  - 脚本：`~/gha-scripts/{gha-runner-maintenance.sh,prune-gocache.sh}`
  - 无 cronie → **systemd timer** `gha-runner-maintenance.timer` 每日 03:50 UTC，只清三份 work 目录
  - 即时 age-prune `_temp`（mtime>+1d）
  - **保留** `/var/cache/buildx/*`（~4.4G 各项目 cache 未 prune）
  - **未** `docker system prune -a`；当前 Docker Images reclaimable ~6.8G、Volumes ~41G（仅 3% reclaimable）— 仅记录，未删
- 备份：无破坏性配置；timer 可 disable
- 回滚：`sudo systemctl disable --now gha-runner-maintenance.timer`
- 验证：`df` 约 **38% / Avail 156G**；`dev-cypresso-ci` Listener 仍在；buildx 目录列表完整
- 备注：系统无 `crontab` 命令属正常（AL2023 未装 cronie）

## 2026-07-31 14:50 CST - mas-icare.cypress.sg 改为 SIT 结束静态说明页

- 服务器：`dev-cypresso`
- 操作人：`Grok`（用户要求）
- 原因：SIT 测试阶段结束；公网入口 `https://mas-icare.cypress.sg/` 不再反代 `mas-icare-portal` 容器，改为静态英文说明页，引导从 2026-08-03 起使用 UAT。
- 影响：
  - `https://mas-icare.cypress.sg/`（及任意路径）返回静态 notice，**不再**代理 `127.0.0.1:5174` / `/api/` → `api-icare.cypress.sg`
  - SSL（Certbot）与 HTTP→HTTPS 301 保持不变
  - **未**停止 `mas-icare-portal` 等业务容器（仅切入口；容器仍监听本机 5174）
- 备份：
  - `/etc/nginx/conf.d/mas-icare.cypress.sg.conf.bak.20260731-sit-notice`
- 回滚方式：
  ```bash
  ssh dev-cypresso 'sudo cp /etc/nginx/conf.d/mas-icare.cypress.sg.conf.bak.20260731-sit-notice /etc/nginx/conf.d/mas-icare.cypress.sg.conf && sudo nginx -t && sudo systemctl reload nginx'
  ```
- 变更时序：
  1. 备份现有 nginx conf
  2. 写入 `/var/www/mas-icare.cypress.sg/index.html`（英文 notice）
  3. 重写 `mas-icare.cypress.sg.conf`：`root` + `try_files`，去掉 `proxy_pass`
  4. `nginx -t` 通过后 `systemctl reload nginx`
- 验证：
  - `curl -sS -o /dev/null -w '%{http_code}' https://mas-icare.cypress.sg/` → **200**
  - 响应体含 `SIT testing phase has ended` / `2026-08-03` / UAT 说明
  - `/api/` 同样 200 且为同一静态页（不再走上游）
  - HTTP 80 → 301 到 HTTPS

## 2026-07-31 14:21 CST - 停用 Runner 2（止血，未注销）

- 服务器：`dev-cypresso`
- 操作人：`Grok`（用户确认只做此项）
- 原因：Runner 2 仅有默认 label `self-hosted, Linux, X64`，会接泛化 self-hosted CI（近期多为 `iCare-mobile-app` Sonar）；本机按 CPU 计费，需先止血。
- 影响：
  - `ip-172-31-42-99.ec2.internal-2`（agentId **18**）不再接 job
  - **未**从 org 注销，目录 `~/actions-runner-2` 保留
  - Runner 1（`dev-cypresso-ci`）继续承接部署；workflow 侧 CI 误用 `dev-cypresso-ci` 由用户自行改
- 备份：无（仅 stop + disable 服务）
- 回滚方式：
  ```bash
  ssh dev-cypresso 'sudo systemctl enable --now actions.runner.cypressoai.ip-172-31-42-99.ec2.internal-2.service'
  ```
- 变更时序：
  1. 确认 agentId 18 `busy=false`
  2. `sudo systemctl stop` + `disable` unit `actions.runner.cypressoai.ip-172-31-42-99.ec2.internal-2.service`
  3. 确认本机无 `actions-runner-2` 进程；Runner 1 unit 仍为 active
- 验证：
  - 本机：unit **inactive / disabled**
  - GitHub API：runner 18 **offline**；runner 17 仍 **online**，labels 含 `dev-cypresso-ci`
- 说明：截图中 `Runner group name: 'default'` 是 org 默认 runner group，与本次误接 CI **无关**；路由靠 **labels**（`dev-cypresso-ci` / 默认 Linux labels），不是 group 名。

## 2026-07-31 14:12 CST - 只读：runner 配置与误接 CI 根因

- 服务器：`dev-cypresso`（`ip-172-31-42-99.ec2.internal`）
- 操作人：`Grok`（只读排查，未改 runner / 服务 / 标签）
- 原因：用户指出 job `cypressoai/iCare-public-backend` run `30607563562` / job `91082991915` 被本机接走；希望本机只接部署、不接 CI（CPU 按时计费）。
- 排查现状：
  - **Runner 1** `ip-172-31-42-99.ec2.internal`（agentId **17**，online）：labels `self-hosted, Linux, X64, dev-cypresso-ci`；systemd `actions.runner.cypressoai.ip-172-31-42-99.ec2.internal.service` active；目录 `~/actions-runner`（v2.336.0）
  - **Runner 2** `ip-172-31-42-99.ec2.internal-2`（agentId **18**，online）：labels **仅** `self-hosted, Linux, X64`（无部署专用 label）；`~/actions-runner-2`
  - **Runner 3** `ip-172-31-42-99.ec2.internal-3`：unit 存在但 **inactive/disabled**（`~/actions-runner-3`）
  - 目标 job：`test-lint-build`，`runs-on: dev-cypresso-ci`，runner_name = `ip-172-31-42-99.ec2.internal`（纯 CI：Test / Lint / Build / Smoke）
  - 近期 Worker 日志：
    - Runner 1：多数为 `deploy.yml`（set-vars / build-push / Deploy）；夹杂 `iCare-public-backend` 的 `ci.yml`
    - Runner 2：几乎全是 `iCare-mobile-app` 的 `sonar.yml`（SonarQube Scan）——靠默认 `self-hosted/Linux/X64` 被泛化匹配
  - 仓库侧误用 `dev-cypresso-ci` 做 CI 的 workflow：
    - `iCare-public-backend` `.github/workflows/ci.yml` → `runs-on: dev-cypresso-ci`
    - `iCare-mobile-backend` `.github/workflows/ci.yml` → 同上
  - 对照正确用法（`iCare-backend` / `iCare-frontend-mas` deploy）：质量 job 用 `backend-ci` / Mac 池；`set-vars` / build-push / Deploy 才用 `dev-cypresso-ci`
- 影响：无（只读）；问题仍存在，CI 会继续打满本机 CPU 计费
- 备份：无
- 回滚：不适用
- 建议修复（待用户确认后再动）：
  1. **workflow**：上述两个仓库 `ci.yml` 改为 `backend-ci` 或 `ubuntu-latest`（有 Docker smoke 时优先 Linux 有 Docker 的池 / GitHub-hosted）
  2. **runner-2**：停服务或从 org 注销（不参与部署池，只会接泛化 self-hosted CI）
  3. runner-1 保持 `dev-cypresso-ci`，**不要**贴 `backend-ci` / 质量类 label
- 验证：GitHub API 与本机 `.runner` / systemd / Worker 日志交叉核对一致
- 参考：`docs/runbooks/ci-runner-pools.md`；2026-07-20 条目「CI 池：dev-cypresso 仅保留部署标签」

## 2026-07-28 17:56 CST - EBS 扩至 250G 后 guest 侧 growpart + xfs_growfs

- 服务器：`dev-cypresso`
- 操作人：`Grok`（用户已在云侧把卷扩到 250G）
- 原因：用户确认 EBS 已扩到 250G，要求检查是否在系统内生效。
- 排查现状（guest 侧补全前）：
  - 整盘 `nvme0n1`：**250G**（云侧已生效）
  - 分区 `nvme0n1p1` 与 XFS `/` 仍为 **100G**；末尾约 **150G Free Space** 未用
  - `fdisk` 提示 GPT PMBR / backup GPT 不在磁盘末尾（扩容后预期状态）
  - 根盘使用率约 **75–76%**（75–76G / 100G）
- 影响：
  - 在线扩展分区与文件系统，**无重启**、未改服务/容器
  - 扩后：`/` **250G**，已用约 **77G**，可用约 **174G**，使用率 **31%**
- 备份：无（仅扩大容量，未改数据）
- 回滚：XFS / 分区 online 扩展后不能无损缩回；若需缩容须另做迁移/重建
- 变更时序：
  1. 确认 `lsblk`：盘 250G、分区 100G
  2. `sudo growpart /dev/nvme0n1 1` → p1 变为 250G
  3. `sudo xfs_growfs -d /` → data blocks `26211323` → `65532923`
- 验证：
  - `df -hT /`：`/dev/nvme0n1p1` xfs **250G** / Used 77G / Avail 174G / **31%**
  - `lsblk`：`nvme0n1` 与 `nvme0n1p1` 均为 **250G**
  - `parted … print free`：无尾部 Free Space，p1 占满至 250GiB

## 2026-07-21 14:15 CST - 决议：维持 tizi-cyp 跳板；TS direct / Peer Relay 作备选

- 服务器：`dev-cypresso`（链路决策，涉及家宽 / `mssql-ref` / `tizi-cyp` / `km-landui`）
- 操作人：`Grok` / 用户确认
- 原因：评估能否把第二跳 `tizi-cyp`→`mssql-ref` 从 DERP 升级为 TS `direct`；用户决定 **保持现状**。
- 影响：**无变更**。继续使用姿势 1（`DB_HOST=100.88.178.78` → `tizi-cyp` socat → `100.124.140.78:1433`）。
- 调研摘要：
  1. **现状路径（保留）**  
     `dev-cypresso` --TS direct ~61ms--> `tizi-cyp:1433` --TS DERP ~185ms--> `mssql-ref:1433`  
     第一跳稳定；端到端 ~240–260ms；API healthy。
  2. **方案 B（真 TS direct）不可靠 — 不实施**  
     - 家宽 OpenWrt（Kwrt）`miniupnpd` 配置 enabled，但进程 **not running**（STUN `stun.miwifi.com` 失败后 EXITING）；LAN SSDP 响应 0。  
     - WAN 为运营商 **CGNAT** `100.65.11.174`（`100.64/10`）；TS STUN 见 `112.117.237.237` 且 `MappingVariesByDestIP: true`。  
     - UPnP 最多映射家路由这一层，**打不穿运营商外层 CGNAT**。  
     - 用户明确：**不修 miniupnpd**。  
     - 家宽另跑 Passwall/xray，多数流量出口显示 `89.208.242.203`（`tizi-cyp`）；TS UDP 仍走物理线 `112.117.x`。
  3. **方案 A（km-landui Peer Relay）— 备选，未部署**  
     - `km-landui`：`43.228.79.237`，Ubuntu 22.04，**未装 Tailscale**。  
     - RTT：`mssql-ref`→`km-landui` 公网 ~4.4ms；`tizi-cyp`↔`km-landui` ~176ms 稳定。  
     - 做法：装 TS → `tailscale set --relay-server-port=<udp>` → ACL grant `tailscale.com/cap/relay`（`src` 限家侧节点，忌 `*`）。  
     - 预期：`tizi-cyp`→`mssql-ref` 显示 `peer-relay`（非 `direct`），吞吐/稳定性通常优于公共 DERP `km`；RTT 仍约 ~180ms 级（地理下限）。  
     - 触发条件（任选）：DERP 抖动不可接受、SQL 吞吐不够、或将来要惠及更多连家宽的 peer。
- 回滚：现状即稳态，无需回滚。
- 参考：`docs/operations/tizi-cyp.md`（跳板部署）、`docs/operations/mssql-ref.md` / 家宽相关条目。

## 2026-07-21 13:32 CST - iCare DB 经 tizi-cyp 跳板访问 mssql-ref（姿势 1）

- 服务器：`dev-cypresso`
- 操作人：`Grok`
- 原因：直连 `100.124.140.78` DERP 差；改走 `tizi-cyp` TS 跳板（见 `docs/operations/tizi-cyp.md` 同日）。
- 影响：
  - `/home/ec2-user/stacks/icare/.env`：`DB_HOST` / `WEBKIT_DB_HOST` / `SALESPORTAL_DB_HOST`  
    `100.124.140.78` → **`100.88.178.78`**
  - `force-recreate` `icare-backend-api-1` + `icare-backend-worker-1`（镜像未变：`fe0323ce2ca4635a9c54e8ddab6e0d738f8a499b`）
  - 未动 portal / shared-* / seed
- 备份：`/home/ec2-user/stacks/icare/.env.bak.20260721-tizi-cyp-proxy`
- 变更时序：
  1. `tizi-cyp` 上 `mssql-ref-proxy` active 且仅 TS 监听。
  2. 备份 `.env` 后改三个 `*_HOST`。
  3. `BACKEND_IMAGE=<当前> docker-compose -f backend.compose.yaml up -d --no-deps --no-build --force-recreate api worker`
- 验证：
  - 日志：`database connected` ×3，host 均为 `100.88.178.78`（preprod / maswebkit / insularsalesportal）
  - API health → `healthy`；真实请求 200（如 contract-cutoffs latency ~0.6–1s）
  - TCP：`100.88.178.78:1433` 热建连 ~61ms；直连 `100.124.140.78` 仍 ~0.6–1s
- 回滚：
  ```bash
  ssh dev-cypresso 'cp /home/ec2-user/stacks/icare/.env.bak.20260721-tizi-cyp-proxy /home/ec2-user/stacks/icare/.env && chmod 600 /home/ec2-user/stacks/icare/.env && cd /home/ec2-user/stacks/icare && BACKEND_IMAGE=ghcr.io/cypressoai/icare-backend:fe0323ce2ca4635a9c54e8ddab6e0d738f8a499b docker-compose -f backend.compose.yaml up -d --no-deps --no-build --force-recreate api worker'
  ```
- 备注：
  - 若 CI/手动部署用模板重写 `.env` 且仍写 `100.124.140.78`，会冲掉跳板；需把模板/ secret 同步为 `100.88.178.78`，或部署后补丁。
  - 单条 SQL 仍可能 ≥1s（多 RTT × ~245ms 路径），属路径物理限制。

## 2026-07-21 13:08 CST - 只读排查到 mssql-ref 的高延迟（Tailscale DERP 中继）

- 服务器：`dev-cypresso`（`ip-172-31-42-99.ec2.internal` / TS `100.115.69.120`）
- 操作人：`Grok`
- 原因：用户反馈 `ssh dev-cypresso` 到达 `mssql-ref` 延迟很高（截图 ping `100.124.140.78` avg ~375ms），怀疑未走 Tailscale。
- 影响：**只读**。未改 Tailscale 配置、防火墙或路由。
- 结论：
  1. **已走 Tailscale**：`ip route get 100.124.140.78` → `dev tailscale0 table 52 src 100.115.69.120`；本机有 `tailscale0`（`100.115.69.120`）。
  2. **不是 direct 直连**，而是 DERP 中继：`tailscale status` 对 `mssql-ref` 显示 `active; relay "km"`（Kunming）；对端视角为 `relay "iad"`（Ashburn）。`CurAddr` 为空。
  3. 地理分布导致中继 RTT 必然高：
     - `dev-cypresso` 在 AWS（公网 `32.192.186.193`），Nearest DERP **Ashburn**（~2ms），到 `km` ~227ms。
     - `mssql-ref` 在家宽（出口 `112.117.237.237`），Nearest DERP **Kunming**（~4.5ms）；且 `MappingVariesByDestIP: true`，不利于 UDP 打洞。
  4. 复测 ping `100.124.140.78`：~249–253ms，0% loss；ping LAN `192.168.2.20` 从本机不可达（预期，未 accept subnet routes）。
  5. 对照：同家网 `mas-go-dev` → `mssql-ref` TS ~1–23ms、LAN ~0.4ms（直连正常）。
- 备份：无变更。
- 回滚：无变更。
- 可选后续（未做，需确认）：
  - 排查/放行两端 UDP（含 AWS SG 入站 ephemeral + 家宽 NAT），争取 direct。
  - 业务侧优先经家网节点（`mas-go-dev` / `pve`）访问 `192.168.2.20`，避免跨洋 DERP。
  - 评估 exit node / subnet router 路径是否更优（当前 health：`--accept-routes is false`）。

## 2026-07-20 13:45 CST - CI 池：dev-cypresso 仅保留部署标签

- 服务器：`dev-cypresso`（runner `ip-172-31-42-99.ec2.internal` id 17）
- 操作人：`Grok`
- 原因：统一 self-hosted 调度；质量门禁（Lint/Sonar/Tests）迁出部署机，提高部署链路稳定性与 PR 吞吐。
- 影响：
  - runner id 17 **保持** `dev-cypresso-ci`，**未**增加 `frontend-quality-ci` / `frontend-tests-ci` / `backend-ci`。
  - 前端 PR Lint 不再 `runs-on: dev-cypresso-ci`（见 frontend-mas PR #1185）。
  - set-vars / build-push / Deploy to Server 仍仅此池。
- 回滚：workflow 改回 `dev-cypresso-ci`；或给 id 17 临时加回质量 label（不推荐）。
- 验证：`gh api orgs/cypressoai/actions/runners/17/labels` 仅含部署相关自定义 label `dev-cypresso-ci`。
- 参考：`docs/runbooks/ci-runner-pools.md`



## 2026-07-14 18:05 CST - nginx 全局 client_max_body_size 100M

- 服务器：`dev-cypresso`
- 操作人：`Grok`
- 原因：大文件上传（如成员导入 Excel）在默认 `client_max_body_size 1m` 下会被 nginx 直接 413；将上传体上限提高到 `100M`。
- 影响：
  - 宿主机 `/etc/nginx/nginx.conf` 的 `http` 块新增 `client_max_body_size 100M;`，作用于全部 vhost（含 `api-icare` / `mas-icare` / `hr-icare` 等）。
  - 既有 `sonar.cypresso.ai.conf` 里 server 级 `100m` 不变。
  - 容器 `mas-icare-portal` 的 `/etc/nginx/conf.d/default.conf` 同步加了 server 级 `client_max_body_size 100M;`（直接打 5174 时也生效）。
  - 仅 `reload`，无 restart；连接不中断。
- 备份：
  - `/etc/nginx/nginx.conf.bak.20260714`
  - 容器内 `/etc/nginx/conf.d/default.conf.bak.20260714`（随容器生命周期，镜像重建后失效）
- 变更时序：
  1. 备份宿主机 `nginx.conf`。
  2. 在 `http` 块 `keepalive_timeout 65;` 后插入 `client_max_body_size 100M;`。
  3. `sudo nginx -t` 通过后 `systemctl reload nginx`。
  4. 容器内 portal 同步改 `default.conf` 并 `nginx -s reload`。
- 验证：
  - `nginx -t` 通过（既有 warning：`conflicting server name "_" on 0.0.0.0:80, ignored`）。
  - `systemctl is-active nginx` → `active`。
  - `nginx -T` 可见全局 `client_max_body_size 100M;`；portal 容器内亦可见 `100M`。
- 回滚：
  ```bash
  ssh dev-cypresso 'sudo cp /etc/nginx/nginx.conf.bak.20260714 /etc/nginx/nginx.conf && sudo nginx -t && sudo systemctl reload nginx'
  # portal 容器（若仍为当时实例）：
  # docker exec -u root mas-icare-portal sh -c 'cp /etc/nginx/conf.d/default.conf.bak.20260714 /etc/nginx/conf.d/default.conf && nginx -t && nginx -s reload'
  ```
- 备注：
  - portal 容器内改动会在下次 runner 重建镜像/容器后丢失；若需永久生效，应把 `client_max_body_size` 写进 frontend-mas 镜像的 nginx 模板。
  - 宿主机全局配置不受 portal 重建影响。

## 2026-07-14 11:41 CST - CYP-1302：后端 api/worker 设 TZ=Asia/Manila

- 服务器：`dev-cypresso`
- 操作人：`Grok`（对应 Jira `CYP-1302` 第 2 项）
- 原因：治后端约 507 处 `time.Now()` 使用 UTC 宿主/容器时区的问题，使 Go 进程本地墙钟与 `mssql-ref` PHT 约定一致。
- 影响：
  - `/home/ec2-user/stacks/icare/.env` 追加 `TZ=Asia/Manila`（`.env.docker` 仍为指向 `.env` 的符号链接）。
  - 仅 `force-recreate` `icare-backend-api-1` + `icare-backend-worker-1`；未动 seed / gotenberg / shared-* / portal / telegram-bot。
  - 镜像未变：`ghcr.io/cypressoai/icare-backend:cadac74a9171f69298f23eb0fb61d85823d7eae0`。
  - API 短暂不可用约 30s（health 从 starting → healthy）。
- 备份：
  - `/home/ec2-user/stacks/icare/.env.bak.20260714-tz-manila`（改前完整副本，600 权限）。
- 变更时序：
  1. 备份 `.env`。
  2. 文件末尾追加注释 + `TZ=Asia/Manila`（`diff` 仅此新增，无其它字段改动）。
  3. `BACKEND_IMAGE=<当前 api 镜像> docker-compose -f backend.compose.yaml up -d --no-deps --no-build --force-recreate api worker`（必须带 `BACKEND_IMAGE`，否则会回退到不存在的 `icare/backend:local`）。
- 验证：
  - `docker exec icare-backend-api-1` / `worker`：`TZ=Asia/Manila`，`date` 为 PST（+0800）本地墙钟，`date -u` 为 UTC。
  - `icare-backend-api-1`：`Up ... (healthy)`；worker `Up`。
- 回滚：
  ```bash
  ssh dev-cypresso 'cp /home/ec2-user/stacks/icare/.env.bak.20260714-tz-manila /home/ec2-user/stacks/icare/.env && chmod 600 /home/ec2-user/stacks/icare/.env && cd /home/ec2-user/stacks/icare && BACKEND_IMAGE=ghcr.io/cypressoai/icare-backend:cadac74a9171f69298f23eb0fb61d85823d7eae0 docker-compose -f backend.compose.yaml up -d --no-deps --no-build --force-recreate api worker'
  ```
- 备注：
  - `TZ` 写在本地 `.env`，CI 滚动部署只要继续 `env_file: .env.docker` 且不覆盖该文件即可保留。若以后用模板重写 `.env`，需把 `TZ=Asia/Manila` 写回（建议同步进仓库 `.env.docker.example`）。
  - 仅改 `TZ` **不能**单独闭环 CYP-1302：代码侧 `NowFunc` 的 `.UTC()`、读路径 RFC3339 带 `Z` 等仍待改（ticket 第 3–5 项）。

## 2026-07-11 15:39 CST - 重试 iCare backend 部署成功（MSSQL Tailnet 链路恢复后）

- 服务器：`dev-cypresso`
- 操作人：`用户`（重试 GitHub Actions）/ `Codex`（只读验证）
- 原因：上一轮部署因 `dev-cypresso -> mssql-ref:1433` 的短暂 Tailscale 单向断联，在 migrate 阶段超时失败；链路自行恢复后重试同一 Job。
- 影响：GitHub Actions 已将 `icare-backend-api-1` 与 `icare-backend-worker-1` 切换至镜像 `ghcr.io/cypressoai/icare-backend:a5f37276fde1dd7dd08357893f63a3868ea2a4a1`。本条仅记录用户已完成的部署，并做只读核验；Codex 未修改配置或手动启停服务。
- 验证：
  - API：`running`、`healthy`，启动于 `15:37:27 CST`，`RestartCount=0`。
  - worker：`running`，启动于 `15:37:28 CST`，`RestartCount=0`；日志显示监听 `default` 和 `reports` 队列。
  - API/worker 启动日志均已成功连接 `100.124.140.78` 上的 `medicalassistance_preprod`；API 还成功连接 `maswebkit`、`insularsalesportal`。
  - 从宿主机复测 `100.124.140.78:1433` TCP 可达。
- 回滚：如需回退，应通过 GitHub Actions 部署先前已验证的镜像版本；本次未在服务器上执行手动回滚操作。

## 2026-07-11 15:32 CST - 排查 iCare backend 部署因 MSSQL Tailnet 链路超时失败（只读）

- 服务器：`dev-cypresso`
- 操作人：`Codex`
- 原因：GitHub Actions run `29144084042` 部署 commit `a5f37276fde1dd7dd08357893f63a3868ea2a4a1` 失败；用户已延长后端超时时间，但 Job 仍在 migrate 阶段退出。
- 影响：本次仅做只读检查与连通性探测，未改配置、未重启服务、未重跑 Job。失败发生在部署的 `migrate -> seed-check -> seed` 前置流水线，尚未执行旧 api/worker 的停止、删除或重建；线上仍运行旧镜像 `487253c4d814aa2a3aff638b02bbefcf36349f9d`，API healthy、worker running，`RestartCount=0`。
- 根因 / 证据：
  - Job 于 `15:15:28 CST` 报 `dial tcp 100.124.140.78:1433: i/o timeout`，目标为 `DB_HOST=100.124.140.78`、`DB_NAME=medicalassistance_preprod`；所以延长应用层超时只能增加等待时间，不能解决 TCP 建连失败。
  - `dev-cypresso` 的 `tailscaled` 为 active，路由正确走 `tailscale0`，但最初 `tailscale ping 100.124.140.78` 与 1433 TCP 探测均超时；日志从 `15:15:18 CST` 起连续记录 `open-conn-track: timeout opening`。
  - API 从 `15:28 CST` 起的 `policy sync: reload failed` 与 Job 相同，均为到 `100.124.140.78:1433` 的连接超时；健康检查仍返回 200，不能代表数据库链路可用。
  - 对端只读核验见 `docs/operations/mssql-ref.md` 同时间条目：SQL Server 正常监听 1433、资源充足。本次事件收敛为 `dev-cypresso -> mssql-ref` 的短暂单向 Tailscale/NAT 数据路径中断，而非 SQL Server 停止或后端代码异常。
- 验证：排查期间链路自行恢复，`tailscale ping` 变为 `via 89.208.242.203:50249 in 237ms`，`100.124.140.78:1433` TCP 随后可达；API 成功完成两次 `casbin_rule` 查询（约 1.0–1.8s）。未采取修复动作。
- 回滚：无服务器变更，无需回滚。
- 后续：可直接重试该 GitHub Actions Job；若再次出现单向断联，先保留两端 `tailscaled` 日志与 `tailscale ping` 结果，再经用户确认后考虑重启 `mssql-ref` 的 `tailscaled`（会短暂中断该节点 Tailnet 连接，不重启 SQL Server）。

## 2026-07-01 12:54 CST - 修复 Azurite 缺 `mas` container 导致成员导入上传 500

- 服务器：`dev-cypresso`
- 操作人：`Claude`
- 原因：公网入口 `https://mas-icare.cypress.sg/`（nginx 反代到本机 `icare-backend-api-1`）上传成员导入 Excel 报 500——`POST /api/v1/admin/group-accounts/7811/member-importing-history/upload`。根因是 iCare backend 往 Azure Blob（本机 `shared-azurite` 模拟器）存文件时，目标 container `mas` 不存在，Azurite 返回 `404 ContainerNotFound`，`internal/modules/groupaccount/service/member_import_upload.go:94` 的 `memberImportStore.Save` 失败 → `ErrMemberImportFileSaveFailed` → handler `handleMemberImportUploadError`（handler.go:4408）映射成 500。这是与同日 worker 队列问题**独立的第二个 bug**：worker 那个卡在异步消费阶段，这个卡在 API **同步存 blob** 阶段，即使 worker 修好、上传接口也会先 500，任务根本入不了队。
- 现象证据（修复前）：
  - api 日志：`04:32:13 POST .../upload status:500 latency:1.209s`，但**无 error 详情**——因 `handleMemberImportUploadError` 兜底分支把未识别 error 映射 500 却不打日志，错误被吞。
  - azurite 日志：每次上传 `PUT /devstoreaccount1/mas/member-importing-history%2F...xlsx` 全部 `404`（6-30 至 7-01 无一例外），时间戳与 500 精确对应。
  - Azurite 元数据库 `/opt/azurite/__azurite_db_blob__.json` 的 `$CONTAINERS_COLLECTION$` docCount=0、`$BLOBS_COLLECTION$` docCount=0，`__blobstorage__/` 目录为空——**从未成功建过任何 container / 写过任何 blob**。这套 Azurite 是 2026-05-28 新上线的空模拟器，业务 container 需显式创建，但一直没建。
  - 代码侧确认只需 `mas` 一个 container：`internal/platform/storage/storage.go:24` `DefaultContainer="mas"`，全模块统一用 `cfg.Storage.AzureContainer`（默认 `mas`），api 容器未设 `AZURE_STORAGE_CONTAINER` 覆盖。日志里历史出现的 `group-account-contract-ledger` 是旧路径，现已废弃不用建。
- 影响：
  - 仅在 Azurite 里**新增一个空 blob container `mas`**。不改代码、不改配置、不重启任何容器、不动任何现有数据（本来也无数据）。
  - 创建后上传 PUT 从 404 变 201，文件正常落盘。
- 回滚：
  - 如需撤销：在 azurite 容器内对 `mas` 发签名的 `DELETE container` 请求即可（无理由回滚，纯新增）。
- 变更（按时序）：
  1. 只读确认：`docker exec shared-azurite node -e` 解析 `__azurite_db_blob__.json` → `$CONTAINERS_COLLECTION$` 为空，`mas` 确实缺失；代码确认 container 名应为 `mas`。
  2. azurite 容器无 `@azure/storage-blob` SDK，改用其自带 `node` 内置 `crypto`+`http` 手工构造 SharedKey 签名，对 `http://127.0.0.1:10000/devstoreaccount1/mas?restype=container` 发 `PUT container`。凭证为标准 `devstoreaccount1` 账号（连接串内置 key）。首次因签名漏把 `restype=container` query 计入 canonicalizedResource → 403 AuthorizationFailure；修正为在 canonicalizedResource 追加 `\nrestype:container` 后 → **201 Created**。
  3. 验证 container 落库 + 可写：元数据库 `$CONTAINERS_COLLECTION$` 出现 `mas`；PUT 一个 `__healthcheck_delete_me.txt` → 201，再 DELETE → 202（清理，不留垃圾）。
- 验证（用户在浏览器实测重传一次，端到端三层全绿）：
  - **API 同步层**：`04:54:37 POST .../upload status:200 latency:11.873s`（修复前 500 → 200）；审计日志记 `response_status:200`，操作人 KADMIN(userNo 2611)。
  - **Azurite 存储层**：`04:54:29 PUT .../mas/...NR-PD-7811-...xlsx 201`（落盘）→ `04:54:38 GET ...xlsx 200 6622`（worker 读回 6622B）→ `04:54:50 PUT ...-receipt.xlsx 201`（worker 写回失败回执）。
  - **Worker 异步层**：`04:55:11 worker task completed jobType=member_import.parse jobID=portal-upload:105920`——`member_import.parse` 走 `default` 队列被 worker 接手并跑完（含 dummymemberno 分配、`sp_uploadmemmapmemberfees`、termination fees 等存储过程）。同时验证了同日 worker 队列修复也生效。
  - 上传 → 存储 → 入队 → worker 解析 → 写回回执整条链路**首次完整跑通**。
- 备注：
  - worker 日志多条 `SLOW SQL >= 1s`、上传接口 latency 11.8s，属**正常现象**——服务在本机、`medicalassistance_preprod` 数据库跨洲，网络往返延迟导致，非故障，不作为问题跟踪。
  - 上游隐患：Azurite 是空模拟器、container 靠手动创建，VM/容器重建或数据卷重置后 `mas` 会再次消失、上传又 500。根治应在部署/初始化流程里加一步"确保 `mas` container 存在"（如 infra compose 加个 init 容器跑 `az storage container create` 或等价脚本）。属独立任务，本次未做。

## 2026-07-01 12:25 CST - 修复 worker 漏配 reports 队列（Report Center 报表任务一直卡 pending）

- 服务器：`dev-cypresso`
- 操作人：`Claude`
- 原因：排查"测试服上传/异步任务不生效"时发现，`icare-backend-worker-1` 只消费 `default` 队列，Report Center 的报表任务全部卡在 `reports` 队列没人消费。根因是 `/home/ec2-user/stacks/icare/.env` 里显式写了 `WORKER_QUEUES=default:1`，覆盖了代码默认值。iCare backend 代码 `internal/config/config.go:210` 的默认队列是 `{"default":1,"reports":1}`（注释：`"reports" is the Report Center async queue (G2)`），只要不设 `WORKER_QUEUES` 就会同时监听两个队列；`envQueueWeights`（config.go:535）解析逻辑无 bug，是环境变量把 `reports` 覆盖没了。这不是代码 bug，是部署 env 配置漏项。回溯本文件 2026-05-28 15:55 那条上线记录第 22 行，当时 worker 日志就已经是 `queues={default:1}`，说明这个漏配从 worker 上线（PR #391）起就一直存在，只是当时 Report Center 还没投用没暴露。
- 现象证据（修复前）：
  - `docker exec icare-backend-worker-1 env | grep WORKER_QUEUES` → `WORKER_QUEUES=default:1`。
  - worker 启动日志：`starting worker ... "queues":{"default":1},"concurrency":1`——不含 reports。
  - Redis：`asynq:queues` 集合只有 `reports`；`asynq:{reports}:pending=1`，卡着任务 `report:1`（`report.generate`，requestID=1），`pending_since` 约 2026-06-30 15:53 UTC，卡了十几小时无人消费。
  - 排除项：磁盘根分区 58%（43G 可用）、inode 2%，非磁盘满；`shared-redis` PING=PONG、`QUEUE_PROVIDER=redis_asynq` 均正常；`report.generate` handler 已在代码 `internal/modules/reportcenter/module.go:81` 注册进 worker registry——worker 有能力处理，纯粹是没监听 `reports` 队列。
- 影响：
  - `/home/ec2-user/stacks/icare/.env` 删除第 50 行 `WORKER_QUEUES=default:1`（文件保持 `600` 权限，`.env.docker` 符号链接 → `.env` 不变）。
  - `icare-backend-worker-1` 容器重建（`.env` 改动必须 recreate 才会重读 env_file，restart 不够）。
  - 不动 api / seed / shared-* 基础设施 / mas-icare-portal / telegram-bot；仅重建 worker 一个容器。
- 回滚：
  - `cp /home/ec2-user/stacks/icare/.env.bak.20260701-worker-queues /home/ec2-user/stacks/icare/.env && chmod 600 /home/ec2-user/stacks/icare/.env`，然后按下方"变更"第 4 步同样命令重建 worker 即可恢复只监听 default 的旧状态。
- 变更（按时序）：
  1. `cp /home/ec2-user/stacks/icare/.env /home/ec2-user/stacks/icare/.env.bak.20260701-worker-queues`（备份，1411B，600 权限）。
  2. `sed -i '/^WORKER_QUEUES=default:1$/d' /home/ec2-user/stacks/icare/.env`（按整行内容精确删除，非按行号）。
  3. `diff` 备份与新文件确认**仅少 `WORKER_QUEUES=default:1` 一行**，其余一字未动。
  4. 重建 worker：本机 docker 无 `compose` 插件，用独立 `docker-compose` v2.24.5。部署时镜像 tag 由 CI 经 shell 层 `BACKEND_IMAGE` 传入（`.env` 里没有此变量），裸 `up` 会回退到默认 `icare/backend:local`（本机不存在）而失败——须显式带上与 api 相同的 tag：`cd /home/ec2-user/stacks/icare && BACKEND_IMAGE=ghcr.io/cypressoai/icare-backend:eaeecd6055a799cc662344f419836e99b8878644 docker-compose -f backend.compose.yaml up -d --no-deps --no-build worker`。
- 验证：
  - worker 新日志：`starting worker ... "queues":{"default":1,"reports":1},"concurrency":1`——已监听 reports ✅。
  - 卡住的 `report:1` 被立即消费：日志 `worker task failed ... jobType=report.generate jobID=report:1 error="record not found"`——这是**修复生效的证明**，不是新 bug：该孤儿任务卡了十几小时，worker 一起来就取出执行，因对应报表请求记录（requestID=1，测试残留）在 DB 已不存在而正常失败。重点是队列链路已通。
  - Redis：`asynq:{reports}:pending=0`、`active=0`、`archived=0`；`default:pending=0`；无堆积。
  - `docker ps`：`icare-backend-worker-1  Up`（重建后），api / 其它容器不受影响。
- 后续 / 待办：
  - **强烈建议核查 `mas-go-dev` 上的 worker 是否同样漏配 `WORKER_QUEUES`**——两台环境的 worker 部署形态是对齐的（同一 PR #391 形态），很可能同样只监听 default，Report Center 报表在 mas-go-dev 上会一样卡住。属独立任务，本次未做。
  - 上游隐患：`.env` 手写 `WORKER_QUEUES=default:1` 的来源未追溯（可能是 5-28 上线时抄模板带进来的）。如未来重新走 CI 部署或从模板重刷 env，注意别再把这行带回来；根治可考虑在部署脚本 / env 模板层显式设 `WORKER_QUEUES=default:1,reports:1` 或干脆不设（依赖代码默认）。

## 2026-05-28 15:55 CST - iCare backend 上线 worker 容器（PR #391 部署落地）

- 服务器：`dev-cypresso`
- 操作人：`Claude`
- 原因：mas-go-dev 已先行验证 api + worker + Azurite + Redis 全链路（参见 `docs/operations/mas-go-dev.md` 2026-05-28 12:47），现按计划 `docs/plans/2026-05-28-001-feat-dev-cypresso-icare-worker-rollout-plan.md` 把同形态推到 dev-cypresso，让 iCare 集成测试环境完整覆盖 worker 路径。
- 影响：
  - `/home/ec2-user/stacks/icare/.env` 追加 13 个 worker / queue / azurite 相关 KEY（文件 624B → 1405B），保持 `600` 权限。
  - iCare 仓库 PR #391 (`feat(CYP-707): dev-cypresso 部署联合滚动 api + worker`) 合并到 `develop` 后，self-hosted runner 在 dev-cypresso 上把 `icare-backend-api-1` + 新的 `icare-backend-worker-1` 两个容器一起滚到 sha `7aa85456a9ec87f2ca99eccd2f514264f30c53d5`。
  - 部署期间不动 shared-* 基础设施容器（azurite / redis / postgres / sqlserver 等），不动 mas-icare-portal / telegram-bot。
- 回滚：
  - env：`cp /home/ec2-user/stacks/icare/.env.bak.20260528-claude-worker-rollout /home/ec2-user/stacks/icare/.env && chmod 600 /home/ec2-user/stacks/icare/.env`，然后 ssh 上去 `cd /home/ec2-user/stacks/icare && docker-compose -f backend.compose.yaml stop worker && docker-compose -f backend.compose.yaml rm -f worker`。
  - deploy.yml：revert iCare 仓库 PR #391，下一次 develop 部署会回到只滚 api 的旧形态。
- 变更：
  - `/home/ec2-user/stacks/icare/.env` 备份到 `.env.bak.20260528-claude-worker-rollout`，追加 13 个 KEY；其中 `REDIS_ADDR=shared-redis:6379`、`REDIS_PASSWORD=` 空、`REDIS_TLS_ENABLED=false`、`AZURE_STORAGE_CONNECTION_STRING=...BlobEndpoint=http://shared-azurite:10000/devstoreaccount1;`，其余字段与 mas-go-dev 一致。
  - 注意：`.env.docker` 是符号链接 → `.env`，所以编辑落到 `.env`；deploy.yml 第 215-219 行优先用 `.env`。
  - iCare 仓库 `.github/workflows/deploy.yml` 的 `deploy` job `Deploy via SSH` step 改造（PR #391 #commit `7aa8545`）：`pull`/`stop`/`rm`/`up` 都纳入 worker；`up -d --no-deps api worker` 防止 seed 二次触发；api healthz 改成 break + 后置统一判断；新增 worker 存活校验段（`docker inspect` 看 15 秒窗口 RestartCount + State.Status）；失败时同时 dump api 与 worker 日志。
- 验证（PR #391 部署完成后立刻校验）：
  - `docker-compose ps`：api 与 worker 都跑同一镜像 `ghcr.io/cypressoai/icare-backend:7aa8545...`，api `Up 5 minutes (healthy)`，worker `Up 5 minutes`。
  - `docker inspect icare-backend-worker-1`：`RestartCount=0, Status=running, ExitCode=0, StartedAt=2026-05-28T07:53:42Z`。
  - worker 日志最后 3 行：`database connected (host=shared-sqlserver, database=medicalassistance_preprod)` → `starting worker (env=sit, queues={default:1}, concurrency=1)` → `asynq: Starting processing`；无 `worker stopped`（runtime.go bug 已在 commit `952d29c` / PR #389 修复）。
  - 从 worker 容器内 `getent hosts shared-redis shared-azurite` 各返回 IP（172.19.0.9 / 172.19.0.4）；TCP `</dev/tcp/shared-redis/6379` 与 `</dev/tcp/shared-azurite/10000` 均 OK。
  - `shared-services` 网络含 8 个成员，新增 `icare-backend-worker-1=172.19.0.2`。
  - api `/healthz` 返回 200，响应 1.5ms。
- 副作用观察：
  - **worker 连的数据库是 `medicalassistance_preprod`**（不是 mas-go-dev 上的 `medicalassistance`）—— 这是 dev-cypresso 现有 `.env` 里 `DB_NAME` 的既定配置，与本次上线无关，但记录在案以备未来对比 `dev-cypresso` 与 `mas-go-dev` 行为差异时参考。
  - `mas-icare-portal` 容器 StartedAt 在部署窗口内更新（2026-05-28T07:55:54）—— 不是本次 iCare backend 部署造成（不同 compose project），可能是 frontend-mas 同期跑了它自己的部署，未跟进。
- 后续：
  - 长期监控 worker：当前没有针对 worker 的健康告警，依赖 deploy.yml 部署期 RestartCount 校验做最低兜底；如未来 worker 在两次部署之间崩溃循环（restart policy 拉起但 RestartCount 累加），需要靠人肉巡检 `docker inspect icare-backend-worker-1` 发现。监控告警机制另议。
  - 计划文档收尾：`docs/plans/2026-05-28-001-feat-dev-cypresso-icare-worker-rollout-plan.md` 标记 `status: completed`。

## 2026-05-28 15:24 CST - shared-redis 移除 requirepass + shared-azurite 上线（含 env 改动副作用）

- 服务器：`dev-cypresso`
- 操作人：`Claude`
- 原因：为支持 iCare worker（CYP-699 / CYP-707）接入 dev-cypresso 集成测试环境，需要 Azure Blob 模拟器（Azurite）+ Redis Asynq 后端。Redis 现成可用（shared-redis）但启用了 `--requirepass`，与 mas-go-dev 简化方案对齐计划移除密码；Azurite 缺失，新增 `shared-azurite` service。事前清单显示实际消费 redis 的服务只有未来的 iCare worker（telegram-bot / mas-icare-portal / shared-postgres / shared-sqlserver 经 env 验证均不连 redis），端口 127.0.0.1 本身已经只接受本机访问，撤掉密码不显著扩大攻击面。
- 影响：
  - `/home/ec2-user/stacks/infra/docker-compose.yml`：新增 `azurite` service（container_name `shared-azurite`、image `mcr.microsoft.com/azure-storage/azurite:latest`、端口 `127.0.0.1:10000`、卷 `shared_azurite_data`、`restart: unless-stopped`，对齐 infra 内现有 shared-* 风格）；redis service `command` 去掉 `--requirepass "$REDIS_PASSWORD"`、healthcheck 去掉 `-a` 参数、`environment` 段删 `REDIS_PASSWORD: ${REDIS_PASSWORD}`。
  - `/home/ec2-user/stacks/infra/.env`：删除 `REDIS_PASSWORD=...` 一行。
  - `docker-compose up -d` 触发 `shared-redis` recreate（yaml 变了）+ `shared-azurite` 新建。
  - **意外副作用 1**：删 `.env` 一行后，所有以 `env_file: .env` 引用它的 service 的 env hash 都变了，导致 `shared-postgres` / `shared-rabbitmq` 也被 recreate；`sonarqube` 因依赖 postgres 也被 recreate。
  - **意外副作用 2**：`shared-mongodb` / `shared-clickhouse` / `shared-rabbitmq` / `sonarqube` 这 4 个本来在 2026-05-19 09:42 主动停掉的容器，被本次 `up -d` 按其 `restart: unless-stopped` 策略**拉起**，违背原运维意图（"服务已迁出 dev-cypresso"）。**已立即 `docker stop` 这 4 个容器恢复 Exited 状态**。
- 回滚（按层次）：
  - 完整回滚 azurite + 改回 redis 密码：`cp /home/ec2-user/stacks/infra/docker-compose.yml.bak.20260528-claude-worker-rollout /home/ec2-user/stacks/infra/docker-compose.yml && cp /home/ec2-user/stacks/infra/.env.bak.20260528-claude-worker-rollout /home/ec2-user/stacks/infra/.env && cd /home/ec2-user/stacks/infra && docker-compose up -d && docker-compose -f docker-compose.yml stop azurite && docker-compose -f docker-compose.yml rm -f azurite`。回滚也会再次拉起 4 个停掉的容器，需要重做一次 `docker stop`。
  - 仅恢复 redis 密码：单独 revert docker-compose.yml 里 redis 段，恢复 .env 里 REDIS_PASSWORD，再 `up -d`；同时把 worker 的 `.env` 里 `REDIS_PASSWORD=` 补回真实值（计划已知不会主动这么做）。
- 变更（按时序）：
  1. `cp /home/ec2-user/stacks/infra/docker-compose.yml /home/ec2-user/stacks/infra/docker-compose.yml.bak.20260528-claude-worker-rollout`
  2. 用 `awk` 在 `^networks:` 行前插入 azurite service（13 字段），在文件末尾追加 `shared_azurite_data:` 卷定义。
  3. `cp /home/ec2-user/stacks/infra/.env /home/ec2-user/stacks/infra/.env.bak.20260528-claude-worker-rollout`
  4. 用 Python 脚本（`/tmp/u2-redis-edit.py`）精确改三处：删 redis environment 段 / command 去 `--requirepass` / healthcheck 去 `-a`。
  5. `sed -i '/^REDIS_PASSWORD=/d' /home/ec2-user/stacks/infra/.env`
  6. `cd /home/ec2-user/stacks/infra && docker-compose up -d`
  7. `docker stop shared-mongodb shared-clickhouse shared-rabbitmq sonarqube`（修副作用 2）。
- 验证：
  - `docker exec shared-redis redis-cli ping` 直接返回 `PONG`（不带 `-a`）；带旧密码会被 `AUTH failed: ERR AUTH ... called without any password configured`，再后续 PONG，证明 requirepass 已移除。
  - `docker ps`：5 个长期 Up 容器（shared-postgres / shared-redis / shared-azurite / shared-sqlserver / sonarqube?）—— 实际为 `shared-postgres healthy`、`shared-redis healthy`、`shared-azurite up`、`shared-sqlserver up 10 days`、其余 4 个 `Exited`（恢复后）。`icare-backend-api-1 healthy`、`mas-icare-portal up`、`telegram-bot-bot-1 up 10 days` 不受影响。
  - `docker network inspect shared-services` 含 `shared-azurite=172.19.0.4`、`shared-redis=172.19.0.9`（新 IP 因 recreate）。
  - `docker volume ls` 含 `shared_azurite_data`、`shared_redis_data`（旧 redis 数据卷沿用，appendonly 未丢）。
  - 从 `icare-backend-api-1` 容器内 `getent hosts shared-redis shared-azurite`、TCP 测试均通。
  - 4 个意外拉起容器现已 `Exited`，与 2026-05-19 09:42 那条记录的目标状态一致。
- 教训（写进本条以备未来）：
  - **删 `.env` 里任一行都会 invalidate 所有 `env_file: .env` service 的 compose config-hash，触发 recreate**。这是 docker compose 的设计行为，不是 bug。未来要在 infra/.env 增删字段前，要先评估"哪些 service 引用它"。
  - **`docker-compose up -d` 会无视 `docker stop` 留下的 Exited 状态，按 `restart: unless-stopped` 拉起任何 yaml 里声明的容器**。如果要永久阻止某 service 自动拉起，应该从 yaml 里删除它，而不是单纯 `docker stop`。
- 后续：
  - 评估是否要把 mongodb / clickhouse / rabbitmq / sonarqube 这 4 个 service 从 `infra/docker-compose.yml` 里**注释或移除**，避免下次 `up -d` 又拉起。属于独立任务，不在本次计划范围。

## 2026-05-19 10:03 CST - 记录 nginx 安全升级待办

- 服务器：`dev-cypresso`
- 操作人：`Codex`
- 原因：近期 nginx 披露 `CVE-2026-42945` 等安全问题，需要确认 `dev-cypresso` 是否需要升级。
- 影响：本次只读检查和记录 TODO，未修改服务器配置，未升级软件，未 reload/restart nginx。
- 当前状态：
  - OS：Amazon Linux 2023
  - nginx：`nginx/1.28.2`，RPM 为 `nginx-1.28.2-1.amzn2023.0.1`
  - `nginx.service`：`active (running)`
  - `nginx -t`：通过，但存在既有 warning：`conflicting server name "_" on 0.0.0.0:80, ignored`
  - ASLR：`/proc/sys/kernel/randomize_va_space=2`
- 风险判断：
  - nginx 官方安全公告显示 `CVE-2026-42945` 的修复边界是 `1.30.1+` 或 `1.31.0+`，当前 `1.28.2` 在受影响版本范围内。
  - AWS CVE Explorer 中 Amazon Linux 2023 的 `nginx / CVE-2026-42945` 状态仍是 `Pending Fix`。
  - Amazon Linux 2023 官方仓库当前只提供到 `1.28.2-1.amzn2023.0.1`，没有可直接 `dnf update nginx` 的修复包。
  - nginx.org 官方 Amazon Linux 2023 stable 仓库已有 `1.30.1`，但 dnf 模拟安装失败，因为包依赖 `libssl.so.3(OPENSSL_3.5.0)`，而当前系统 OpenSSL 是 `3.2.2`。
- 配置观察：
  - `/etc/nginx/conf.d/mas-icare.cypress.sg.conf` 中有一条 `rewrite ^/api/(.*)$ /api/$1 break;`，使用了 `$1`。
  - 这条 rewrite 没有 `?`，不完全命中 `CVE-2026-42945` 描述里的典型触发条件，但后续建议改成 named capture 降低暴露面。
- 回滚：本次没有做服务器变更，无需回滚。
- TODO：
  - [ ] 过几天复查 Amazon Linux 2023 是否发布 nginx 修复包；如果已发布，优先走 Amazon 官方仓库升级。
  - [ ] 复查 nginx.org `1.30.1` 或更新包是否仍依赖 OpenSSL 3.5；不要为了 nginx 单独升级系统 OpenSSL，除非有明确兼容性方案。
  - [ ] 如官方修复仍未发布，考虑先备份并修改 `mas-icare.cypress.sg.conf`，把 `$1` rewrite 改为 named capture 后执行 `nginx -t && systemctl reload nginx`。
  - [ ] 修复完成后补一篇 `docs/solutions/dev-cypresso/security-issues/` 文档，记录 nginx CVE 处置方案。

## 2026-05-19 09:42 CST - 停止已迁出服务相关 Docker 容器

- 服务器：`dev-cypresso`
- 操作人：`Codex`
- 原因：部分服务已迁出 `dev-cypresso`，需要停止原服务器上的遗留容器，并确保服务器重启后这些容器不会自动启动。
- 影响：以下容器对应服务在 `dev-cypresso` 上停止；容器、镜像、数据卷均未删除。
- 回滚：

```bash
ssh dev-cypresso 'docker start shared-mongodb shared-clickhouse shared-rabbitmq cypresso-ui-web cypresso-api cypresso-doc hr-icare-portal'
```

如后续确认仍需随服务器启动自动拉起，再恢复 restart policy：

```bash
ssh dev-cypresso 'docker update --restart=unless-stopped shared-mongodb shared-clickhouse shared-rabbitmq cypresso-ui-web cypresso-api cypresso-doc hr-icare-portal'
```

### 变更

- 目标容器来自用户确认的编号：`1, 4, 5, 10, 11, 12, 13, 14`。
- 编号 `1` 对应的临时 buildx 容器 `buildx_buildkit_builder-93669b86-1e97-4178-9c2f-ec3ed32ed5690` 在操作前已不存在于 `docker ps -a`，未执行停止。
- 对以下容器执行 `docker update --restart=no`，防止服务器重启后自动启动：
  - `shared-mongodb`
  - `shared-clickhouse`
  - `shared-rabbitmq`
  - `cypresso-ui-web`
  - `cypresso-api`
  - `cypresso-doc`
  - `hr-icare-portal`
- 随后对上述容器执行 `docker stop`。

### 操作前状态

```text
/shared-mongodb       Status=running  Restart=unless-stopped  Image=mongodb/mongodb-atlas-local:8.0
/shared-clickhouse    Status=running  Restart=unless-stopped  Image=clickhouse/clickhouse-server:25.3
/shared-rabbitmq      Status=running  Restart=unless-stopped  Image=rabbitmq:4.2.3-management
/cypresso-ui-web      Status=running  Restart=unless-stopped  Image=cypresso-ui:latest
/cypresso-api         Status=running  Restart=unless-stopped  Image=cypresso-api:latest
/cypresso-doc         Status=running  Restart=unless-stopped  Image=cypresso-doc:latest
/hr-icare-portal      Status=running  Restart=unless-stopped  Image=icare-hr-portal
```

### 验证结果

目标容器停止后状态：

```text
/shared-mongodb       Status=exited  Restart=no
/shared-clickhouse    Status=exited  Restart=no
/shared-rabbitmq      Status=exited  Restart=no
/cypresso-ui-web      Status=exited  Restart=no
/cypresso-api         Status=exited  Restart=no
/cypresso-doc         Status=exited  Restart=no
/hr-icare-portal      Status=exited  Restart=no
```

操作后仍在运行的容器：

```text
icare-backend-api-1    Up, healthy
mas-icare-portal       Up
telegram-bot-bot-1     Up
shared-postgres        Up, healthy
shared-redis           Up, healthy
shared-sqlserver       Up
```
