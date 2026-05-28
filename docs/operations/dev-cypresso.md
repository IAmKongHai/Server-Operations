# dev-cypresso 运维时间线

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
