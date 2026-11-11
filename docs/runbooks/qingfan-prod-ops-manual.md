# hk-1 服务器运维手册（qingfan / tk-flywheel）

> **归档说明（2026-11-11）**：本手册迁自已废弃的 `DigitalOcean` 仓库（原 `docs/hk-1-服务器运维手册.md`），文中 `hk-1` 即 `qingfan-prod`。配置副本在本仓库 `qingfan-prod/`（按服务器绝对路径镜像）；主机档案见 [`qingfan-prod/README.md`](../../qingfan-prod/README.md)。

> 建立日期：2026-11-10。来源：本仓库 `qingfan-prod/`（服务器上每个配置文件的副本）、迁移计划 `docs/plans/2026-11-10-0226-feat-hk-migration-qingfan-flywheel-plan.md`。
> 本文档不含密码、私钥或连接串；凭据只在服务器 `/etc/qingfan/`、`/etc/tk-flywheel/`、`/root/rds-credentials.env` 和 GitHub Actions Secrets 中。
> 服务器由 Claude 通过 SSH 和 CLI 维护，不装面板；改动服务器后同步 `qingfan-prod/` 与本手册。

---

## 1. 资源

| 资源 | 标识 | 说明 |
|---|---|---|
| 轻量应用服务器（SWAS） | 新阿里云账号，实例 `68c002bd79054bd2bdaffdfef2321cce`，cn-hongkong-d，公网 `8.210.153.241`，内网 `172.21.63.215` | 4 vCPU / 8 GiB / 70 GB，Debian 13.7，系统时区 UTC；本机 aliyun CLI 用 `--profile new-hk`，SWAS 命令带 `--biz-region-id cn-hongkong` |
| 防火墙（SWAS） | 放行 TCP 22/80/443 与 ICMP，来源 0.0.0.0/0 | 22 端口对公网开放，sshd 只允许密钥登录、`MaxAuthTries 3` |
| RDS PostgreSQL 18 | `pgm-j6cd36m59smx6n9g`，`pgm-j6cd36m59smx6n9g.pg.cnhk.rds.aliyuncs.com` → `10.0.0.67:5432` | 经轻量服务器“内网互通”连到 for-qingfan-VPC；强制 SSL；最多 400 连接；白名单分组 `swas_hk` |
| 库 / 账号 | `qingfan`/`qingfan`，`tk_flywheel`/`tk_flywheel`，高权限账号 `qf_admin` | 库属主为同名业务账号，两库都 `REVOKE CONNECT FROM PUBLIC`；两库都设了 `ALTER DATABASE … SET timezone = 'GMT'`（与 DO 托管库一致，见 6.3） |
| 域名（Cloudflare，仅 DNS） | `qingfan.app`、`flywheel.qingfan.app` → `8.210.153.241` | 必须保持灰色云朵：HTTP-01 续期和客户端真实 IP 都依赖直连 |

## 2. 服务

| 服务 | 入口 | 进程 | 发布方式 | 健康检查 |
|---|---|---|---|---|
| qingfan | `https://qingfan.app`（官网、下载、`/admin/`、桌面端 API） | `qingfan@blue` :8090 / `qingfan@green` :8091，`/opt/qingfan/active_slot` 记录在用槽位 | CI → `qingfan-deploy@` 账号 → `sudo /usr/local/bin/qingfan-deploy <版本>`，蓝绿切换 | `/healthz` |
| tk-flywheel | `https://flywheel.qingfan.app` | `tk-flywheel` :8087；`tk-flywheel-tune.timer`（每小时，**默认不启用**，与 DO-1 一致，由管理员决定是否开） | CI → root 的 forced command `/usr/local/sbin/tk-flywheel-deploy`（`deploy <SHA>`），软链切换 | `/healthz` + `/version.txt` |

系统用户：`qingfan`（999/993）、`tk-flywheel`（994/992）、`qingfan-deploy`（1001）。UID 与 DO-1 不同（DO-1 的 995/997 在 Debian 13 上已被 polkitd、systemd-timesync 占用），迁移时 rsync 按用户名映射属主。

qingfan 依赖的本机程序：`ffprobe`（apt `ffmpeg`）、`/usr/local/bin/whisper-cli`（whisper.cpp v1.9.5）、`/usr/local/bin/sherpa-onnx-offline{,-punctuation}`（sherpa-onnx v2.0.1 static）。三个二进制从 DO-1 原样复制；重建机器时按 qingfan 仓库 `deploy/setup-server.sh` 与 `docs/server-providers.md` 安装。模型文件在 `/var/lib/qingfan/server/models/`，随数据目录备份。

## 3. 目录与配置

| 路径 | 内容 | 仓库副本 |
|---|---|---|
| `/etc/qingfan/app.env`（root:qingfan 0640） | 数据库 URL、`QINGFAN_ADMIN_ORIGIN`、采集器/runner 密钥、TTS、OSS | `qingfan-prod/etc/qingfan/app.env.example` |
| `/etc/qingfan/pg.env`、`/etc/tk-flywheel/pg.env`（root 0600） | 备份脚本用的业务账号连接 | `*.example` |
| `/etc/tk-flywheel/admin.env`（root 0600） | `qf_admin` 连接，仅 root 运维用 | `admin.env.example` |
| `/etc/tk-flywheel/app.env`（root:tk-flywheel 0640） | `MODEL_MASTER_KEY` 必须与库里的加密配置配套 | `app.env.example` |
| `/var/lib/qingfan/server/` | `master.key`、`providers.enc`、`downloads/`（安装包）、`models/`、`production/` | 不入库；与数据库一并备份 |
| `/opt/qingfan/{releases,slots,current}`、`/opt/tk-flywheel/{releases,current}` | 发布目录 | — |
| Nginx | `conf.d/00-defaults.conf`（裸 IP/未知 Host 拒绝），`sites-available/qingfan.app.conf`、`flywheel.qingfan.app.conf`，`upstreams/qingfan-upstream.conf`（由发布脚本改写） | 同名文件 |
| 证书 | `/etc/letsencrypt/live/{qingfan.app,flywheel.qingfan.app}/`，webroot `/var/www/{qingfan,tk-flywheel}-acme`，certbot.timer 自动续期，续期后 `renewal-hooks/deploy/reload-nginx` 重载 | 钩子入库 |
| sshd | `sshd_config.d/00-hardening.conf` | 同名文件 |

## 4. 发布与回滚

- **qingfan**：推送版本标签触发 `Release` 工作流。服务器侧 `qingfan-deploy` 先备份数据库，再在备用槽位启动新版本，健康检查通过后切 Nginx upstream，排空旧槽位连接后停掉它。保留最近 5 个版本。
- **qingfan 回滚**：`/usr/local/sbin/qingfan-rollback` 切回另一个槽位所绑定的版本；`qingfan-rollback <版本>` 把指定版本装到备用槽位再切。
- **tk-flywheel**：main 分支 CI 通过后部署，`tk-flywheel-deploy` 解包、备份、`flywheel migrate`、切 `current`、检查 `/version.txt`，失败自动切回上一版本（数据库不回退）。旧版本不会自动清理（每个约 450 MB），定期手工删除，保留当前与上一版本。
- **CI 凭据**：两条部署公钥与 DO-1 上的相同（qingfan 在 `qingfan-deploy` 的 `authorized_keys`，tk-flywheel 在 root 的 `authorized_keys` 且带 `restrict,command=`）。GitHub 上需要的是主机地址与 known_hosts（`DEPLOY_HOST`、`DEPLOY_KNOWN_HOSTS`、`PRODUCTION_KNOWN_HOSTS`）。

## 5. 备份与还原

- `qingfan-backup`、`tk-flywheel-backup`：`pg_dump -Fc` 到 `/var/backups/{qingfan,tk-flywheel}/`，`pg_restore --list` 校验后改名，保留 14 天；cron `/etc/cron.d/hk-1-backups` 每天 03:15、03:20（UTC）各跑一次，发布前另备份一次。
- 还原演练：建临时库，`pg_restore --no-owner --no-privileges` 恢复后删除，不在生产库上试。
- 整机：SWAS 系统盘快照（见第 7 节记录）。

## 6. 从 DigitalOcean 迁移（2026-11）

### 6.1 方法

- 数据库：在 DO-1 上执行 `/usr/local/sbin/hk-migrate-db export <库>`。脚本开一个 `REPEATABLE READ` 事务导出快照，在快照内逐表 `count(*)` 作为基准，`pg_dump -Fc --snapshot` 经临时迁移密钥管道送到 hk-1；hk-1 端（`hk-migrate-recv` → `hk-migrate-db restore`）落盘校验、停服、以业务账号重建 `public` schema 后 `pg_restore --single-transaction`、`analyze`，并回传恢复后的逐表行数，DO-1 端逐行比对。
- 文件：DO-1 上 `rsync -aHAX --delete /var/lib/qingfan/ root@8.210.153.241:/`（经 `rrsync` 限定在 `/var/lib/qingfan`），属主按用户名映射。
- 临时迁移密钥：DO-1 `/root/.ssh/hk-migrate`，hk-1 root `authorized_keys` 中带 `restrict,from="137.184.127.196",command="/usr/local/sbin/hk-migrate-recv"`。切换后删除密钥、`hk-migrate-recv` 和 `/var/lib/hk-migrate/`。

### 6.2 演练记录（2026-11-09 UTC，DO-1 未停服）

| 项 | 结果 |
|---|---|
| tk_flywheel 导库 | 43 张表行数一致，`schema_migrations` 49 行；导出+传输+还原 6 秒（dump 4 MB） |
| qingfan 导库 | 33 张表行数一致（qingfan 没有迁移版本表）；9 秒（dump 33 MB） |
| 对象属主 | 两库所有对象属主为业务账号，业务账号写入后回滚无权限错误 |
| 迁移密钥限制 | 任意命令被拒；rsync 到 `../etc` 被拒、`/etc/` 被映射进 `/var/lib/qingfan`；`restore postgres` 被拒；从其他 IP 使用同一密钥被拒 |
| `/var/lib/qingfan` 预同步 | 12.3 GB / 118 个文件，79 分钟（2.6 MB/s）；随后增量同步 3 秒、`--dry-run -i` 无差异；106 个安装包，抽查 3 个及 `master.key`、`providers.enc` 的 sha256 与 DO-1 一致，全部属主 `qingfan` |
| 停服窗口估算 | 两库导入约 15 秒 + 增量同步数秒 + 启动与冒烟检查，远低于 30 分钟 |
| qingfan 冒烟 | `https://qingfan.app/healthz`、`/admin/`、首页、安装包下载均 200 |
| qingfan 供应商测试（后台“测试”接口，只读） | 模型服务 `tovo.sh`（gpt-6.1-sol）连通、鬼手连通（证明 `master.key` 能解密 `providers.enc`） |
| qingfan 外部依赖 | **Groq 语音转录（当前在用的转录方式）在香港被拒**：DO-1 无密钥请求得 401，香港得 403 Forbidden；**Gemini TTS 在香港被拒**（“User location is not supported”）；阿里云 OSS 杭州可达 |
| tk-flywheel 模型测试 | deepseek-flash ×2 成功（证明 `MODEL_MASTER_KEY` 正确、DeepSeek 在香港可达）；两条模型 ID 填为 “DeepSeek” 的配置返回 HTTP 400（DO 上也从未测试成功）；三条 `sub2api.cypresso.ai` 的 openai 配置返回 HTTP 401（网关拒绝密钥；该网关在 AWS 新加坡，DO 生产上最后一次成功调用是 2026-10-13，待用户确认密钥是否仍有效） |

### 6.3 与 DO-1 不同的地方

- 服务用户 UID/GID 不同（见第 2 节）。
- nginx 1.26：`listen 443 ssl; http2 on;` 代替已弃用的 `listen … http2`；`server_tokens off` 已由 Debian 自带 `nginx.conf` 设置。
- RDS 默认时区为 Asia/Hong_Kong，两库已设为 GMT，与 DO 托管库一致（库中没有 `timestamp without time zone` 列，存储不受影响，但 SQL 里按天截断等逻辑依赖会话时区）。

## 7. DO-1 保留期与后续清理

DO-1 上 qingfan、tk-flywheel 停止并禁用但不删除，DO 托管库中 `qingfan`、`tk_flywheel` 保留，**保留至 2026-11-24**。回滚（R12）：停 hk-1 两个服务；DO-1 上 `systemctl enable --now qingfan@$(cat /opt/qingfan/active_slot) tk-flywheel`；测试人员临时用旧域名。DO 托管库在切换后未被写入，数据停在停服时刻。

2026-11-24 之后清理：DO-1 上 `/opt/qingfan`、`/opt/tk-flywheel`（含 48 个旧版本约 21 GB）、`/var/lib/qingfan`、`/etc/{qingfan,tk-flywheel}`、两套 systemd 单元、Nginx 站点、`qingfan.konghai.me`/`tk.konghai.me` 证书、`/usr/local/sbin/hk-migrate-db`，以及 DO 托管库中的 `qingfan`、`tk_flywheel` 两个库与账号。new-api、sub2api 留在 DO-1，不受影响。

其他待办：`tk-flywheel-deploy` 加保留最近 N 个版本的清理；备份异地副本（例如同步到 OSS）。
