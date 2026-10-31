# team-svc 运维操作时间线

## 2026-10-31 13:37 CST - 随 PVE 宿主重启（VM 150）

- 服务器：`team-svc`
- 操作人：`Claude`（用户已确认）
- 原因：PVE 宿主升级内核修复 CVE-2026-98432 后重启（见 `docs/operations/pve.md` 同一时间的条目），VM 跟着宿主一起关机再开机。这台 VM 本身的内核没有变。
- 回滚方式：不涉及这台 VM 的变更。
- 验证：运行中的容器 20 个，和重启前一样，没有 unhealthy；唯一一个没在跑的是 `moo-dev-s3-init-1`，它是 10-31 00:52 就已退出的一次性初始化容器。mac-mini 上的 `team-svc-forwarders` 自动重连，`http://mac-mini:9000/api/system/status` 返回 `UP`。内核仍是 `6.8.0-147`，Ubuntu 的修复还没发布。

## 2026-10-31 09:24 CST - 只读：CVE-2026-98432 内核漏洞暴露面排查

- 服务器：`team-svc`
- 操作人：`Claude`
- 原因：CVE-2026-98432（IPv4 TCP use-after-free，Anthropic 演示了对 MPTCP 监听服务器远程拿 root）公开，需要确认各服务器是否受影响。
- 影响：只读（`uname`、`net.mptcp.enabled`、`ss -Mlnp`、已装内核列表）。没升级、没重启。
- 回滚方式：无服务器变更，无需回滚。
- 结果：Ubuntu 24.04，运行 `6.8.0-147`，受影响；没有 MPTCP 监听。Ubuntu 还没出修复包。
- 汇总与建议：`docs/reviews/2026-10-31-cve-2026-98432-kernel-exposure.md`

## 2026-10-31 01:05 CST - 迁入 moo-dev-infra（含 CDC）与 moo-ocr Kafka

- 服务器：`team-svc`（PVE VM 150，`192.168.2.23`）
- 操作人：`Claude`
- 原因：mac-mini 腾内存，见 `docs/plans/2026-10-31-0010-ops-mac-mini-vms-to-pve-plan.md`
- 做了什么：
  1. mac-mini 上先停 moo-app 的 server / worker（`launchctl bootout user/<hon uid>/ai.cypresso.moo-app.{server,worker}`），再停 debezium-server、kafka-connect、cdc-scanner
  2. `~/moo-dev-infra`（不含 `backups/`）同步到 `/opt/stacks/moo-dev-infra`；`.env` 补上 `COMPOSE_PROJECT_NAME=moo-dev`、`COMPOSE_FILE`、`COMPOSE_PROFILES=debezium-server`，以及 debezium-server 原来从 shell 传入的 `CDC_STATE_JDBC_URL` / `CDC_STATE_PASSWORD`；新增 `docker-compose.team-svc.yml`（postgres / redis / s3 / kafka / kafka-connect 加 `restart: unless-stopped`，Kafka 堆 `-Xmx512m`，Connect 堆 `-Xmx768m`）；在 x86 上重新构建 `moo-dev-postgres`（postgres 17 + PostGIS）
  3. Postgres 先用 `pg_dumpall` 导出导入：`moo_ocr` 的一张 jsonb 表在 plain SQL 导入时报 `invalid input syntax for type json`，`moo_test` 库也没建出来。删掉这两个库，改用 `pg_dump -Fc -C` + `pg_restore -C` 单独重导，之后 9 个库的表数和精确行数全部一致（`moo_fraud_detection` 1483 万行）
  4. Kafka 两个卷（`moo-dev_kafka-data` 843 个文件、`moo-ocr_kafka-secure-data` 411 个文件）和 `moo-dev_s3data-dev`（197 个文件）用 tar 拷贝，文件数一致。`docker system df` 显示的 2.7G / 1.3G 是稀疏的预分配索引文件，实际占用只有 33M / 18M
  5. `/opt/stacks/moo-ocr-kafka`：`compose.yaml` 来自 `~/moo-ocr/deploy/kafka.compose.yaml`，`.env` 设 `COMPOSE_PROJECT_NAME=moo-ocr`，`KAFKA_PASSWORD` 取自原容器
- 验证：
  - 8 个 moo 容器 Up，有健康检查的都是 healthy
  - kafka-connect 的 `icare-claims-v2`、`icare-v4` 连接器和任务都是 RUNNING
  - debezium-server 日志出现 "Skipping change … smaller than the last recorded position"，说明是从原来的 offset 续读，没有重新快照
  - cdc-scanner 输出 `cdc scan started`；moo-dev Kafka 有 31 个 topic
  - mac-mini 上的 moo-app 经 ssh 转发连过来，`http://127.0.0.1:18188/healthz` 和 tailnet `:18188/healthz` 都返回 200
- 回滚方式：停掉这两个 stack；在 mac-mini 上把 colima `moo` 里的容器 `docker update --restart=unless-stopped` 后 `colima start -p moo`，从 forwarder 里去掉 moo 的 6 个端口。这段时间 CDC 写进 team-svc Kafka 的数据不会带回

## 2026-10-31 00:44 CST - 建机并迁入 colima team 的服务

详见 `docs/operations/pve.md`、`docs/operations/mac-mini.md` 同时间条目。
