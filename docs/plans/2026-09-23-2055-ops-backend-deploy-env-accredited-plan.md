---
title: 为 Backend Deploy 补 .env.accredited 占位文件（mas-go-dev / dev-cypresso） - Plan
type: ops
date: 2026-09-23
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
server: [mas-go-dev, dev-cypresso]
---

# 为 Backend Deploy 补 .env.accredited 占位文件（mas-go-dev / dev-cypresso） - Plan

## Goal Capsule

- **Objective:** iCare-backend `develop` 的 Backend Deploy 重新全绿，mas-go-dev 与 dev-cypresso 上的 ecom-api / sup-api 重新随每次 push 更新（自 2026-09-14 起一直停在旧版本）。
- **Means:** 在两台部署机的部署目录各放一个不含密钥的 `.env.accredited` 占位文件，只满足 compose 的 env_file 存在性校验，不启动 accredited-api（KTD1、KTD2）。
- **Authority:** 用户当前指示 > `AGENTS.md` 生产服务器操作守则 > 本计划 > 上游 handoff 推导。
- **Stop conditions:** 在服务器上创建文件前、重跑 GitHub Actions 前，都先向用户确认；发现目标目录里已有 `.env.accredited`，或已有 accredited-api 容器（说明有人在并行处理）即停；`compose config` 校验在补文件后仍报错即停，不去改 compose 或 workflow；重跑后 ECOM / SUP readiness 失败即停，按 U3 回滚到 U1 记录的旧镜像，再回到用户。
- **Execution profile:** 手工 SSH，先只读核对再写入；不改任何仓库代码。
- **Tail ownership:** 执行者补完文件、拿到绿色 run 后，追加 `docs/operations/mas-go-dev.md` 与 `docs/operations/dev-cypresso.md` 时间线并提交。

## Product Contract

### Summary

在 `mas-go-dev:/opt/mas-go-dev/backend/` 与 `dev-cypresso:/home/ec2-user/stacks/icare/` 各创建一个 `.env.accredited`，文件只有注释、不含任何变量，说明它仅为占位，并写明在后续工作完成前不得对本机跑 `profile=accredited` 的 Partner API Deploy。权限与同目录 `.env.ecom` 对齐。补完后用 `docker compose config` 在本机先验证，再重跑最近一次失败的 Backend Deploy。accredited-api 真正上线所需的工作单列在 Scope Boundaries，不在本次执行。

### Problem Frame

iCare-backend 的 CYP-2890（commit `72d096c0`，PR #1993，2026-09-14 合入）在 `backend.compose.yaml` 新增 `accredited-api` 服务，归属 `external-api` profile，声明 `env_file: ${ACCREDITED_ENV_FILE:-.env.accredited}`。`scripts/deploy_external_api.sh` 只 up ecom-api / sup-api，但它以 `--profile external-api` 调 compose，compose 加载 project 时会检查该 profile 下全部服务的 env_file，文件不存在就直接失败（exit 14）。

两台部署机都没有这个文件，于是 Backend Deploy 从 CYP-2890 合入起每次都在"部署 ecom-api"这一步失败。api / worker 在此之前已重建成功，所以主后端是新的；ecom-api / sup-api 自 9-14 起没有真正部署过。截至 2026-09-23 最新一次 run（`35862572320`，head `a79dd4a5`）仍失败。

### Key Decisions

- **在服务器上补环境文件，不改 compose。** (session-settled: user-directed — chosen over 在 iCare-backend 把 env_file 改成 `required: false`: 用户选择先在运维侧恢复部署，本次不改应用仓代码。) Governs R1、R2。
- **只求部署恢复，不在这两台机器上启用 accredited-api。** (session-settled: user-directed — chosen over 同时填全配置并用 Partner API Deploy 部署 accredited-api: 真正上线需要新建库账号、密钥与 Redis 规划，范围大得多，用户要求单独记录为后续工作。) Governs R3。

### Requirements

**部署恢复**

- R1. 两台部署机的部署目录各有一个 `.env.accredited`，使 `docker compose --profile external-api -f backend.compose.yaml config` 不再报 env file not found。
- R2. Backend Deploy 的 `Deploy to mas-go-dev` 与 `Deploy to Server` 两个 job 都通过 ecom / sup 健康检查。

**安全与边界**

- R3. 占位文件不含任何密码、JWT secret、连接串，也不从 MAS 的 `.env` / `.env.docker` 复制内容；accredited-api 容器在两台机器上保持不存在。
- R4. 占位文件的属主与权限与同目录 `.env.ecom` 一致，部署用户能读，其他用户不能读。

### Scope Boundaries

- 不改 iCare-backend 的 compose、脚本、workflow。
- 不创建数据库账号、不生成 JWT secret、不动 Redis。
- 不处理生产主机（`SERVER_HOST_PROD`）。见下方 Deferred。

#### Deferred to Follow-Up Work：让 accredited-api 在这两台机器上真正跑起来

执行 U1–U3 后部署恢复，但 accredited-api 仍未部署。以后要真正上线，还需完成下列工作。依据是 iCare-backend `docs/deployment/accredited-api.md` 的 "Independent deployment" 一节、`internal/config/accredited.go` 的 `validateAccreditedProfile`，以及本仓库现有档案。

1. **先定目标与入口。** 确认 SIT 上是否需要这个服务、由谁调用、要不要经 Tailscale 暴露（compose 默认只绑 `127.0.0.1:8084`）。
2. **定主库并建只读账号。** 两台机器的主库来源不同：mas-go-dev 走 mssql-ref 的 preprod catalog（见 `docs/operations/mas-go-dev.md` 2026-08-24 ihc-cut 条目），dev-cypresso 用本机 `shared-sqlserver` 或经 tizi-cyp 跳板访问的 mssql-ref（见 `dev-cypresso/README.md`）。`DB_NAME` 不能照抄 example 里的 `medicalassistance_preprod`，要按主机实际 catalog 填。账号 `accredited_db_reader`（或复用现有账号）只需要对 `dbo.tblproviders`、`dbo.tbllocations`、`dbo.tblspecializations`、`dbo.tbldoctors`、`dbo.tbldoctorschedules`、`dbo.tbldoctorspecialization` 有 SELECT。建账号属于改库，要先征得用户确认并在 `docs/operations/mssql-ref.md` 记录。
3. **定 OAuth 库并建只读账号。** example 写的 `AUTH_DB_NAME=authprovidermasweb`，但 mas-go-dev 上 ecom 实际用的是 `authprovidermasuat_preprod`（2026-08-24 条目），要按主机对齐。`accredited_oauth_reader` 只需要对 `dbo.oauth_clients` 有 SELECT。还要在 `oauth_clients` 里有一个 accredited 专用的测试 client，否则无法做登录验证。
4. **生成独立 JWT secret。** `ACCREDITED_JWT_SECRET` 至少 32 字节，和 MAS / ecom / sup 的密钥都不能相同。明文只放服务器 600 文件和本仓库 gitignore 的 `mas-go-dev/secrets.local.md`、`dev-cypresso/secrets.local.md`。
5. **规划 Redis。** mas-go-dev 可经 `shared-services` 网络用 iCare 的 `redis`，dev-cypresso 有 `shared-redis`。要选一个没被占用的 `REDIS_DB` 号。内网 Redis 不走 TLS，example 里的 `REDIS_TLS_ENABLED=true` 要改成与实际一致。`EXTERNAL_RATE_LIMIT_ENABLED` 必须保持 `true`，否则启动校验不过。
6. **用完整配置替换占位文件。** 以 `.env.accredited.example` 为模板写出完整文件，把第 2–5 步确定的值和按 SIT 填写的 `APP_ENV` 等字段一起写进去，替换掉只有注释的占位文件，同时删去"不得跑 Partner API Deploy"的警示。
7. **部署方式按主机区分。** `Partner API Deploy`（`deploy-sup.yml`，`profile=accredited`、`environment=develop`）只经 SSH 部署到 `SERVER_HOST_DEV`，也就是 dev-cypresso。**这个 workflow 覆盖不到 mas-go-dev**。mas-go-dev 要么在 runner 上手工 `compose build` + `up -d --no-deps accredited-api`，要么在 iCare-backend 给 workflow 增加 mas-go-dev 目标（这是应用仓改动，需要另开 PR）。
8. **上线后验证。** 按文档第 5 步检查：`/healthz` 与 `/api/v1/health` 返回 200；`/swagger/accredited.json` 有 7 个 path；未认证访问 `/ecomm/accredited-providers` 返回 401；MAS / SUP / ECOM 路由返回 404；用测试 client 登录后做一次只读目录查询。
9. **收尾。** 可选跑 `Deploy Restricted API Documentation` 发布文档；在两台机器的运维时间线记录；更新 `mas-go-dev/README.md`、`dev-cypresso/README.md` 的端口 / 服务表（8084）。

#### Deferred to Follow-Up Work：其它

- **生产主机。** `deploy.yml` 与 `deploy-sup.yml` 在 `production` 分支用 `SERVER_HOST_PROD || SERVER_HOST`，部署目录也是 `/home/ec2-user/stacks/icare`。CYP-2890 进入 `main` 后，这台主机会遇到同样的 exit 14。目前未确认它是哪台机器，也不确定 iCare 是否已有生产环境（记忆里 iCare 当前没有生产）。
- **应用仓长期根治。** 在 `backend.compose.yaml` 把 accredited-api 的 env_file 改为 `path` + `required: false`，或把 accredited-api 拆到独立 profile，就不需要每台部署机都放占位文件。前者需要 Compose ≥ 2.24，两台机器的 compose 版本尚未核实。

## Planning Contract

### Key Technical Decisions

- KTD1. **占位文件只写注释，不抄 example 骨架。** compose 只要求 env_file 存在，只有注释的文件就能通过校验（R1）。不抄骨架有两个原因。第一，example 里的 `DB_NAME=medicalassistance_preprod`、`AUTH_DB_NAME=authprovidermasweb`、`REDIS_TLS_ENABLED=true` 对这两台机器都不对（见 Deferred 第 2、3、5 步），照抄会诱导后来的人只补密码就上线。第二，文件一旦存在，`deploy-sup.yml` 在 `profile=accredited` 时唯一的前置检查 `test -f ".env.$profile"` 就会通过，这时再跑会建出一个缺配置、`restart: unless-stopped` 反复崩溃的 accredited-api，违反 R3。注释内容包括三点：本文件仅用于满足 compose 的 env_file 存在性校验；accredited-api 未在本机部署；完成本计划 Deferred 各步之前，不得对本机跑 `profile=accredited` 的 Partner API Deploy。另附 `docs/deployment/accredited-api.md` 作为填写依据。
- KTD2. **属主和权限照抄同目录 `.env.ecom`。** 读取 env_file 的是跑 compose 的那个用户：mas-go-dev 上是 runner 用户，dev-cypresso 上是 `SERVER_USER`。只要文件属主不是这个用户，即使文件存在，部署也会失败。以 `.env.ecom` 为基准，不在计划里预设用户名（R4）。
- KTD3. **先在本机用 `compose config` 复现和验证，再重跑 CI。** 补文件前在部署目录以部署用户执行一次 `--profile external-api -f backend.compose.yaml config -q`，应复现 env file not found；补文件后再执行一次，应通过。这样不需要等 CI 就能证明 R1，重跑 CI 只用来证明 R2。两台机器的 compose 入口不同。dev-cypresso 没有 `docker compose` 插件，要用独立的 `/usr/local/bin/docker-compose`（v2.24.5）；直接用 `docker compose` 会报 "'compose' is not a command"，这个报错不能当成已复现。mas-go-dev 用 `docker compose` 插件，并且必须在 `sudo -u actions-runner sh -c 'cd /opt/mas-go-dev/backend && ...'` 里执行，因为目录属 actions-runner，ec2-user 进不去（见 `docs/operations/mas-go-dev.md` 中与 dev-cypresso 的操作差异）。
- KTD4. **重跑最新失败的 run，不重跑 handoff 里的 `35859529826`。** 重跑旧 run 会部署旧 commit `94416198`。最新失败的是 `35862572320`（`a79dd4a5`），重跑它部署的是当前 develop。执行时再用 `gh run list` 确认一次，以当时最新的失败 run 为准。

### Assumptions

- "compose 只检查文件存在，不校验内容"来自对日志和脚本的推断，没有实测。KTD3 的本机校验会先证明或推翻它。
- dev-cypresso 就是 `SERVER_HOST_DEV`。依据是 `backend.compose.yaml` 头注释指向本仓库 `docs/operations/dev-cypresso.md` 2026-08-10 条目，而且 `docs/plans/2026-05-28-001-feat-dev-cypresso-icare-worker-rollout-plan.md` 把 `/home/ec2-user/stacks/icare/` 记作 dev-cypresso 的部署目录。U1 登录后会再确认。

## Implementation Units

### U1. 只读核对两台部署目录

- **Goal:** 确认目标位置、属主基准和当前失败状态，为 U2 提供依据。
- **Requirements:** R1、R4
- **Dependencies:** 无
- **Files:** 无仓库文件改动
- **Approach:**
  1. 在 mas-go-dev 的 `/opt/mas-go-dev/backend/` 与 dev-cypresso 的 `/home/ec2-user/stacks/icare/` 列出 `.env*`，记录 `.env.ecom` 的属主、组和权限，并确认 `.env.accredited` 不存在。
  2. 确认 `backend.compose.yaml` 已包含 `accredited-api` 服务，说明它已被 CI 同步到位。
  3. `docker ps -a` 确认两台机器都没有 accredited-api 容器。
  4. 记录两台机器上正在运行的 ecom-api / sup-api 容器的镜像 ID 和 tag，作为 U3 的回滚点。mas-go-dev 的 CI 会无条件清理旧的本地镜像 tag，所以只记 tag 不够，必须记镜像 ID。
  5. 以部署用户、用 KTD3 规定的 compose 入口在目录内执行 `config -q`，保存报错原文。
  6. 记录两台机器的 compose 版本，供 Deferred 里的长期根治方案参考。
- **Test scenarios:** Test expectation: none -- 只读核对，不改变状态。
- **Verification:** 两台机器都复现 `env file ... .env.accredited not found`；拿到 `.env.ecom` 的属主和权限，以及 ecom-api / sup-api 当前的镜像 ID。

### U2. 创建占位 `.env.accredited`

- **Goal:** 让两台机器的 compose 都能通过 `external-api` profile 的加载校验。
- **Requirements:** R1、R3、R4；KTD1、KTD2
- **Dependencies:** U1，以及用户对"在服务器上创建文件"的确认
- **Files:** 无仓库文件改动（服务器上新增 `.env.accredited`）
- **Approach:**
  1. 按 KTD1 写一份只有注释的内容，两台机器用同一份。
  2. 以 `.env.ecom` 的属主创建文件，权限与其一致（通常是 600），不经 `/tmp` 中转。
- **Test scenarios:**
  - 以部署用户、用 KTD3 规定的 compose 入口执行 `config -q`，退出码为 0，没有 env file 报错。
  - 去掉注释行和空行后，文件没有任何内容，也就是没有一个 `KEY=` 行。
  - `docker ps -a` 中没有 accredited-api 容器。
- **Verification:** 两台机器上的 `config -q` 都通过，文件属主和权限与 `.env.ecom` 一致。

### U3. 重跑 Backend Deploy 并记录

- **Goal:** 用真实部署证明 R2，并把这次操作写进运维时间线。
- **Requirements:** R2；KTD4
- **Dependencies:** U2，以及用户对重跑 CI 的确认
- **Files:** `docs/operations/mas-go-dev.md`、`docs/operations/dev-cypresso.md`
- **Approach:**
  1. 按 KTD4 选出要重跑的 run，只重跑失败的 job。
  2. 看日志确认两个 job 都通过 `ECOM API readiness...` 和 `SUP API readiness...`。
  3. 在两台机器上确认 ecom-api / sup-api 容器的 `StartedAt` 刷新为本次部署时间，状态 healthy；再次确认 `docker ps -a` 里没有 accredited-api 容器。
  4. 如果任一 job 在 ECOM / SUP readiness 失败，就停下。用 U1 记录的镜像 ID 对 ecom-api / sup-api 做一次 `up -d --no-deps --force-recreate`，镜像要通过对应的 `*_IMAGE` 变量显式传入，因为 compose 默认 tag 在这两台机器上不存在。然后带着失败日志回到用户，因为这说明新代码的启动校验需要 `.env.ecom` / `.env.sup` 补字段。
  5. 两台机器的时间线各写一条，内容包括：时间、原因（CYP-2890 引入的 env_file）、影响（9-14 起 ecom / sup 未更新）、做了什么、回滚方式、验证结果（run 链接与容器状态），以及指向本计划 Deferred 一节的链接。回滚方式要写两层：删掉 `.env.accredited` 后，部署会重新失败在 exit 14；按第 4 步的方法可以把 ecom / sup 恢复到 U1 记录的旧镜像。dev-cypresso 的条目里要明确写上："完成 Deferred 各步前，不得跑 `profile=accredited` 的 Partner API Deploy"。
- **Test scenarios:** Test expectation: none -- 验证就是 CI 结果和容器状态本身。
- **Verification:** 重跑的 run conclusion 为 `success`；两份时间线都已提交。

## Verification Contract

| 检查 | 对应 | 期望 |
|---|---|---|
| 两台机器以部署用户执行 `--profile external-api -f backend.compose.yaml config -q`（dev-cypresso 用 `/usr/local/bin/docker-compose`，mas-go-dev 用 `sudo -u actions-runner` 下的 `docker compose`） | R1 | 补文件前报 env file not found，补文件后退出码为 0 |
| `.env.accredited` 的内容 | R3 | 只有注释，没有任何 `KEY=` 行 |
| 两台机器 `docker ps -a` | R3 | 补文件前、补文件后、CI 跑完后，三次都没有 accredited-api 容器 |
| `stat` 对比 `.env.accredited` 与 `.env.ecom` | R4 | 属主、组、权限一致 |
| 重跑后的 Backend Deploy run | R2 | 两个部署 job 都 success，日志含 ECOM / SUP readiness passed |
| 两台机器的 ecom-api / sup-api 容器 | R2 | healthy，`StartedAt` 在本次 run 之后 |

## Definition of Done

- U1–U3 的 Verification 全部满足。
- 两台机器除了新增的 `.env.accredited`，没有其它文件或容器被手工改动。
- `docs/operations/mas-go-dev.md` 与 `docs/operations/dev-cypresso.md` 已追加时间线并在 `main` 提交。
- 执行过程中如果发现假设不成立（例如 compose 除了存在性还校验内容，或 dev-cypresso 不是 `SERVER_HOST_DEV`），已在时间线中写明，并回到用户确认下一步。

## Sources

- 上游 handoff（机器本地临时文件）：`/tmp/compound-engineering-501/ce-handoff/icare-backend-03e0f7f6/backend-deploy-missing-env-accredited.md`
- iCare-backend `origin/develop`：`.env.accredited.example`、`backend.compose.yaml` 的 `accredited-api` 段、`scripts/deploy_external_api.sh`（以 `--profile external-api` 调 compose）、`.github/workflows/deploy.yml`（`BASE_DIR` 与 `SERVER_HOST_DEV`）、`.github/workflows/deploy-sup.yml`（`profile=accredited` 分支只走 SSH 目标）、`docs/deployment/accredited-api.md`
- 本仓库：`docs/operations/mas-go-dev.md`（2026-08-24 ihc-cut 条目，记录 ecom 的 catalog 与 auth 库名）、`dev-cypresso/README.md`（shared-sqlserver / shared-redis）
