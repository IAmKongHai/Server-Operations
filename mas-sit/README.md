# mas-sit

PVE VM `160`，Debian 13（2026-10-31 由 AL2023 的 VM `130` 迁来）。Tailscale `100.109.223.53` / MagicDNS `mas-sit`，内网 `192.168.2.22`。

`ssh mas-sit`（用户 `ec2-user`）。开发测试机，改 Docker / runner 前仍需备份。

## 系统约定（Debian 13，2026-10-31 起）

- 包管理用 `apt`；`unattended-upgrades` 自动装安全更新；`qemu-guest-agent` 已启用。时区保持 **UTC**（与旧机一致，timer 的 `OnCalendar` 按 UTC）。
- 用户 / 组的号与旧机一致，迁移数据都按数字属主拷贝：`ec2-user` 1000:1000、`actions-runner` 993:992、`tk-flywheel-ci` 992:991、`acquilang-ci` 991:990、`docker` 993。Debian 自带的 `clock`、`kvm`、`render`、`systemd-resolve` 组已挪到 987–984。
- DNS：`/etc/resolv.conf` → `/run/systemd/resolve/resolv.conf`，`/etc/systemd/resolved.conf.d/tailscale-magicdns.conf` 把 `~taila93443.ts.net` 交给 `100.100.100.100`。已卸载 `libnss-resolve`，`/etc/nsswitch.conf` 是 `files myhostname dns`：走 nss-resolve 时短名 `mac-mini` 解析不了（resolved 不拿路由域补全单标签名）。
- Docker 29（download.docker.com），`/etc/docker/daemon.json`：`log-driver: local`、关闭 containerd snapshotter、`nofile 32768:65536`。drop-in `docker.service.d/10-after-tailscale.conf` + `/usr/local/sbin/wait-tailscale-ip.sh`：开机时等 `tailscale0` 拿到 `100.109.223.53` 再起 Docker（最多 90 秒），否则绑 TS IP 的容器会 bind 失败。
- cloud-init 只管首次开机：`/etc/cloud/cloud.cfg.d/99-mas-sit-preserve.cfg` 关掉了重建 SSH 主机密钥、改主机名、改 `/etc/hosts`。SSH 主机密钥沿用旧机（ED25519 `SHA256:dBJKYVoD6PHKGWlXR7HqMNoQqeokLC/N9/7nVTRzrAQ`）。
- 宿主工具：AWS CLI v2 在 `/usr/local/bin/aws`（`mas-sit-ci-1` 上的 prod 部署 job 要用）；`sqlcmd`、`btm` 在 `/usr/local/bin`；`build-essential`、`git`、`jq`、`zip`、`dirmngr` 等走 apt。locale 生成了 `en_US.UTF-8`（AcquiLang runner `.env` 用到）。
- Tailscale state 沿用旧机节点（`accept-dns=false`），机器名 `mas-sit`。
- `/etc/gnupg/dirmngr.conf` 写了 `standard-resolver`：dirmngr 自带解析器遇到 quad-100 对公网名回的 SERVFAIL 就放弃，Sonar action 拉 SonarSource 公钥会失败。

当前定位：内网 **SIT 合部署 VM**。iCare MAS Go 继续跑在 `/opt/mas-sit/`；其它项目的 SIT 也放到这台机，共用一套 PostgreSQL / Garage / Redis，不再为每个项目单独开 VM。

## 共享 SIT 基础设施

位置：`/opt/shared-sit/`（属主 `ec2-user`，**不要**放进 `/opt/mas-sit`，runner 不管这里）。

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

Compose 副本在本仓库 `mas-sit/shared-sit/`，以服务器 `/opt/shared-sit/` 为准。

```bash
# 状态
ssh mas-sit 'docker compose ls; docker ps --filter name=shared-sit'

# 起停（不影响 iCare）
ssh mas-sit 'docker compose -f /opt/shared-sit/postgres/docker-compose.yml --project-directory /opt/shared-sit/postgres up -d'
ssh mas-sit 'docker compose -f /opt/shared-sit/s3/docker-compose.yml --project-directory /opt/shared-sit/s3 up -d'
ssh mas-sit 'docker compose -f /opt/shared-sit/redis/docker-compose.yml --project-directory /opt/shared-sit/redis up -d'
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

tk-flywheel CI 已建：常驻库 / 角色 `tk_flywheel_ci`（各限 12 连接），供本机专用 runner 经 `127.0.0.1:5432` 访问。库 owner 为 `postgres`，CI 角色仅获目标库 `CONNECT` / `CREATE` / `TEMPORARY`，不能连接 `cmm` / `evp` / `postgres`。凭据在服务器 `/opt/shared-sit/tk-flywheel-ci/credentials.env`（root，600），GitHub Secret 为 `CI_DATABASE_URL`。详见 [tk-flywheel CI 档案](tk-flywheel-ci/README.md)。

当前 EVP 后端只认默认 AWS 凭据链，**没有** `S3_ENDPOINT`；SIT 应用先把 `S3_BUCKET` 留空也能启动。要用这套 Garage 需要业务仓补自定义 endpoint / path-style。会话仍在 PostgreSQL，Redis 已就绪但应用尚未接入。

## EVP SIT

位置：`/opt/evp-sit/`（属主 `actions-runner`，供 `shared-sit` runner 部署）。SIT compose 源文件在 `cypressoai/evp` 的 `deploy/sit/`；本仓库 `mas-sit/evp-sit/` 仅作对照。`main` 推送走 [Deploy SIT](https://github.com/cypressoai/evp/actions/workflows/deploy-sit.yml)。

| 入口 | 地址 |
| --- | --- |
| 医院端 | http://100.109.223.53:25173/ |
| 管理端 | http://100.109.223.53:25174/ |
| 医院 API（调试） | http://100.109.223.53:28081/ |
| 管理 API（调试） | http://100.109.223.53:28082/ |

账号 `platform.admin` / `hospital.admin`（org `demo-hospital`），密码见 `secrets.local.md`。只走 Tailscale。

## 菜苗苗 SIT

> 2026-10-31 盘点：`/opt/cmm-sit`、容器和 shared-sit 里的 `cmm` 库都已不在本机，仓库里没有下线记录。以下为历史配置。

位置：`/opt/cmm-sit/`（属主 `ec2-user`）。compose 源文件在 `caimiaomiao` 的 `backend-cmm-api/deploy/sit/`；本仓库 `mas-sit/cmm-sit/` 仅作对照。不要用 `cypressoai` runner 组 `shared-sit`。

| 入口 | 地址 |
| --- | --- |
| 公网 API | https://sit-api-cmm.nanyahui.cn |
| 公网管理中台 | https://sit-admin-cmm.nanyahui.cn |
| Tailscale API | http://100.109.223.53:25880/ |
| Tailscale 管理中台 | http://100.109.223.53:25881/ |

员工 Cookie 只挂在 `sit-admin-cmm.nanyahui.cn`（`Secure`、host-only）。Tailscale HTTP 只做 health/smoke，不能证明登录态。seed 管理员 `sit-admin`，密码见 `secrets.local.md`；首次登录必须改密。COS 桶 `cmm-sit-uploads-1469943699`，不是生产 `cmm-prod-uploads`。

```bash
ssh mas-sit 'docker compose --env-file /opt/cmm-sit/.deploy.env -f /opt/cmm-sit/compose.yml --project-directory /opt/cmm-sit ps'
```

回滚：对该目录 `docker compose stop`，不要 `down -v`，也不要 `--remove-orphans`。公网侧把 nyh-prod 两个 vhost 从备份 `/www/backup/nginx-vhost/cmm-sit-20260912-1719/` 拷回后 `nginx -t && nginx -s reload`。

```bash
ssh mas-sit 'docker compose -f /opt/evp-sit/docker-compose.yml --project-directory /opt/evp-sit ps'
```

回滚：对该目录 `docker compose stop`，不要 `down -v`，也不要 `--remove-orphans`（会扫到别的项目）。

## GitHub Actions runner

同机六个 systemd runner，**不要**混组和混 label。

| 名字 | 组 | 目录 | 用途 |
| --- | --- | --- | --- |
| `mas-sit` | `mas-sit` | `/opt/actions-runner/mas-sit` | iCare 本机部署 |
| `mas-sit-ci-1/2` | `mas-sit` | `/opt/actions-runner/mas-sit-ci-{1,2}` | 组内仓库的质量门禁；`ci-1` 带 `docker`，还跑 Telegram-bot / moo-ticket / EVP 的 prod 部署（用宿主 `aws` CLI） |
| `shared-sit` | `shared-sit`（id 6，selected：目前仅 `cypressoai/evp`） | `/opt/actions-runner/shared-sit` | 非 iCare SIT 部署 |
| `mas-sit-kanova-ci-1` | 仓库级：`IAmKongHai/Kanova`（原 AcquiLangAI） | `/opt/acquilang-ci/runner` | AcquiLang 日常检查，label `acquilang-build`，见 [档案](acquilang-ci/README.md) |
| `mas-sit-tk-flywheel-ci-1` | 仓库级：`IAmKongHai/tk-flywheel` | `/opt/tk-flywheel-ci/runner` | tk-flywheel 四个 CI job，专用 label `tk-flywheel-ci` |

GitHub runner ID（2026-10-31 重新注册后）：`mas-sit` 45、`mas-sit-ci-1` 44、`mas-sit-ci-2` 43、`shared-sit` 41；仓库级 `mas-sit-kanova-ci-1` 30（2026-11-01 由 `mas-sit-acquilang-ci-1` 改名）、`mas-sit-tk-flywheel-ci-1` 22。systemd unit 是 `actions.runner.<scope>.<名字>.service`，目录里的 `bin` / `externals` 是相对符号链接（挪目录不会断）。

组 `mas-sit`（id 3）的仓库名单见 `docs/operations/mas-sit.md`；3 组 timer：`docker-builder-prune`、`gha-runner-maintenance`、`gha-runner-maintenance-weekly`。

tk-flywheel runner 使用独立用户 `tk-flywheel-ci`，不在 Docker / sudo 组；最多 2 核 / 3 GiB，工作区与缓存位于 `/opt/tk-flywheel-ci/`。服务和维护方式见 [tk-flywheel CI 档案](tk-flywheel-ci/README.md)。

`shared-sit` labels：`self-hosted`, `Linux`, `X64`, `docker`, `shared-sit`（`al2023` 已于 2026-10-31 迁 Debian 后删除）。不要贴 `mas-sit` / `backend-ci` / `frontend-quality-ci`。EVP Checks 仍走 GitHub-hosted `ubuntu-latest`。

部署 job 应写：

```yaml
runs-on:
  group: shared-sit
  labels: [self-hosted, Linux, X64, shared-sit]
```

服务：`actions.runner.cypressoai.shared-sit.service`（enabled）。用户 `actions-runner`。registration token 注册后已删，不入库。

## iCare 目录

| 目录 | compose 项目 | 端口 |
| --- | --- | --- |
| `/opt/mas-sit/infra/` | `icare-backend-infra`（azurite + redis，网络 `shared-services`） | `:10000`、`:6379` |
| `/opt/mas-sit/backend/` | `icare-backend`（api、worker、gotenberg；profile `external-api` 的 ecom / sup） | api `127.0.0.1:8080`；ecom `:8081`、sup `:8082` |
| `/opt/mas-sit/public-backend/` | `icare-public-backend`（app / hr / map） | `:8090`–`:8092` |
| `/opt/mas-sit/frontend-mas/` | `frontend-mas` | `0.0.0.0:5174` |
| `/opt/mas-sit/public-frontend/` | `public-frontend`（hr / member portal） | `0.0.0.0:5173`、`0.0.0.0:5175` |

除特别注明外，端口都是 `127.0.0.1` + `100.109.223.53` 双绑定。iCare 主库在 `mssql-ref`（`192.168.2.20:1433`），不在本机。镜像 tag 由部署 workflow 传入；ecom / sup 的 Tailscale 端口由 `backend/deploy_external_api.sh` 临时生成 override 追加，手工 `docker compose up` 会丢掉这两个绑定。

## 其它

- `/opt/vps-traffic-monitor/`：compose 项目 `vps-traffic-monitor`（`app/docker-compose.yml`），只绑 `100.109.223.53:18080`，由 `cypressoai/vps-traffic-monitor` 的 `deploy-mas-sit.yml` 部署。

不要对整机 `docker compose --remove-orphans` 或随意 `docker system prune`。
