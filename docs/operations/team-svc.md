# team-svc 运维操作时间线

## 2026-10-31 14:40 CST - 装 CI runner（moo-decision / cmm-api / qingfan），moo-app（SIT）迁入，加到 6 vCPU

- 服务器：`team-svc`
- 操作人：`Claude`（用户已确认方案："都按你的方案做，PR 你来开，旧地址保留转发"）
- 原因：mac-mini 要停掉 colima `team`，并迁走 moo-app。需要 Docker 的 CI job 直接放到 team-svc 上跑：Docker 在本机，`-p 127.0.0.1::<port>` 原样可用，不用跨机器连接。计划见 `docs/plans/2026-10-31-0010-ops-mac-mini-vms-to-pve-plan.md`
- 做了什么：
  1. 装软件包和工具：
     - apt 装 `build-essential`（cgo、`-race`）、`unzip`、`poppler-utils`（moo-app worker 生成 PDF 预览要用 `pdftoppm`，缺了 worker 起不来）。
     - Go 1.27.2 装到 `/usr/local/go`，给 `deploy/team-svc/integration-test.sh` 用。runner 的 job 用 `setup-go` 自己下载 Go。
     - caddy v2.11.2 静态二进制装到 `/usr/local/bin/caddy`。
     - 软件包都核对过官方 SHA256 / SHA512。
  2. 新建系统用户 `actions-runner`，加入 `docker` 组，开启 `loginctl enable-linger`。
  3. 注册 3 个仓库级 runner，名称和标签都是 `team-svc`，v2.338.2，以 `actions-runner` 身份用 systemd 托管，工作目录 `/opt/actions-runner/<repo>/_work`：

     | 目录 | 仓库 | systemd 服务 |
     | --- | --- | --- |
     | `/opt/actions-runner/moo-decision` | `cypressoai/moo-decision` | `actions.runner.cypressoai-moo-decision.team-svc` |
     | `/opt/actions-runner/cmm-api` | `caimiamiao/cmm-api` | `actions.runner.caimiamiao-cmm-api.team-svc` |
     | `/opt/actions-runner/qingfan` | `IAmKongHai/qingfan` | `actions.runner.IAmKongHai-qingfan.team-svc` |

  4. 开了三个 PR：
     - `caimiamiao/cmm-api#14`：`verify` 改到 team-svc，用 `services:` 起临时库。
     - `IAmKongHai/qingfan#59`：PostgreSQL 存储测试拆成 team-svc 上的独立 job。
     - `cypressoai/moo-decision#84`：SIT 改到 team-svc，新增 `deploy/team-svc/`。
     - 前两个 PR 的 CI 在新 runner 上全部通过：cmm-api 的 `go test -race` 和 Quality Gate 都过了，Sonar 直连 `127.0.0.1:9000`；qingfan 的临时库只绑 `-p 127.0.0.1::5432`。
  5. vCPU 4 → 6（见 `docs/operations/pve.md` 14:31 条目）。14:31 关机重启，约 1.5 分钟后恢复。重启前确认过所有 runner 都没有在跑的 job。
  6. moo-app（SIT 演示环境）从 mac-mini 迁入：
     - `/opt/moo-app`，属主 `actions-runner`。`data/`（563M、1691 个文件）先预同步，停机后再增量同步一次，两边文件数一致。`tenantdb-phase4-checks/` 也搬了过来。旧 darwin 回滚包（`backups/`、`rollback/`，6.6G）和日志留在 mac-mini。
     - `app.env` 从 mac-mini 复制，权限 600。`/Users/hon/moo-app` 改为 `/opt/moo-app`，`PUBLIC_APP_URL` 改为 `http://team-svc.taila93443.ts.net:18188`。DuckDB 扩展由程序按 linux_amd64 平台自动下载。
     - 进程改为 systemd user unit `moo-app@{server,worker,web}`，已 enable，开机即起。
     - 从 PR 分支触发 Deploy SIT 完成首次部署：14:35 开始，14:39 完成，`release-commit` 为 `2556770`。
     - 加了 `sudo tailscale serve --bg --https=443 http://127.0.0.1:18188`。
  7. 私有 Go 模块 `github.com/cypressoai/moo-ocr/client`：
     - 第一次部署在编译阶段失败。runner 没有 GitHub 凭据，`git ls-remote` 要求输入用户名。mac-mini 上 hon 是借用 `gh auth git-credential` 拉的。
     - 给 `cypressoai/moo-ocr` 加只读 deploy key 时被组织策略拒绝：`Deploy keys are disabled for this repository`。
     - 临时办法：把 `go.mod` 锁定的版本 `v0.0.0-20261013082834-24acd289fd17` 从 hon 的模块缓存拷到 `~actions-runner/go/pkg/mod/cache/download/`。`ziphash` 与 go.sum 一致。
     - `/opt/actions-runner/moo-decision/.env` 加了 `GOPRIVATE=github.com/cypressoai/*`（原文件备份为 `.env.bak.20261031`）。
     - 已经准备好但还没生效：`actions-runner` 的 `~/.ssh/moo-ocr-deploy` 密钥对、ssh 别名 `github-moo-ocr`，以及 git 的 `url.insteadOf` 规则（把 `https://github.com/cypressoai/moo-ocr` 改写为走这个别名）。组织允许 deploy key 后，把公钥加到 moo-ocr 就能用。
  8. `/etc/logrotate.d/moo-app`：`/opt/moo-app/logs/*.log` 超过 100M 时 copytruncate，保留 10 份。mac-mini 上的日志从来没轮转过，已经涨到 2.9G。
- 影响：
  - moo-app 从 14:32 停到 14:40，约 8 分钟。第一次部署因为私有模块失败，又耽误了约 3 分钟。
  - SonarQube、各开发库和 CDC 在 14:31 停了约 1.5 分钟。
- 回滚方式：
  - moo-app：
    1. 停掉三个 unit：`sudo -u actions-runner XDG_RUNTIME_DIR=/run/user/1001 systemctl --user disable --now moo-app@server moo-app@worker moo-app@web`。
    2. 关掉 HTTPS 入口：`sudo tailscale serve --https=443 off`。
    3. 在 mac-mini 上把 `~/moo-app/launchd.disabled-20261031` 改回 `launchd`，逐个 `launchctl bootstrap user/<uid>`。
    4. 把 khmini runner 的 `khmini` 标签加回去。
    5. 先用 rsync 把 `/opt/moo-app/data` 同步回 mac-mini。
  - runner：`sudo ./svc.sh uninstall`，再执行 `./config.sh remove`。
- 验证：
  - `moo-app@{server,worker,web}` 全部 `active` / `enabled`，`127.0.0.1:18180/healthz` 返回 200。Caddy 监听 `127.0.0.1:18188` 和 `100.80.124.63:18188`。
  - 本机经 tailnet 访问：`http://team-svc.taila93443.ts.net:18188/healthz`、`https://team-svc.taila93443.ts.net/healthz`、旧地址 `http://mac-mini.taila93443.ts.net:18188/` 都返回 200。`http://192.168.2.23:18188` 不通，家里内网访问不到，符合预期。
  - worker 重新加入 `moo-icare-{claims,claim-details,members,providers}-v4` 消费组，状态 Stable。日志里除了已修复的 pdftoppm 报错，没有 ERROR / WARN。

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
