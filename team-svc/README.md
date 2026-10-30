# team-svc

PVE 上的 Ubuntu VM，2026-10-31 起承接原 mac-mini colima `team` / `moo` 里的全部服务，用来腾出 mac-mini 的内存跑 AI 模型。迁移计划见 [`docs/plans/2026-10-31-0010-ops-mac-mini-vms-to-pve-plan.md`](../docs/plans/2026-10-31-0010-ops-mac-mini-vms-to-pve-plan.md)。

## 连接

```bash
ssh ubuntu@192.168.2.23
```

| 项目 | 值 |
| --- | --- |
| PVE VMID | `150` |
| 规格 | 4 vCPU（`cpu: host`）/ 12G（不 balloon）/ 200G `nvme-data:vm-150-disk-0` |
| 系统 | Ubuntu 24.04 cloud image，cloud-init 用户 `ubuntu` |
| IP | `192.168.2.23/24`（静态，cloud-init 写入）；Tailscale `100.80.124.63`，主机名 `team-svc` |
| 自启 | `onboot: 1`，`startup: order=30,up=60`（在 `mssql-ref` 之后） |
| SSH 公钥 | konghai 本机、mac-mini `hon`（备份脚本和端口转发要用），PVE 上 `/root/team-svc-keys.pub` |

## 系统配置

- Docker CE（`/etc/docker/daemon.json`：`log-driver: local`，单容器日志 20M × 3），`ubuntu` 在 `docker` 组
- Tailscale 用 `--accept-dns=false` 登录，避免覆写 `/etc/resolv.conf`（见 memory：Tailscale 覆写 resolv.conf 导致 runner 全掉线）
- `/etc/sysctl.d/90-sonarqube.conf`：`vm.max_map_count=524288`（SonarQube 内置 ES 必需）
- 时区 Asia/Shanghai；`qemu-guest-agent` 已装

## 服务（`/opt/stacks/<name>`，属主 `ubuntu`）

| stack | 容器 | 端口 | 备注 |
| --- | --- | --- | --- |
| `sonarqube` | sonarqube、sonar-postgres | 9000 | `sonarqube_extensions` 卷带 community-branch-plugin；`sonarqube-web/` 是自定义 web 目录 |
| `richer` | richer-postgres、richer-grafana | 5432、3001 | grafana 的 `DB_HOST` 改为 `richer-postgres`；provisioning 在 `richer/grafana/` |
| `nyh-postgres` | nyh-postgres | 5437 | |
| `acquilang-postgres` | acquilang-postgres | 5433 | 去掉了未使用的旧 TimescaleDB 外部卷声明 |
| `shared-dev-postgres` / `-redis` / `-s3` | shared-dev-* | 5434、6379、3900 | mac-mini 上原来只听回环，这里改为 `0.0.0.0`（家里内网 + tailnet） |
| `sub2api` | sub2api、-postgres、-redis | 18080 | `data/`、`postgres_data/`、`redis_data/` 是 bind mount |
| `moo-dev-infra` | moo-dev postgres / redis / s3 / kafka / kafka-connect / debezium-server / cdc-scanner | 回环 15432、16379、19000、9092、8083 | `.env` 里设了 `COMPOSE_PROJECT_NAME=moo-dev`、`COMPOSE_FILE`（含本地覆盖 `docker-compose.team-svc.yml`：补 restart 策略、Kafka / Connect 堆上限）、`COMPOSE_PROFILES=debezium-server` 和 `CDC_STATE_*` |
| `moo-ocr-kafka` | moo-ocr-kafka | 回环 19094 | `.env`：`COMPOSE_PROJECT_NAME=moo-ocr`、`KAFKA_PASSWORD` |

- 各 stack 的密码都在同目录 `.env`（600），不入库。mac-mini 上原来的 compose 文件留了 `.mac-mini` 副本
- CDC：kafka-connect 的两个连接器和 debezium-server 连 `mssql-ref` 的 tailnet 地址 `100.124.140.78:1433`，所以 **Tailscale 必须在线**，否则 CDC 停摆。同步进度在 Kafka topic 和 Postgres `moo_cdc` 库里，已经随数据迁过来
- Kafka 两个 broker 都 advertise `localhost:<端口>`，只适合本机客户端或经 ssh `-L` 同端口转发的客户端

## 谁在用、怎么连

- mac-mini 上的老地址由 `team-svc-forwarders` 用 ssh 转发过来（见 `AGENTS.md` 的 `mac-mini` 目录约定），客户端可以暂时不改
- 新客户端直接连 `192.168.2.23`（家里内网）或 `100.80.124.63`（tailnet）

## 备份

- SonarQube（03:30）和 AcquiLang（04:00）仍由 mac-mini 的 hon LaunchDaemon 触发，脚本内部用 `DOCKER_HOST=ssh://ubuntu@192.168.2.23` 远程调用这台机器的 Docker，备份文件落在 mac-mini `/Users/hon/backups/`
- 其余库目前没有定时备份（迁移前也没有）

## 迁移记录

- `docs/operations/team-svc.md`
- `docs/operations/mac-mini.md`、`docs/operations/pve.md` 2026-10-31 条目
