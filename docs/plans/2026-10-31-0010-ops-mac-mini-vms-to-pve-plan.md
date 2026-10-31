---
title: mac-mini 的 colima VM 全部迁到 PVE - Plan
type: ops
date: 2026-10-31
execution: manual
server: [mac-mini, pve]
---

# mac-mini 的 colima VM 全部迁到 PVE - Plan

## 目标

mac-mini 要腾出内存跑 AI 模型。把 `hon` 下三个常驻 colima VM（`team` 8G、`moo` 6G、`multica` 3G，合计 17G）里的服务，以及依赖它们的本机进程，全部迁到 PVE 上一台新 VM，最后在 mac-mini 上停掉这三个 VM。vz 虚拟机占用的内存不会归还宿主（见 memory `mac-mini-vm-memory-never-returned`），所以只缩小 VM 规格不够，必须停掉。

用户已确认（2026-10-30 夜）：

- `mas-win` 关机（已完成，见 `docs/operations/pve.md`）。
- `mssql-ref` 压到 10G（已完成，见 `docs/operations/mssql-ref.md`）。
- moo、multica 的本机进程跟着一起搬。
- 夜间团队不用内网服务，可以停机。

## 执行进度（2026-10-31 14:42）

- [x] P0 建 VM：`team-svc` 已建好，Tailscale 已登录（`100.80.124.63`）
- [x] P1 team 服务：已全部迁移，老地址由 ssh 转发保持可用（不用 socat 的原因见 `AGENTS.md`）；两个备份脚本已改为经 ssh 远程调用 VM 的 Docker
- [x] P3 multica：用户确认不再使用，直接卸载（数据库导出留在 `~/backups/multica/`），不迁移
- [x] P4 moo 基础设施：moo-dev-infra（含 CDC，offset 已续上）和 moo-ocr Kafka 已迁移，colima moo 已停
- [x] P4 moo-app 进程：14:40 迁到 team-svc `/opt/moo-app`（systemd user unit），由 team-svc 上的 moo-decision runner 部署（`cypressoai/moo-decision#84`，待合并）；旧地址经 mac-mini 转发保留。私有模块 moo-ocr 暂靠手工放的模块缓存，见 `team-svc/README.md`
- [~] P2 CI Docker：改为把需要 Docker 的 job 直接放到 team-svc 上跑（用户 10-31 决定，替代 K4 的远程 `DOCKER_HOST`）。runner 已注册；`caimiamiao/cmm-api#14`、`IAmKongHai/qingfan#59` 的 CI 已在 team-svc 上跑通，待合并。合并后用 root 停用 `com.cypressoai.colima-team`，再 `colima stop -p team`（其余 runner plist 里残留的 `DOCKER_HOST` 已无人用，可以不改）
- [ ] P5 收尾：colima moo / team 的磁盘 7 天后经确认再删

## 现状

### PVE 容量（2026-10-30 23:55）

| 项 | 值 |
| --- | --- |
| CPU | i5-9600，6 核无超线程 |
| 内存 | 32G；运行中 `110 mssql-ref` 10G、`130 mas-go-dev` 8G；available 约 18.2G |
| 存储 | `nvme-data` 剩约 354G，`local-lvm` 剩约 355G |
| 已停 | `120 mas-win` 6G（`onboot: 0`）、`140 fnos-nas` 2G |

### 要迁的东西

| 来源 | 内容 | 容器实际内存 | 数据卷 |
| --- | --- | --- | --- |
| colima `team` | SonarQube + sonar-postgres、richer-postgres + grafana、nyh-postgres、acquilang-postgres、shared-dev postgres / redis / garage、sub2api（app + postgres + redis）；`cmm-postgres` stack 存在但未运行 | 约 4.0G | 16.8G |
| colima `moo` | moo-dev postgres / redis / seaweedfs / kafka / kafka-connect / debezium-server / cdc-scanner，moo-ocr-kafka | 约 3.3G | 12G |
| colima `multica` | backend、frontend、pgvector postgres | 约 0.3G | 0.1G |
| hon 本机进程 | `~/moo-app`（`server` / `worker` 为 darwin arm64 二进制，caddy 在 tailnet `:18188`，`tailscale serve` 443），由 moo-decision 的 `khmini` runner 部署；`multica daemon --device-name khmini` | 约 0.2G | — |
| hon LaunchDaemon | `com.cypressoai.sonarqube-backup`、`acquilang-backup`、`acquilang-prod-sync`（disabled）、`colima-team` | — | — |

### 依赖 `team` Docker 的 CI

15 个 runner 的 plist 设了 `DOCKER_HOST` 指向 `team`。按 `_diag/Worker_*.log` 统计，真正跑容器的只有：

- `caimiamiao-1`、`mac-mini-qingfan-ci-1..3`：`docker run -d -p 127.0.0.1::5432 postgres:17-alpine`，再用 `127.0.0.1:<port>` 连库。
- `konghai-friends-lab-1`：`docker builder prune` 清理步骤。
- `mac-mini-sonar-1/2/3`：少量 `docker exec` / `docker compose`，需逐个核对。

其余命中是 PR 描述里的文字。

## 关键决定

- **K1. 新建一台 VM，不塞进 `mas-go-dev`。** `mas-go-dev` 是 iCare SIT + runner，混进去会互相拖累。新 VM 暂定 VMID `150`、名称 `team-svc`、`192.168.2.23`，Ubuntu 24.04 cloud image，4 vCPU / 12G / 200G（`nvme-data`），装 Docker CE + Tailscale。
- **K2. 内存账：** 10（mssql-ref）+ 8（mas-go-dev）+ 12（team-svc）= 30G，在 32G 宿主上很紧。缓解：Kafka、SonarQube 的 ES 设显式堆上限；`fnos-nas` 保持关机；如果仍紧张，`mas-go-dev` 8G → 6G（实际只用约 2.3G）。
- **K3. 数据迁移用逻辑导出，不拷数据卷。** 架构从 aarch64 变成 x86_64：Postgres 用 `pg_dumpall` / `pg_dump` 导出再导入；Redis RDB、Grafana sqlite、Kafka 日志目录、SeaweedFS 数据与架构无关，可以直接拷；Garage 先试直接拷 `meta` + `data`，不行就用 S3 同步。本地构建的镜像（`moo-dev-postgres`、`multica-backend:dev`）在 VM 上重新构建。
- **K4. CI Docker 改走远程。** runner 的 `DOCKER_HOST` 改成 `ssh://<user>@team-svc`。docker CLI、compose、build 都能用，但有两点要注意：
  - 端口发布在 VM 上，`127.0.0.1` 访问不到。`caimiamiao`、`qingfan` 的 workflow 要改成绑定 VM 地址、并用该地址连库（各开一个 PR）。
  - bind mount 挂的是 VM 上的路径，不是 runner 工作区；目前统计到的 job 没有用到。
  - 备选方案：在 mac-mini 留一个 2C/2G 的 colima，只给 CI 用（会常驻占约 2G）。
- **K5. 客户端地址。** 过渡期在 mac-mini 上用轻量 TCP 转发（socat 或 launchd + `nc`），保持 `mac-mini:9000/5432/5433/5437/3001/18080` 和 Tailscale `3900/5434/6379` 不变。之后逐个改客户端连到 `team-svc`，最后撤掉转发。
- **K6. moo-app 改为 Linux 部署。** VM 上建 `moo` 用户，`server` / `worker` 编译成 linux/amd64，用 systemd 托管，caddy 绑 VM 的 tailnet IP；moo-decision 的部署 workflow 改成在 VM 上新装的 runner 跑（另一个仓库的 PR）。原来的 `https://<mac-mini>.ts.net` 入口换成 VM 的 ts.net 名称。
- **K7. multica daemon 改在 VM 上跑。** agent 需要的 CLI 和登录态要在 VM 上重新配置。agent 的工作负载会改用 PVE 那 6 核 i5。

## 执行步骤

每个步骤结束都要在 `docs/operations/` 追加记录并提交。mac-mini 上的 colima 磁盘在 P5 之后保留 7 天再删，期间可以随时回滚。

### P0 建 VM（无停机）

1. 下载 Ubuntu 24.04 cloud image，`qm create 150`，cloud-init 配静态 IP `192.168.2.23`，写入 SSH key。
2. 装 Docker CE、Tailscale（加入 tailnet，记下 IP）、`qemu-guest-agent`；`onboot: 1`，启动顺序排在 `mssql-ref` 之后。
3. 验证：`docker run hello-world`；从 mac-mini 能通过 `ssh` 访问 `docker ps`。

### P1 team 服务（停机窗口）

1. 停掉 mac-mini 上的备份 LaunchDaemon，避免迁移途中触发备份。
2. 每个 stack：在 mac-mini 停应用容器 → 导出 / 拷贝数据 → `rsync` compose 和 env 到 `team-svc:/opt/stacks/<name>` → 在 VM 上启动 → 核对行数、库大小、Sonar 项目数。
3. 在 mac-mini 上配好 K5 的转发，从 runner 视角确认 `http://mac-mini:9000/api/system/status` 返回 UP。
4. 备份任务改成 VM 上的 systemd timer（时刻沿用 03:30 / 04:00），备份文件拉回哪里待定（mac-mini 或 NAS）。

### P2 CI Docker

1. 15 个 runner plist 的 `DOCKER_HOST` 改为 `ssh://…`，重启 runner（可能打断正在跑的 job，选空闲时做）。
2. `caimiamiao`、`qingfan` 的 workflow 开 PR：端口绑 VM IP。合并后各触发一次 CI 验证。
3. 核对 `sonar-1/2/3` 那几次 `docker exec` 来自哪个 job，并验证它们能跑通。

### P3 multica

1. `pg_dump` pgvector 库，在 VM 上重建镜像、导入数据、启动 compose。
2. VM 上装 multica CLI 和 agent CLI，登录，`multica daemon` 用 systemd 托管，`--server-url` 指向本机。
3. 停用 mac-mini 的 `multica-colima-supervisor`、`multica-runtime-supervisor`。

### P4 moo

1. 停 moo-app 的 `server` / `worker` / `web` 三个 LaunchAgent。
2. 迁 moo-dev 数据：Postgres 导出导入；Kafka、SeaweedFS、Redis 拷贝数据目录。Debezium 和 kafka-connect 的 offset 与原 Postgres 的复制槽绑定，换库后需要重新建槽、重新快照。
3. moo-app 在 VM 上按 linux/amd64 重新构建，`app.env` 拷过去（600），改 systemd + caddy + `tailscale serve`。
4. moo-decision 部署 workflow 的 PR；在 VM 上注册 runner。
5. 停用 mac-mini 的 `moo-colima-supervisor` 和 `khmini` runner（是否保留它跑别的 job 待定）。

### P5 收尾

1. `colima stop` 三个 profile，并停用 `com.cypressoai.colima-team` 和两个 supervisor。
2. 确认 mac-mini 的内存已经释放（看 `memory_pressure` 和 VM 进程是否消失）。
3. 更新 `AGENTS.md`（`mac-mini` 目录约定、服务器表新增 `team-svc`）和 `mac-mini/README.md`。
4. 7 天后经用户确认再删除 colima 磁盘。

## 回滚

所有步骤都不删 mac-mini 上的数据。要回滚哪个 stack，就在 mac-mini 上重新 `colima start` 对应 profile、撤掉转发、把 `DOCKER_HOST` 改回 unix socket；VM 上的数据视为丢弃。注意：回滚前要确认 VM 上这段时间没有新写入的数据需要带回。
