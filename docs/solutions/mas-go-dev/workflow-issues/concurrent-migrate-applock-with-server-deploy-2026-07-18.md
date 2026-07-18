---
title: Deploy to mas-go-dev 的 migrate 与 Deploy to Server 并发抢 medicalassistance_preprod 应用锁
date: 2026-07-18
last_updated: 2026-07-18
category: docs/solutions/mas-go-dev/workflow-issues
server: mas-go-dev
module: iCare-backend / Backend Deploy (mas-go-dev seed + Server seed)
problem_type: workflow_issue
component: tooling
symptoms:
  - "Backend Deploy 中 Deploy to mas-go-dev 在 Deploy local backend container 失败"
  - "日志 [deploy-seed] running migrate up 后立刻 failed to open database"
  - "mssql: Cannot release the application lock ... Resource: '3979484786' ... sp_releaseapplock @LockOwner = 'Session'"
  - "同一次 run 的 Build and Push / Deploy to Server 可能仍 success"
root_cause: race_condition
resolution_type: configuration_change
severity: medium
tags:
  - github-actions
  - golang-migrate
  - sqlserver
  - applock
  - medicalassistance-preprod
  - mas-go-dev
  - mssql-ref
  - concurrent-deploy
---

# Deploy to mas-go-dev migrate 与 Deploy to Server 并发抢同一库 applock

## 现象

Run 例：
[iCare-backend Backend Deploy #29587500204](https://github.com/cypressoai/iCare-backend/actions/runs/29587500204)
（`feat(CYP-1397)` → `develop`，job `Deploy to mas-go-dev` / `87909063494`）

- 镜像构建成功：`icare/backend:mas-go-dev-099d4908…`
- 失败步骤：`Deploy local backend container` → `docker compose run --rm seed` → `deploy_seed.sh` 里的 `migrate up`
- 关键错误（约 25ms 内）：

```text
[deploy-seed] running migrate up
error: failed to open database,
  "***192.168.2.20:1433?database=medicalassistance_preprod&encrypt=disable":
  mssql: Cannot release the application lock
    (Database Principal: 'public', Resource: '3979484786')
    because it is not currently held.
  in line 0: EXEC sp_releaseapplock @Resource = @p1, @LockOwner = 'Session'
```

- 不是 dirty migration、不是镜像坏、也不是 healthcheck：进程还没到 API 探活。

## 根因

**同一次 workflow 里两个 job 几乎同时对同一 SQL Server 库跑 golang-migrate。**

| 路径 | 连接 | 库 |
|------|------|-----|
| `Deploy to mas-go-dev` seed | `192.168.2.20:1433`（LAN） | `medicalassistance_preprod` |
| `Deploy to Server` seed | `100.124.140.78:1433`（Tailscale） | `medicalassistance_preprod` |

`100.124.140.78` 即 `mssql-ref` 的 Tailscale 地址；与 `192.168.2.20` 是**同一台机、同一实例**。

UTC 时间重叠（run `29587500204`）：

| 时刻 (UTC) | 事件 |
|------------|------|
| 14:27:40.679 | **Deploy to Server** `[deploy-seed] running migrate up` |
| 14:27:42.850 | **Deploy to mas-go-dev** `[deploy-seed] running migrate up` |
| 14:27:42.875 | mas-go-dev `sp_releaseapplock` 失败退出 |
| 14:27:44.320 | Server 侧 migrate 结束 `no change`，继续 seed 并成功 |

golang-migrate（镜像内 `v4.18.1`，`-tags sqlserver`）用 **Session 级** `sp_getapplock` / `sp_releaseapplock` 做互斥。两路并发 Open/Lock 时，第二路会在释放锁阶段报 “not currently held”，表面像 “open database failed”，实际是 **锁竞态**，不是 schema 损坏。

补充时间线：稍早的 run `29587489985`（CYP-1334）在 **14:23:01–14:23:24** 已成功完成 mas-go-dev deploy（镜像 `1a82aa14…`）。失败 run 的 mas-go-dev job 在 14:23:57 才开始，与上一 run **串行**；冲突来自**本 run 内** mas-go-dev 与 Server 两 job 并行，而非两个 develop push 互抢（虽然 push 间隔仅约 9s）。

## 当时库与运行态（排查后，2026-07-18）

- `dbo.schema_migrations`：`version=26`，`dirty=0`（干净）
- 用失败镜像 `099d4908…` 手工 `migrate version` / `migrate up` → `26` / `no change`（可复现已消失）
- mas-go-dev 上 `icare-backend-api-1` 仍跑 **上一成功** 镜像 `mas-go-dev-1a82aa14…`，healthz 正常；**未**滚动到失败 commit 的本地 tag
- Server 侧该 commit 的 deploy 已成功（经 TS 打同一库 migrate/seed）

`mas_ref_owner` 无 `VIEW SERVER PERFORMANCE STATE`，无法用 `sys.dm_tran_locks` / `sys.dm_exec_sessions` 看 applock；不影响结论。

## 处理建议

**短期（运维）**

1. 库状态已干净时，**单独重跑** `Deploy to mas-go-dev`（或整条 Backend Deploy）即可，避免与另一次 Server seed 重叠。
2. 若只想把 mas-go-dev 滚到某 commit：在 runner 空闲、确认无其它 seed/migrate 时再 deploy。
3. 不要在 `dirty=1` 未确认前盲 `force`；本次 `dirty=0`，无需 force。

**中期（应用仓 workflow，推荐）**

在 `iCare-backend` 的 `Backend Deploy` 中任选其一：

1. **串行化 seed/migrate**：`Deploy to mas-go-dev` 与 `Deploy to Server` 对共享 preprod 的 migrate 加 `concurrency` group（例如 `icare-preprod-migrate`），或让其中一个 `needs` 另一个的 seed 完成后再跑。
2. **拆库**：mas-go-dev 与远端 SIT 使用不同 database（仍可同实例），从根本上消除 applock 互抢。
3. **重试**：`deploy_seed.sh` 对 migrate 的 “applock / failed to open database” 做有限次退避重试（seed 已有 `seed_with_retry`，migrate 目前单次失败即 exit）。

## 排查命令备忘

```bash
# 当前本地后端镜像与健康
ssh mas-go-dev 'docker inspect icare-backend-api-1 --format "{{.Config.Image}} {{.State.Health.Status}}"'
curl -fsS http://127.0.0.1:8080/healthz   # 在 mas-go-dev 上

# 迁移版本（在 mas-go-dev，用现有镜像 + .env.docker，勿打印 DSN）
ssh mas-go-dev 'docker run --rm --network host \
  --env-file <(sudo -u actions-runner cat /opt/mas-go-dev/backend/.env.docker) \
  --entrypoint /bin/sh icare/backend:mas-go-dev-<tag> -c "
    DSN=\$(printf \"sqlserver://%s:%s@%s:%s?database=%s&encrypt=%s\" \
      \"\$DB_USER\" \"\$DB_PASSWORD\" \"\$DB_HOST\" \"\$DB_PORT\" \"\$DB_NAME\" \"\${DB_ENCRYPT:-disable}\")
    migrate -path /app/migrations -database \"\$DSN\" version
  "'

# 确认 TS 与 LAN 是否同一 mssql-ref
ssh mssql-ref 'hostname -I; tailscale ip -4'   # 期望含 192.168.2.20 与 100.124.140.78
```

## 相关

- 镜像内 migrate：`github.com/golang-migrate/migrate/v4/cmd/migrate@v4.18.1`（Dockerfile `go install -tags sqlserver`）
- seed 入口：`/app/scripts/deploy_seed.sh`
- 同库两入口：mas-go-dev `.env.docker` → `DB_HOST=192.168.2.20`；SIT Server env → `100.124.140.78`
- 运维时间线：`docs/operations/mas-go-dev.md`、`docs/operations/mssql-ref.md`（2026-07-18 条目）
