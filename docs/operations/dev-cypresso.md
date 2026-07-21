# dev-cypresso 运维时间线

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
