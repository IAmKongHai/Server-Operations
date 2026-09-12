# mas-go-dev

PVE VM `130`，Amazon Linux 2023。Tailscale `100.109.223.53` / MagicDNS `mas-go-dev`，内网 `192.168.2.22`。

`ssh mas-go-dev`（用户 `ec2-user`）。开发测试机，改 Docker / runner 前仍需备份。

当前定位：内网 **SIT 合部署 VM**。iCare MAS Go 继续跑在 `/opt/mas-go-dev/`；其它项目的 SIT 也放到这台机，共用一套 PostgreSQL / Garage / Redis，不再为每个项目单独开 VM。

## 共享 SIT 基础设施

位置：`/opt/shared-sit/`（属主 `ec2-user`，**不要**放进 `/opt/mas-go-dev`，runner 不管这里）。

| 服务 | 容器 | 镜像 | 入口（仅 Tailscale + 回环） | 限额 |
| --- | --- | --- | --- | ---: |
| PostgreSQL 18.6 | `shared-sit-postgres` | `postgres:18-alpine`（digest 钉死） | `100.109.223.53:5432` | 1 GiB / 1 CPU，`max_connections=80` |
| Garage S3 | `shared-sit-s3` | `dxflrs/garage:v2.3.0`（digest 钉死） | `http://100.109.223.53:3900` | 512 MiB / 1 CPU |
| Redis 7 | `shared-sit-redis` | `redis:7-alpine`（digest 钉死，与 iCare 同镜像不同容器） | `100.109.223.53:6380`（容器内仍是 6379） | 256 MiB / 0.5 CPU，`maxmemory 128mb` |

- Docker 网络：`shared-sit`（独立于 iCare 的 `shared-services`）。同机容器用 DNS 名 `postgres` / `garage` / `redis`。
- **不要**把容器名设成 `redis`：iCare 已经占用该名字。本实例容器名 `shared-sit-redis`，只在 `shared-sit` 网上用别名 `redis`。宿主端口用 `6380`，因为 `6379` 是 iCare Redis。
- Redis 开了 `requirepass` + AOF。项目按 DB 号隔离，EVP 用 `/1`。无密码会 `NOAUTH`。
- 未绑 `0.0.0.0`，也未绑 `192.168.2.22`。PVE 局域网直接连这些端口会失败，这是预期。
- 与 mac-mini 上的 `shared-dev-postgres` / `shared-dev-s3` **不是同一套**：那边给笔记本本地调试，这边给 SIT 部署。
- 单节点、无定时备份。回滚：`docker compose stop`，保留 named volume；不要 `down -v`。
- 凭据：服务器上 600 文件；本机副本 [`secrets.local.md`](./secrets.local.md)（gitignore）。

Compose 副本在本仓库 `mas-go-dev/shared-sit/`，以服务器 `/opt/shared-sit/` 为准。

```bash
# 状态
ssh mas-go-dev 'docker compose ls; docker ps --filter name=shared-sit'

# 起停（不影响 iCare）
ssh mas-go-dev 'docker compose -f /opt/shared-sit/postgres/docker-compose.yml --project-directory /opt/shared-sit/postgres up -d'
ssh mas-go-dev 'docker compose -f /opt/shared-sit/s3/docker-compose.yml --project-directory /opt/shared-sit/s3 up -d'
ssh mas-go-dev 'docker compose -f /opt/shared-sit/redis/docker-compose.yml --project-directory /opt/shared-sit/redis up -d'
```

### 新项目怎么接入

1. 单独建数据库和 `LOGIN` 角色：非超级用户、无 `CREATEDB`/`CREATEROLE`，设 `CONNECTION LIMIT`，`REVOKE CONNECT ... FROM PUBLIC`，只把目标库授权给该角色。
2. 单独建 Garage bucket 和 access key，只 `--read --write` 该 bucket，不要给 `--owner` 长期权限。
3. Redis 另选 DB 号（EVP 已用 `1`），连接串带密码；同机用 `redis:6379`，Tailscale 用 `100.109.223.53:6380`。
4. SIT 应用 compose：`external: true` 加入 `shared-sit`，`DATABASE_URL` 用 `postgres://...@postgres:5432/...`。
5. 不要用管理员账号进应用，不要复用 `evp` 库/密钥/Redis DB。
6. 核算 Postgres 总连接数（当前上限 80）。

EVP 已建：库/角色 `evp`（连接上限 40）、bucket `evp`、key 名 `evp-sit`。区域 `ap-southeast-1`，path-style。Redis DB `1`。

CMM 已建：库/角色 `cmm`（连接上限 20）、Redis DB `2`、无 Garage bucket（对象存储用腾讯 COS SIT，不走本机 Garage）。应用目录 `/opt/cmm-sit`（属主 `ec2-user`，mode `750`）。不要复用 `evp` 库/密钥/Redis DB，也不要拷 `cmm-prod` 的 `api.env`。

当前 EVP 后端只认默认 AWS 凭据链，**没有** `S3_ENDPOINT`；SIT 应用先把 `S3_BUCKET` 留空也能启动。要用这套 Garage 需要业务仓补自定义 endpoint / path-style。会话仍在 PostgreSQL，Redis 已就绪但应用尚未接入。

## EVP SIT

位置：`/opt/evp-sit/`（属主 `actions-runner`，供 `shared-sit` runner 部署）。SIT compose 源文件在 `cypressoai/evp` 的 `deploy/sit/`；本仓库 `mas-go-dev/evp-sit/` 仅作对照。`main` 推送走 [Deploy SIT](https://github.com/cypressoai/evp/actions/workflows/deploy-sit.yml)。

| 入口 | 地址 |
| --- | --- |
| 医院端 | http://100.109.223.53:25173/ |
| 管理端 | http://100.109.223.53:25174/ |
| 医院 API（调试） | http://100.109.223.53:28081/ |
| 管理 API（调试） | http://100.109.223.53:28082/ |

账号 `platform.admin` / `hospital.admin`（org `demo-hospital`），密码见 `secrets.local.md`。只走 Tailscale。

```bash
ssh mas-go-dev 'docker compose -f /opt/evp-sit/docker-compose.yml --project-directory /opt/evp-sit ps'
```

回滚：对该目录 `docker compose stop`，不要 `down -v`，也不要 `--remove-orphans`（会扫到别的项目）。

## GitHub Actions runner

同机四套 systemd runner，**不要**混组和混 label。

| 名字 | 组 | 目录 | 用途 |
| --- | --- | --- | --- |
| `mas-go-dev` | `mas-go-dev` | `/opt/actions-runner/mas-go-dev` | iCare 本机部署 |
| `mas-go-dev-ci-1/2` | `mas-go-dev` | `/opt/actions-runner/mas-go-dev-ci-{1,2}` | iCare 质量门禁 |
| `shared-sit` | `shared-sit`（id 6，selected：目前仅 `cypressoai/evp`） | `/opt/actions-runner/shared-sit` | 非 iCare SIT 部署 |

`shared-sit` labels：`self-hosted`, `Linux`, `X64`, `docker`, `al2023`, `shared-sit`。不要贴 `mas-go-dev` / `backend-ci` / `frontend-quality-ci`。EVP Checks 仍走 GitHub-hosted `ubuntu-latest`。

部署 job 应写：

```yaml
runs-on:
  group: shared-sit
  labels: [self-hosted, Linux, X64, shared-sit]
```

服务：`actions.runner.cypressoai.shared-sit.service`（enabled）。用户 `actions-runner`。registration token 注册后已删，不入库。

## iCare 目录（未改）

- `/opt/mas-go-dev/backend/`、`frontend-mas/`、`infra/`（azurite + redis，网络 `shared-services`）
- GitHub org runner `mas-go-dev`，组 `mas-go-dev`，只服务 iCare 仓库

不要对整机 `docker compose --remove-orphans` 或随意 `docker system prune`。
