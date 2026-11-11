# qingfan-prod

qingfan 项目的**生产服务器**（阿里云香港 ECS），2026-11-10 纳入本仓库。上面跑 `qingfan.app` 主站和 `flywheel.qingfan.app`（tk-flywheel）。按生产对待：重启服务、改 nginx / SSH / 防火墙 / 数据库前必须先征得用户确认。

## 连接

```bash
ssh qingfan-prod   # = ssh root@8.210.153.241，用 ~/.ssh/id_ed25519
```

| 项目 | 值 |
| --- | --- |
| 公网 IP | `8.210.153.241` |
| 云厂商 / 地域 | 阿里云 ECS，`cn-hongkong`，规格 `ecs.e-c1m2.xlarge` |
| 主机名 | `iZj6cfbbt4l6yxdiqkoqnfZ` |
| 系统 | Debian 13 (trixie)，内核 `6.12.116+deb13-amd64` |
| 规格 | 4 vCPU / 7.2G 内存 / 无 swap / 系统盘 69G ext4（`/dev/vda3`，2026-11-10 已用 25%） |
| 时区 | `Etc/UTC`（看日志时注意 +8 换算成 CST） |
| SSH | `sshd_config.d/00-hardening.conf`：`PermitRootLogin prohibit-password`、`PasswordAuthentication no`，只能用密钥登录 |

### root 的 `authorized_keys`

| 注释 | 用途 / 限制 |
| --- | --- |
| `konghai@konghai.me` | 本机 konghai 的 `~/.ssh/id_ed25519` |
| `hon-2026` | 同事 hon 的公钥（2026-11-10 加入，指纹 `SHA256:t5JxvwYZEe9z6KOnXyd08lYm/3rRTIrfzSM8J1k3e+0`），无限制 |
| `tk-flywheel-github-deploy` | `restrict,command="/usr/local/sbin/tk-flywheel-deploy"`：GitHub 部署用，只能上传发布包，拿不到 shell |
| `hk-migrate` | `restrict,from="137.184.127.196",command="/usr/local/sbin/hk-migrate-recv"`：迁移数据用的受限入口 |

改之前的备份：`/root/.ssh/authorized_keys.bak.20261110`。

## 服务

对外只有 nginx（80/443）和 sshd（22）；应用都只听回环，由 nginx 终止 HTTPS 再反代。

| 服务 | systemd unit | 监听 | 运行用户 | 目录 / 配置 |
| --- | --- | --- | --- | --- |
| qingfan 主站 | `qingfan@blue` / `qingfan@green`（蓝绿模板 `qingfan@.service`） | blue `127.0.0.1:8090`，green `127.0.0.1:8091` | `qingfan` | 程序 `/opt/qingfan/slots/<slot>/qingfan-server`，当前槽 `/opt/qingfan/active_slot`（2026-11-10 为 `blue`，版本 `0.1.46`）；工作目录 `/var/lib/qingfan`；配置 `/etc/qingfan/app.env` + `slot-<slot>.env` |
| tk-flywheel | `tk-flywheel` | `127.0.0.1:8087` | `tk-flywheel` | `/opt/tk-flywheel/current` → `releases/<sha>`；配置 `/etc/tk-flywheel/app.env`；部署入口 `/usr/local/sbin/tk-flywheel-deploy`（root 强制命令，带 flock 锁） |
| nginx | `nginx` | `0.0.0.0:80/443` | — | `/etc/nginx/sites-enabled/{qingfan.app,flywheel.qingfan.app}.conf`，`conf.d/00-defaults.conf` |
| certbot | cron `/etc/cron.d/certbot` | — | — | 证书 `/etc/letsencrypt/live/{qingfan.app,flywheel.qingfan.app}` |

其它：`aliyun.service`（云助手）、`chrony`、`exim4`（只听回环）、`sysstat`。`postgresql.service` 显示 active，但本机**没有** PostgreSQL 集群（`pg_lsclusters` 为空，5432 无监听），只装了 `psql` 客户端。

## 数据库

qingfan 用阿里云 RDS PostgreSQL（香港）：`pgm-j6cd36m59smx6n9g.pg.cnhk.rds.aliyuncs.com:5432/qingfan`，连接串在 `/etc/qingfan/app.env` 的 `QINGFAN_DATABASE_URL`（600，不入库）。

`app.env` 里还有 OSS、TTS、collector / runner key 等密钥，只记键名，不要抄值进仓库。

## 注意事项

- 蓝绿切换时只有 `active_slot` 指向的那个槽在跑，另一个槽 unit 不常驻；排查前先 `cat /opt/qingfan/active_slot`。
- 无 swap，内存 7.2G；应用常态只用 ~500M。
- 运维时间线：[`docs/operations/qingfan-prod.md`](../docs/operations/qingfan-prod.md)。
- 配置源码：本目录下 `etc/`、`usr/local/`、`root/` 按服务器绝对路径镜像（迁自已废弃的 `DigitalOcean` 仓库 `hosts/hk-1/`）；详细运维手册 [`docs/runbooks/qingfan-prod-ops-manual.md`](../docs/runbooks/qingfan-prod-ops-manual.md)，迁移计划 [`docs/plans/2026-11-10-0226-feat-hk-migration-qingfan-flywheel-plan.md`](../docs/plans/2026-11-10-0226-feat-hk-migration-qingfan-flywheel-plan.md)。
