# mas-go-dev 运维操作时间线

## 2026-05-29 CST - 确认 azurite 运行状态 + 沉淀 iCare 项目使用方式

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：用户询问 azurite 是否启动、在 iCare 项目里应该怎么用。做一次只读核查，并把"怎么用"的接法沉淀下来（上线记录 `2026-05-28 12:47` 只写了部署过程，没写消费方如何接入）。
- 影响：纯只读查询（`docker ps` / `docker inspect` / 读 `.env.docker`），未改动任何容器、配置、网络。
- 当前状态（只读核查结果）：
  - `azurite`：`Up`，只启用 **blob** 服务，启动命令 `azurite-blob --blobHost 0.0.0.0 --blobPort 10000 --skipApiVersionCheck`；queue(10001)/table(10002) 未对外暴露。
  - `redis`：`Up`。
  - 两者端口均只 bind `127.0.0.1`（azurite `10000`、redis `6379`），**VM 外部无法直连**。
  - `azurite` 接在 `shared-services` 网络，DNS 名 / 别名为 `azurite`，容器内 IP `172.18.0.4`，`restart: always`（VM 重启自动拉起）。
  - 同网络消费方容器在跑：`icare-backend-api-1`(healthy)、`icare-backend-worker-1`、`mas-icare-portal`。
- iCare 项目使用方式（沉淀，供后续部署/排查参考）：
  - 服务器上 `icare-backend-api-1` / `icare-backend-worker-1` 已接好，连接配置在 `/opt/mas-go-dev/backend/.env.docker`：
    ```
    AZURE_STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=<azurite默认key>;BlobEndpoint=http://azurite:10000/devstoreaccount1;
    ```
  - `AccountName=devstoreaccount1` + 默认 AccountKey 是 Azurite 内置固定账户（官方公开默认值），非真实凭据。
  - **`BlobEndpoint` 的 host 必须写 `azurite`**（`shared-services` 网络 DNS 名），不能写 `localhost`/`127.0.0.1`——对运行在别的容器里的 api/worker 来说 `localhost` 指向它自己。
  - 消费方容器**必须也加入 `shared-services` 网络**才能解析到 `azurite`（`networks: [shared-services]` + `external: true`），这正是 backend compose 的接法。
  - 在 mas-go-dev VM 上跑新服务：直接复用上述连接串 + 加入 `shared-services` 网络即可。
  - 本机本地开发：**连不到 VM 上的 azurite**（端口只绑 127.0.0.1），标准做法是本地另起一个 azurite 容器（`docker run -p 10000:10000 mcr.microsoft.com/azure-storage/azurite azurite-blob --blobHost 0.0.0.0`），连接串里 `BlobEndpoint` 改为 `http://127.0.0.1:10000/devstoreaccount1`，AccountName/Key 沿用同一套默认值，代码无需改动。
- 回滚：无（只读操作，无变更）。

## 2026-05-28 14:55 CST - 部署 build cache 自动清理 timer + 全清历史 cache

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：本仓库 backend Dockerfile + workflow 修复（合并到 develop 后已跑过多个 PR）已验证 build cache 不再无限累积，但磁盘里仍残留 66.91GB 历史 cache 层（其中大量是被新 build 复用的老 591MB Go 编译层）。决定全清一次彻底回收空间，并安装 systemd timer 兜底，防止未来再出现孤儿层堆积。
- 影响：
  - 安装 `docker-builder-prune.service` + `.timer`（root），每天 UTC 20:00（CST 凌晨 4 点）自动清理 168 小时（7 天）未使用的 buildkit cache 层。RandomizedDelaySec=300 避免与其他 timer 同时启动。
  - `sudo docker builder prune -a -f` 全清 buildkit cache，下次 PR build 需要全量重新下载 Go modules + 编译，预计耗时从 3-5 分钟拉长到 8-15 分钟（一次性），多消耗 500MB-1GB 网络流量。
  - 未触碰镜像、容器、卷；正在运行的 `icare-backend-api-1`(healthy)、`icare-backend-worker-1`、`azurite`、`redis`、`mas-icare-portal` 全部未受影响。
- 回滚：
  - timer：`sudo systemctl disable --now docker-builder-prune.timer && sudo rm /etc/systemd/system/docker-builder-prune.{service,timer} && sudo systemctl daemon-reload && sudo rm /var/log/docker-prune.log`
  - cache：不可逆，但下次 build 会按需重建。
- 变更：
  - 新建 `/etc/systemd/system/docker-builder-prune.service`：`Type=oneshot`，执行 `/usr/bin/docker builder prune --filter until=168h --force`，stdout/stderr 追加到 `/var/log/docker-prune.log`。
  - 新建 `/etc/systemd/system/docker-builder-prune.timer`：`OnCalendar=*-*-* 20:00:00 UTC`，`Persistent=true`（断电期间错过的会补跑），`RandomizedDelaySec=300`。
  - `sudo touch /var/log/docker-prune.log && sudo chmod 644`。
  - `sudo systemctl daemon-reload && sudo systemctl enable --now docker-builder-prune.timer`。
  - `sudo docker builder prune -a -f`，回收 66.92GB。
- 验证：
  - `systemctl list-timers docker-builder-prune.timer` 显示 `NEXT=2026-05-28 20:03:48 UTC`（含随机延迟）。
  - 清理前：`Build Cache 993 条 / 66.91GB`，根分区 `74G/120G (62%)`。
  - 清理后：`Build Cache 0 条 / 0B`，根分区 `5.5G/120G (5%)`，可用 `115GB`。
  - `docker ps`：5 个容器全部 `Up`，`icare-backend-api-1` 保持 `healthy`。
- 后续：
  - 观察下次 PR 部署：build 时长（预期 8-15 分钟）、build 完成后 `docker system df` 的 Build Cache 应该回到 1-2GB 级别。
  - 每天 UTC 20:00 后查看 `/var/log/docker-prune.log` 几次，确认 timer 按预期执行。
  - 长期理想态：Build Cache 稳定在 1-2GB（一份完整复用 cache），timer 偶尔清掉过期残留。如果一周后看到 Build Cache 又涨到几十 GB，说明 cache 复用机制再次失效，需要重新排查。

## 2026-05-28 12:47 CST - 上线 iCare 集成测试基础设施容器（azurite + redis）

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：iCare backend 接入 Redis + Asynq 队列（CYP-699）后需要 worker 容器，worker 依赖 Redis 和 Azure Blob（开发态用 Azurite 模拟）。此前这两个依赖只在本地 `compose.dev.yaml` 中提供；mas-go-dev 集成测试环境缺失，导致 worker 无法部署。
- 影响：
  - 在 mas-go-dev 上新增独立 compose project `icare-backend-infra`，运行两个常驻容器 `azurite` + `redis`，接入既有 `shared-services` 网络（172.18.0.0/16）。
  - 同一网络上原有的 `icare-backend-api-1`、`mas-icare-portal` 容器**未重启、未受影响**；只是网络成员从 2 个增加到 4 个。
  - 服务器 `.env.docker` 追加 13 个 worker / queue / azurite 相关环境变量；现有 KEY 不变。
  - 容器端口仅绑 `127.0.0.1`（azurite 10000、redis 6379），不对外暴露。
- 回滚：
  - 容器：`sudo -u actions-runner docker compose -f /opt/mas-go-dev/infra/infra.compose.yaml down -v`（同时清掉持久化卷；如果只是停容器去掉 `-v`）。
  - `.env.docker`：用备份 `/opt/mas-go-dev/backend/.env.docker.bak.20260528-claude-infra-rollout`（818 字节）覆盖回去即可，保持 600 权限。
- 变更：
  - 新建目录 `/opt/mas-go-dev/infra/`，owner `actions-runner:actions-runner`，mode `750`（与 `backend/`、`frontend-mas/` 对齐）。
  - `scp` 仓库内 `iCare/backend/infra.compose.yaml` → `/opt/mas-go-dev/infra/infra.compose.yaml`（mode `644`）。SHA256 比对一致：`38b2e450bc13669f6276983080b15fc15314637ba71f0608b20b27e79347454d`。
  - `sudo -u actions-runner docker compose -f infra.compose.yaml up -d` 启动：
    - `azurite` (image `mcr.microsoft.com/azure-storage/azurite:latest`)，绑 `127.0.0.1:10000`，挂载卷 `icare-backend-infra_azurite-data`，`restart: always`。
    - `redis` (image `redis:7-alpine`)，绑 `127.0.0.1:6379`，挂载卷 `icare-backend-infra_redis-data`，`restart: always`。
  - `/opt/mas-go-dev/backend/.env.docker` 追加 `QUEUE_PROVIDER=redis_asynq` 等 13 个 KEY（先备份为 `.env.docker.bak.20260528-claude-infra-rollout`，文件从 816B → 1558B），保持 `600` 权限。
- 验证：
  - `docker ps` 显示两个容器 `Up`、`restart=always`。
  - `docker network inspect shared-services` 包含 4 个成员：`mas-icare-portal=172.18.0.2`、`icare-backend-api-1=172.18.0.3`、`azurite=172.18.0.4`、`redis=172.18.0.5`。
  - 从 `icare-backend-api-1` 容器内：
    - `getent hosts redis azurite` → 各自解析到 IP，DNS 名一致。
    - TCP：`</dev/tcp/redis/6379` 成功；`curl http://azurite:10000/` 返回 400（裸 GET 被拒，等价"端点活跃"），`curl 'http://azurite:10000/devstoreaccount1?comp=list'` 返回 403（未鉴权请求被正确拒绝，等价"服务真在跑"）。
  - `docker exec redis redis-cli ping` → `PONG`。
  - `docker compose -f /opt/mas-go-dev/backend/backend.compose.yaml config` 解析成功，三个 service `api / seed / worker` 的 environment 中均含新增的 `AZURE_STORAGE_CONNECTION_STRING` 等。
- 后续：
  - **未触发 PR 流水线**。仓库内待提交：`backend/infra.compose.yaml`（新增）、`backend/.env.docker.example`（分组标注三类环境）、`backend/.github/workflows/deploy.yml`（`Deploy local backend container` step 改为 `stop/rm/up api worker` + `--no-deps` + worker RestartCount 存活校验）。
  - PR 合并后由 runner 自动滚 api + worker 新版本，期间 azurite / redis 不会被动到（不同 compose project，部署链路只动 `icare-backend` 的 service）。
  - `infra.compose.yaml` **不进** runner 自动化；仓库内文件变更后，需手动 scp + `docker compose up -d` 同步到 `/opt/mas-go-dev/infra/`。该约定写入 `AGENTS.md`。

## 2026-05-28 12:41 CST - 清理 docker build cache 救磁盘并修复缓存累积根因

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：另一个 session 排查时发现根分区 `/dev/sda1` 占用 98%（`117G/120G`，可用仅 `3.5G`），`/var/lib/docker` 占 113GB，其中 109.4GB 全是 buildkit 构建缓存。镜像本体只有 309MB，问题完全在 build cache。继续累积下去 runner 会因为磁盘满而 build/deploy 失败。
- 影响：
  - 执行 `docker builder prune --filter until=48h`，删除 947 条 48 小时以上未使用的 buildkit cache 层，释放约 35GB。
  - 未触碰镜像、容器、卷；未重启 docker、runner、容器；未改防火墙、SSH、数据库。
  - 同时在 `iCare/backend` 仓库改了 `Dockerfile` 和 `.github/workflows/deploy.yml`（未提交，由用户走 PR 流程），从根因上让后续 build 不再每次累积 ~591MB 新缓存层。
- 回滚：
  - 已清理的 buildkit cache 不可逆，但都是 48 小时以上未访问的孤儿层，下次 build 会按需重新拉取/编译（首次可能慢一些 + 多消耗一点出网流量，但不会破坏数据）。
  - backend 仓库改动可通过 revert PR 回退到 `docker build` 裸跑方式。
- 变更：
  - mas-go-dev 上：`sudo docker builder prune --filter "until=48h" -f`
    - 清理前：`Build Cache 2105 条 / 109.4GB`，根分区 `117G/120G (98%)`
    - 清理后：`Build Cache 1158 条 / 75.39GB`，根分区 `82G/120G (69%)`
  - `iCare/backend/Dockerfile`：4 个 `go build` 合并到一个 `RUN`，加 `--mount=type=cache,target=/root/.cache/go-build,sharing=locked` 和 `--mount=type=cache,target=/go/pkg/mod,sharing=locked`。BuildKit cache mount 的内容不进 image 层，同一 target 路径只保留一份，不会随每次 build 累积。
  - `iCare/backend/.github/workflows/deploy.yml` 中 `deploy-mas-go-dev` job：把裸 `docker build` 换成 `docker/setup-buildx-action@v3` + `docker/build-push-action@v5`，配合 `/tmp/.buildx-cache-mas-go-dev` 本地 cache + 旋转策略，与 `build-and-push` job (`dev-cypresso-ci` runner) 同一套模式。
- 验证：
  - `df -h /` 显示 `82G/120G (69%)`，可用 39GB。
  - `docker system df` 显示镜像、容器、卷均未受影响：`Images 3/2 309.3MB`、`Containers 3/2`、`Volumes 0`。
  - 正在运行的 `icare-backend-api-1` 仍为 `healthy`，`mas-icare-portal` 仍 `Up`。
- 后续：
  - backend PR 合到 `develop` 触发一次 mas-go-dev 部署后，观察 `sudo docker system df` 的 Build Cache 总量。预期稳定在 1-2GB 级别（一份完整 buildkit cache），而不是每个 PR 多 591MB。
  - 跑 2-3 个 PR 验证 cache 真正稳定后，再考虑在 mas-go-dev 加 cron 作为兜底（`0 4 * * * docker builder prune --filter "until=168h" -f`，每天清 7 天未用的）。现在不加 cron，因为如果根因没修好，cron 只会把"撑爆磁盘"变成"周期性丢缓存 + 重新拉网络流量"，和原本"少用网络"的目标冲突。
  - 当前剩余 75GB build cache 都是 48h 内的层；修复合并后会被新的复用结构逐步替换，不需要额外动作。
