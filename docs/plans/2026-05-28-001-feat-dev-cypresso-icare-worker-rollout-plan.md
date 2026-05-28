---
title: dev-cypresso 上线 iCare worker + shared-azurite，对齐 mas-go-dev 模式
type: feat
status: completed
date: 2026-05-28
---

# dev-cypresso 上线 iCare worker + shared-azurite，对齐 mas-go-dev 模式

## Summary

把 dev-cypresso（AWS EC2，多项目共享 dev 环境）上的 iCare backend 部署对齐到 mas-go-dev 已经验证的形态：worker 容器随 api 一起滚动、新增 `shared-azurite` 容器作为 iCare 项目专属（但放在 infra 共享栈里方便未来其他项目复用）Blob 模拟器、worker 用现成的 `shared-redis` 作为 asynq 队列后端。**附带**做一次小幅安全权衡：移除 `shared-redis` 的 `--requirepass`（验证后实际 redis 消费者只有未来的 worker，简化运维风险可接受）。GHCR pull 模式保留，不改本地 build。

---

## Problem Frame

iCare 后端在 mas-go-dev 上已经跑通 `api + worker` 双容器 + Azurite/Redis infra 的完整链路。dev-cypresso 上目前只有 api 在跑——同一个 PR sha（`952d29ce`）部署落地后，因为 `deploy` job 没改、`.env` 里没补 queue/redis/azurite 字段、azurite 容器也不存在，worker 始终没起来，asynq 队列功能在这台机器上空缺。dev-cypresso 是团队日常验证的服务器，需要尽快补齐到与 mas-go-dev 行为一致，避免出现"PR 在 mas-go-dev 上能验，在 dev-cypresso 上不能验"的两套行为差。

---

## Requirements

- R1. dev-cypresso 上的 `shared-services` 网络新增 `shared-azurite` 容器，端口仅绑 `127.0.0.1:10000`，restart `unless-stopped`，与 infra 栈现有 shared-* 风格一致。
- R2. `shared-redis` 拿掉 `--requirepass`，相应清掉 `infra/.env` 里的 `REDIS_PASSWORD`，确认 redis 在 `shared-services` 网络上免密可达。
- R3. `/home/ec2-user/stacks/icare/.env` 补齐 worker 启动所需的 `QUEUE_PROVIDER` / `REDIS_*` / `AZURE_STORAGE_CONNECTION_STRING` / `WORKER_*` 字段；先备份再追加，保持 `600` 权限。
- R4. iCare backend 在 dev-cypresso 上每次 PR 部署能同时滚动 `api` + `worker`，部署脚本含 api healthz + worker RestartCount 双重存活校验；失败时同时 dump 两个容器日志。
- R5. 改完之后 dev-cypresso 上 worker 容器稳定运行（RestartCount 在 15 秒窗口内不增加），api `/healthz` 仍 200。
- R6. 全程保留可回滚路径：每个改动文件都有备份；shared-redis 重启如有意外可恢复带密码版本。
- R7. 不破坏现有其他容器：`mas-icare-portal` / `telegram-bot-bot-1` / `shared-postgres` / `shared-sqlserver` 在改动期间不重启或行为不变。

---

## Scope Boundaries

- 不改 deploy.yml 里 `deploy-mas-go-dev` job（已经在另一个 PR 改完落地）。
- 不改 iCare backend 的 `Dockerfile` / `compose.dev.yaml` / `backend.compose.yaml` 本身——它们对 dev-cypresso 已经足够（worker service 已经定义好）。
- 不改 GHCR pull → 本地 build 模式（已确认 AWS ingress 免费，本地 build 不省钱反而引入风险）。
- 不动 dev-cypresso 上其他项目栈（cypresso-ai、telegram-bot、cypresso-ui 等）。
- 不引入 redis ACL / TLS 等更严的安全机制（拿掉 requirepass 已经是简化方向，加固另议）。
- 不对 dev-cypresso 做磁盘/buildcache 治理（属于另一个 session 的工作）。

### Deferred to Follow-Up Work

- 在 `docs/operations/dev-cypresso.md` 补充上线记录条目（部署结束后单独 commit）。
- 在 `docs/operations/dev-cypresso.md` 同步登记 shared-redis 取消密码的变更（同上）。
- 是否给 dev-cypresso 的 docker build cache 也加一个 systemd timer（参考 mas-go-dev 14:55 那条记录），由独立任务评估。

---

## Key Technical Decisions

- **shared-azurite 加进 `/home/ec2-user/stacks/infra/docker-compose.yml`**（不是新建独立 compose project）。与 shared-postgres / shared-redis / shared-sqlserver 同位，复用 infra/.env 与 shared-services 网络，未来其他项目要用 azurite 也能直接复用。
- **restart 用 `unless-stopped`**，对齐 infra 内现有 shared-* 风格，而非 mas-go-dev 上的 `always`。dev-cypresso 是 EC2 实例，宿主重启时 unless-stopped 容器会被拉起，对"基础设施常驻"的语义足够。
- **shared-redis 拿掉 `--requirepass`**。事前清单：实际消费 redis 的服务只有未来的 iCare worker，telegram-bot / mas-icare-portal / shared-postgres / shared-sqlserver 经过验证不连 redis；redis 端口仅绑 `127.0.0.1`，本身已经只接受本机访问，撤掉密码不显著扩大攻击面。
- **worker 连 redis 用 service name `shared-redis:6379`**（不是 `redis:6379`）。dev-cypresso 上 infra 栈里 redis 的 service name 是 `redis`，但 container_name 是 `shared-redis`，跨 compose project 的 DNS 只能解析 container_name；mas-go-dev 上叫 `redis` 是因为它独立 project 内部 service name = container name = `redis`。
- **env 同 mas-go-dev 手法手动追加**，不走 deploy.yml 自动注入。env 是机密敏感文件、本地维护，CI 不该读写它。
- **deploy.yml 改 `deploy` job 的 SSH 脚本**（不新建独立 job），追加 worker 的 stop/rm/up 和 RestartCount 校验逻辑，与 `deploy-mas-go-dev` 同形。这样 `develop` 分支的 dev-cypresso 部署与 mas-go-dev 部署在脚本结构上对称，未来维护成本低。

---

## High-Level Technical Design

变更触达三个独立位置，呈"基础设施 → env → 部署链路"的分层结构：

```
dev-cypresso (192.168.x.x via SSH alias)
├── /home/ec2-user/stacks/infra/                  [手工运维, 共享基础设施]
│   ├── docker-compose.yml                        [U1: 加 shared-azurite service]
│   └── .env                                      [U2: 删 REDIS_PASSWORD]
├── /home/ec2-user/stacks/icare/                  [GH Actions runner 部署目标]
│   ├── backend.compose.yaml                      [无改动 — 仓库里已定义 worker]
│   ├── .env (符号链接 → .env.docker)              [U3: 追加 worker env 字段]
│   └── .env.bak.20260528-claude-worker-rollout    [备份]
└── docker network shared-services (172.19.0.0/16)
    ├── shared-postgres   [无变化]
    ├── shared-redis      [U2 后重启, --requirepass 移除]
    ├── shared-sqlserver  [无变化]
    ├── mas-icare-portal  [无变化]
    ├── telegram-bot-bot-1 [无变化]
    ├── icare-backend-api-1 [U4 后重建]
    ├── icare-backend-worker-1 [U4 后新增]
    └── shared-azurite    [U1 后新增]

iCare-backend repo
└── .github/workflows/deploy.yml                  [U4: deploy job SSH 脚本加 worker]
```

*以上是变更分布的方向性视图，不是实施规范。具体 yaml 行内容与 deploy.yml diff 在每个实施单元的 Approach 里。*

---

## Implementation Units

### U1. infra/docker-compose.yml 新增 shared-azurite service

**Goal**：在 dev-cypresso 的共享基础设施栈里新增一个 azurite 容器，加入 `shared-services` 网络，供后续 iCare worker（以及未来任何需要 Azure Blob 模拟器的项目）通过 DNS 名 `shared-azurite:10000` 访问。

**Requirements**：R1, R7

**Dependencies**：无（独立基础设施改动）

**Files**：
- `/home/ec2-user/stacks/infra/docker-compose.yml`（远程 ssh 编辑，仓库内无对应文件）
- `/home/ec2-user/stacks/infra/docker-compose.yml.bak.20260528-claude-worker-rollout`（备份）

**Approach**：
- 先 `cp docker-compose.yml docker-compose.yml.bak.20260528-claude-worker-rollout`。
- 在现有 services 段追加一个 `azurite` service：
  - `image: mcr.microsoft.com/azure-storage/azurite:latest`
  - `container_name: shared-azurite`
  - `restart: unless-stopped`
  - `command: ["azurite-blob", "--blobHost", "0.0.0.0", "--blobPort", "10000", "--skipApiVersionCheck"]`
  - `ports: ["127.0.0.1:10000:10000"]`
  - `volumes: ["shared_azurite_data:/data"]`
  - `networks: ["shared-services"]`
- 在文件末尾的 `volumes:` 节追加 `shared_azurite_data:`。
- 用 `docker compose -f docker-compose.yml config` 验证 yaml 解析正确（U2 联动启动）。

**Patterns to follow**：infra 栈里现有 shared-redis service 的结构（container_name 显式命名、ports 仅绑 127.0.0.1、volumes 命名约定 `shared_*_data`）。

**Test scenarios**：
- 静态校验：`docker compose -f docker-compose.yml config` 解析后输出包含 `shared-azurite` 容器、`shared_azurite_data` 卷、`shared-services` 网络成员。
- 备份存在性：`ls /home/ec2-user/stacks/infra/docker-compose.yml.bak.20260528-claude-worker-rollout` 返回 0。

**Verification**：U1 完成的标志是 yaml 含新 service 且 config 校验过；**不立即启动容器**（启动留给 U2 一起做，因为 U2 要重启 shared-redis，顺手把整个 stack `up -d` 一起）。

---

### U2. 移除 shared-redis 的 `--requirepass`，清掉 `infra/.env` 里 REDIS_PASSWORD，启动 shared-azurite

**Goal**：拿掉 shared-redis 的密码，简化 worker 接入逻辑；同时把 U1 新增的 shared-azurite 一起 up 起来。

**Requirements**：R2, R7

**Dependencies**：U1（yaml 必须已经含 shared-azurite，否则 `up -d` 不会拉 azurite 起来）

**Files**：
- `/home/ec2-user/stacks/infra/docker-compose.yml`（U1 已改）
- `/home/ec2-user/stacks/infra/.env`
- `/home/ec2-user/stacks/infra/.env.bak.20260528-claude-worker-rollout`（备份）

**Approach**：
- 备份 `infra/.env`：`cp .env .env.bak.20260528-claude-worker-rollout`。
- 在 docker-compose.yml 里把 redis service 的 `command` 改为去掉 `--requirepass "$REDIS_PASSWORD"`，把 healthcheck 的 `redis-cli -a "$REDIS_PASSWORD" ping` 改为不带 `-a` 的 `redis-cli ping`，environment 里删去 `REDIS_PASSWORD`。
- 删除 `infra/.env` 里的 `REDIS_PASSWORD=...` 那一行。
- `cd /home/ec2-user/stacks/infra && docker compose up -d` —— 此命令会同时：重建 shared-redis（密码改了 yaml 变了，compose 检测到 config-hash 差异自动 recreate）+ 新建 shared-azurite + **不动** shared-postgres / shared-sqlserver（它们 yaml 没变）。
- 不需要 `docker compose down`，避免对其他 shared-* 服务造成不必要的连锁停启。

**Patterns to follow**：mas-go-dev 上 12:47 那次 infra 启动只用 `up -d`、不 `down`，行为对齐。

**Test scenarios**：
- redis 重启后无密码可连：`docker exec shared-redis redis-cli ping` 返回 `PONG`，**且不带 `-a` 参数**。
- 旧密码作废：`docker exec shared-redis redis-cli -a 'oldpass' ping` 应失败或仍返 PONG（redis 在没有 requirepass 时也接受 `-a` 但忽略它），关键是 **不带密码也能 PONG**。
- shared-azurite 起来：`docker ps --filter name=shared-azurite` 显示 `Up`。
- 网络成员：`docker network inspect shared-services` 列表里同时含 `shared-redis`（新 IP）和 `shared-azurite`（新增）。
- 旁观容器未动：`docker inspect shared-postgres --format '{{.State.StartedAt}}'` 与备份前对比，时间未变。
- 卷未丢：`docker volume ls | grep shared_redis_data` 仍存在，数据不丢（appendonly 文件被新容器继续使用）。

**Verification**：5 个 shared-* 容器中 shared-redis 重建、shared-azurite 新增、其余 3 个未动，且 redis 免密 PONG 通过。

---

### U3. 在 `/home/ec2-user/stacks/icare/.env` 追加 worker 所需 13 个 env 字段

**Goal**：把 worker 需要的 queue / redis / azurite / worker 变量写入 icare stack 的 env，让 worker 容器启动时 asynq client 能连上 shared-redis、storage SDK 能连上 shared-azurite。

**Requirements**：R3, R7

**Dependencies**：U2（shared-redis 必须先免密、shared-azurite 必须先 up，否则 worker 启动时连不上）

**Files**：
- `/home/ec2-user/stacks/icare/.env`（注意：`.env.docker` 是符号链接 → `.env`，所有改动落在 `.env`）
- `/home/ec2-user/stacks/icare/.env.bak.20260528-claude-worker-rollout`（备份）

**Approach**：
- 备份：`cp .env .env.bak.20260528-claude-worker-rollout`，保持 `600` 权限。
- 追加 13 个字段到 `.env` 末尾，**沿用 mas-go-dev 12:47 同款命名**，仅以下两处与 mas-go-dev 不同：
  - `REDIS_ADDR=shared-redis:6379`（mas-go-dev 是 `redis:6379`）
  - `AZURE_STORAGE_CONNECTION_STRING=...BlobEndpoint=http://shared-azurite:10000/devstoreaccount1;`（mas-go-dev 是 `http://azurite:10000`）
- 其他 11 个字段照搬 mas-go-dev：`QUEUE_PROVIDER=redis_asynq` / `QUEUE_ENQUEUE_TIMEOUT=5s` / `REDIS_USERNAME=` / `REDIS_PASSWORD=`（空，因为 U2 已经拿掉密码）/ `REDIS_DB=0` / `REDIS_TLS_ENABLED=false` / `WORKER_QUEUES=default:1` / `WORKER_CONCURRENCY=1` / `WORKER_TASK_TIMEOUT=30m` / `WORKER_SHUTDOWN_TIMEOUT=30s` / `WORKER_LOCK_TTL=35m`。
- `chmod 600 .env .env.bak.20260528-claude-worker-rollout` 双保险。

**Patterns to follow**：`docs/operations/mas-go-dev.md` 2026-05-28 12:47 CST 那条的"追加 worker / queue / azurite 相关环境变量"段落，命令与 KEY 列表照搬。

**Test scenarios**：
- 字段新增：`grep -E '^(QUEUE_|REDIS_|AZURE_|WORKER_)' /home/ec2-user/stacks/icare/.env | wc -l` 返回 13。
- 文件权限：`stat -c '%a %U:%G' /home/ec2-user/stacks/icare/.env` 输出 `600 ec2-user:ec2-user`。
- 备份完整：`diff .env.bak.20260528-claude-worker-rollout .env` 输出恰好等于新增的 13 行 + 可能的一行空行分隔。
- compose config 校验：`cd /home/ec2-user/stacks/icare && docker compose -f backend.compose.yaml config` 解析成功，三个 service（api / seed / worker）的 environment 列表都含 `AZURE_STORAGE_CONNECTION_STRING` 与 `REDIS_ADDR=shared-redis:6379`。
- **不重启任何容器**：U3 是纯文件改动，所有 icare-* 容器状态保持。

**Verification**：env 字段补齐且 compose config 校验通过；当前运行的 api 容器不感知新 env（这是预期，要等 U4 滚动重建才生效）。

---

### U4. 改 `deploy.yml` 的 `deploy` job：滚动部署改为 api + worker 联合，加 worker 存活校验

**Goal**：让所有 develop 分支的 PR 部署到 dev-cypresso 时，同时滚动 api 和 worker；与 `deploy-mas-go-dev` job 同形。

**Requirements**：R4, R6

**Dependencies**：U3（worker 启动需要 env，env 必须先就位）

**Files**：
- `iCare/backend/.github/workflows/deploy.yml`（在 iCare 仓库，repo-relative：`.github/workflows/deploy.yml`）

**Approach**：
- 在 `deploy` job 的 `Deploy via SSH` step 里：
  - `docker compose pull api seed` 改为 `docker compose pull api seed worker`。
  - `stop / rm` 由 `api` 改为 `api worker`。
  - `up -d --no-deps api` 改为 `up -d --no-deps api worker`。
  - api healthz 循环里 `exit 0` 改为 `break`，循环外加 `if ! curl ...; then dump api + worker logs; exit 1; fi`。
  - 追加 worker RestartCount 校验：`docker compose ps -q worker` → `docker inspect -f '{{.RestartCount}}'` 取 BEFORE → `sleep 15` → 取 AFTER → 比较 + 比较 `{{.State.Status}}` 是否 `running`；不稳定则 dump worker 日志并 exit 1。
- 完全照搬 mas-go-dev job 的措辞与逻辑（包括中文注释），减少未来认知负担。

**Patterns to follow**：`.github/workflows/deploy.yml` 的 `deploy-mas-go-dev` job `Deploy local backend container` step（commit `01eb485` 之前由本次 plan 作者改过的同形结构）。

**Test scenarios** ——以下都属于 PR 触发后的 GH Actions runner 行为，不是单元测试：
- Covers R4. workflow 静态校验：`yamllint .github/workflows/deploy.yml` 或 GitHub Actions 编辑器侧的 lint 通过。
- Covers R4. 部署成功路径：合并到 develop 后，`deploy` job 跑完，api healthz 200 + worker RestartCount 0；job 整体 success。
- Covers R5. 部署失败路径（手工模拟，不在本计划必跑）：worker env 故意写错 REDIS_ADDR=不存在的主机 → worker 进入崩溃循环 → job 在 15 秒窗口检出 RestartCount 上涨 → dump worker logs → exit 1。
- 与 mas-go-dev job 的措辞一致性：grep `RestartCount`、`--no-deps`、`Verifying worker container is alive` 两个 job 都出现一次。

**Verification**：PR 合并后 GH Actions 的 `deploy` job 通过，且日志里包含"Worker is running stably."这一行。

---

### U5. 落地后健康校验

**Goal**：用与 mas-go-dev 12:47 同款的清单确认 dev-cypresso 上整套链路工作正常。

**Requirements**：R5, R7

**Dependencies**：U1, U2, U3, U4 全部完成（且 deploy.yml PR 合到 develop 触发了一次实际部署）

**Files**：无文件改动，仅 SSH 校验。

**Approach**：
- 列容器：`docker compose -f /home/ec2-user/stacks/icare/backend.compose.yaml ps` 应该看到 api + worker 都 Up，api healthy。
- worker 不在崩溃循环：`docker inspect icare-backend-worker-1 --format '{{.RestartCount}}'` = 0，`{{.State.Status}}` = `running`，`StartedAt` 与本次部署时间一致。
- worker 日志：`docker logs icare-backend-worker-1 | tail -5` 看到 "database connected" + "starting worker" + "Starting processing"，**不出现** "worker stopped"（如出现说明 main 卡死老 bug 复发，但 backend 镜像里已经修复，理论上不会）。
- DNS 解析：从 worker 容器内 `getent hosts shared-redis shared-azurite` 各返回一个 IP。
- TCP 连通：`docker exec icare-backend-worker-1 sh -c 'timeout 2 bash -c "</dev/tcp/shared-redis/6379 && echo OK" && timeout 2 bash -c "</dev/tcp/shared-azurite/10000 && echo OK"'`。
- shared-services 网络成员：`docker network inspect shared-services --format '{{range $k,$v := .Containers}}{{$v.Name}} {{end}}'` 应该看到 `shared-azurite`、`shared-redis`、`icare-backend-worker-1` 都在里面。
- 旁观容器未动：`docker inspect shared-postgres mas-icare-portal telegram-bot-bot-1 --format '{{.Name}} StartedAt={{.State.StartedAt}}'` 与改动前快照对比，时间未变。
- api /healthz 200：`curl -fsS http://127.0.0.1:8080/healthz`。

**Test scenarios** ——这一单元本身就是 test scenarios，不需要额外的"测试代码"。

**Verification**：以上 7 项全部通过即视为整个 plan 落地成功。

---

## Risks & Mitigations

| 风险 | 等级 | 缓解 |
|---|---|---|
| 重启 shared-redis 时 mas-icare-portal / telegram-bot 因连接断开短暂报错 | 低 | 已验证这两个服务实际不连 redis；即便有 transient 连接重连也只是几秒抖动，不需要预约维护窗口 |
| 拿掉 redis 密码后未来误操作风险（如某个 dev 直接 curl/redis-cli 进去清库） | 低-中 | redis 端口仅绑 127.0.0.1，只有 ssh 上机的人能访问；ssh 已经是身份认证边界 |
| `docker compose up -d` 在改动 yaml 后意外重建了别的 service | 低 | compose 通过 config-hash 检测，只重建 hash 变了的容器（即 redis 和 azurite）；postgres / sqlserver / mongodb 等 hash 未变不会动 |
| worker 启动后吃 redis 内存，挤压 shared-redis 的 `maxmemory 480mb` 上限 | 低 | asynq 队列消息体很小（KB 级），480MB 远超 worker 队列实际需求 |
| 仓库内 deploy.yml 改动产生 conflict（另一个 PR 正在改同一文件） | 低 | 上一个 mas-go-dev 改动已合并到 develop，本次 PR rebase 后 conflict 风险小；如冲突手工解 |
| dev-cypresso 磁盘累积新镜像（azurite ~200MB + worker 复用 backend 镜像无新增） | 极低 | deploy.yml 现有 `Cleaning up old icare-backend images` step 兜底；shared-azurite 镜像只占一次 |

---

## System-Wide Impact

- **dev-cypresso 上 shared-redis 行为变化**：所有连 shared-redis 的服务（目前只有未来的 worker）都不再带密码；后续任何项目要接 shared-redis 都按免密配置。
- **dev-cypresso 上 shared-services 网络新成员**：`shared-azurite`。未来其他项目要用 Azure Blob 模拟器，DNS 名 `shared-azurite:10000` 直接可用，无需再起新容器。
- **iCare backend 部署链路**：dev-cypresso 上 `develop` 分支部署从"只滚 api"变成"同时滚 api + worker"，单次部署时长会增加 5-15 秒（worker 容器创建 + RestartCount 校验 sleep 15s）。
- **iCare backend 监控边界**：worker 没有 healthcheck，运维上需要监控 worker 的 RestartCount（dev-cypresso 当前没有任何 docker 容器监控告警，先靠 deploy.yml 部署期校验，长期监控另议）。
- **运维文档**：需要在 `docs/operations/dev-cypresso.md` 追加本次变更条目（计划末尾 deferred work）。
- **iCare 项目代码无变化**：仓库内 `backend.compose.yaml`、`Dockerfile`、worker 二进制都不动；只动 deploy.yml 的 SSH 脚本。

---

## Sources & References

- `docs/operations/mas-go-dev.md`（2026-05-28 12:47 / 14:55 两条记录，本计划的主要参照范本）
- `docs/solutions/dev-cypresso/integration-issues/docker-image-buildup-fills-disk-2026-05-14.md`（dev-cypresso 磁盘累积历史教训，启发 Risks 表里的磁盘条目）
- `docs/operations/dev-cypresso.md`（dev-cypresso 既往运维记录，含 2026-05-19 已停容器列表，确认 telegram-bot-bot-1 是当前唯一活跃的非 iCare 共享容器）
- iCare 仓库 `.github/workflows/deploy.yml`（`deploy` job + `deploy-mas-go-dev` job，本次主要修改对象）
- iCare 仓库 `backend.compose.yaml`（worker service 已定义，本次无需改动）
- dev-cypresso 远程：`/home/ec2-user/stacks/infra/docker-compose.yml`、`/home/ec2-user/stacks/infra/.env`、`/home/ec2-user/stacks/icare/.env`（本次三个主要远程编辑目标）
