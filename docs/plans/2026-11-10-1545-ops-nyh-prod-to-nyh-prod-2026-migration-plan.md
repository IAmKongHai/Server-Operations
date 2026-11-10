---
title: nyh-prod 全部服务迁到 nyh-prod-2026 - Plan
type: ops
date: 2026-11-10
server: [nyh-prod, nyh-prod-2026]
artifact_contract: ce-unified-plan/v1
product_contract_source: ce-plan-bootstrap
execution: code
---

# nyh-prod 全部服务迁到 nyh-prod-2026 - Plan

## Goal Capsule

- **Objective:** nyh-prod（ECS `i-j6chyzdlvn2vkqw0jbgv`，`47.239.167.8`）上所有在用的站点、队列 worker、容器、定时任务，今天全部改由 nyh-prod-2026（SWAS `a9670f44600c4671a95c2a46a795657a`，`8.217.145.133`）提供。用户和第三方看到的域名、证书、行为都不变。
- **硬截止：** nyh-prod 是包年包月实例，**到期时间 `2026-11-10T16:00Z` = 2026-11-11 00:00 CST**。到期后实例会停机（数据一般保留 15 天，期间续费可恢复）。切换必须在今晚 23:00 CST 前完成并验证。
- **Means:** 新机先装宝塔，把 `/www` 和必要的 `/etc` 配置整体同步过去。所有 PHP / Python / Go 服务先在新机上起好，但**不跑会写数据的进程**。然后在一个短窗口内：停旧机的 worker、定时任务和容器，做最后一次增量同步，在新机上启动这些进程，再切 DNS。数据库都在 RDS PostgreSQL 上，两台机器共用，所以没有数据库迁移。
- **Authority:** 用户在本次会话中确认的范围 > 本计划 KTD > 单元内细节。`AGENTS.md` 的「生产服务器操作守则」始终有效：停旧机进程、切 DNS、关旧机，都要用户逐次确认。
- **Stop conditions:**
  - U1 结束时新机连不上 RDS（`172.31.138.209:5432`），不进入 U5。
  - U4 里任何一个核心站点（load / center / vip / mp / ddricher / acquilang / bnsg）在新机上用 `--resolve` 测不通，不进入 U5。
  - U5 里新机起 worker 后 10 分钟内出现批量报错（队列失败、RDS 连接失败），立即回滚：新机停 worker，旧机恢复 worker，DNS 改回。
- **Who finishes:** Claude 经 `ssh nyh-prod`、`ssh nyh-prod-2026`、aliyun CLI（`--profile default`）执行服务器侧操作。**DNS（Cloudflare 两个账号 + DNSPod）、阿里云控制台「内网互通」、第三方 IP 白名单、GitHub Secrets 由用户操作**，Claude 给出逐条清单。

---

## Product Contract

### Summary

把一台跑了 3 年、用宝塔管理的 2C/8G ECS（系统盘 79G + 数据盘 147G）上的约 20 个站点、20 个 supervisor 进程、10 个容器和 20 来个定时任务，搬到一台 4C/16G、单盘 80G 的轻量服务器上。两台都是 Debian 13 + 6.12 内核，所以宝塔的 nginx / PHP 编译产物可以直接拷过去用。

### Problem Frame

- 旧 ECS 今晚到期，用户已买了新的轻量服务器替代，不打算续旧机。
- 公网 IP 是 ECS 固定公网 IP，不是 EIP，**带不走**。所以必须切 DNS，并且所有按 IP 白名单的第三方都要加新 IP `8.217.145.133`。
- 所有业务库都在 RDS PostgreSQL `pgm-j6cf5kaej216sx0z`（只有内网地址 `172.31.138.209`，VPC `vpc-j6cy0gudplcfwatq8i43f`）。轻量服务器不在这个 VPC 里，**默认连不上**，实测 `nc` 超时。qingfan-prod 用的是轻量服务器的「内网互通」，这里照做。
- 新盘 80G，比旧机两块盘已用的空间（25G + 48G）小，**不能整盘照搬**，要排除停用站点、旧备份和日志（见 KTD5）。

### Requirements

- R1. 下表「迁移」列为「是」的服务，切换后在新机上正常工作，域名、证书、端口不变。
- R2. 队列 worker 和会写数据的定时任务，任何时刻只在一台机器上运行（两台共用同一个 RDS，双跑会重复下单、重复发短信 / 通知）。
- R3. 本地状态完整带过去：宝塔 Redis（7480）的数据、上传文件、Archery 的 SQLite、guagua uploads、nyh-notify / nyh-wechat-mp 的工作目录、宝塔面板数据（站点、计划任务、证书）。
- R4. 旧机数据盘已在清理前打了手动快照 `s-j6c234k2untx79f5jjiu`；切换前再给系统盘打一个。
- R5. 迁移后在 `nyh-prod-2026/README.md`、`docs/operations/` 里记录；`AGENTS.md` 服务器表更新 nyh-prod 的状态。

### 服务清单（2026-11-10 15:30 CST 只读盘点）

| 类别 | 服务 | 迁移 | 说明 |
| --- | --- | --- | --- |
| 宝塔 PHP 7.4 站点 | `load.nanyahui.com`（+`api.nanyahui.com`）、`load.nanyahui.cn`、`center.nanyahui.com`、`vip.nanyahui.com`、`vip.nanyahui.cn` | 是 | nyhAgent / nyhCenter，核心业务 |
| 宝塔 PHP 8.2 站点 | `konghai.me`、`nyh-2025.konghai.me`、`numbers.konghai.me`（走 Cloudflare 代理）、`127.0.0.1`（richer_web） | 是 | |
| 宝塔静态 / 反代 | `mp.nanyahui.com`、`vip-dev.nanyahui.com`、`zen-design-hualu.konghai.me`、`ddricher.ai`、`gateway.ddricher.ai`、`admin.ddricher.ai`、`admin-al` / `api-al` / `m-al.konghai.me`、`bnsg.konghai.me`、`smith.konghai.me`、`duowei.konghai.me`、`guagua.honc.fun` | 是 | `api.ddricher.ai` 反代 `127.0.0.1:7800`，**旧机上没有进程监听**，照原样带过去，不修 |
| 已停用站点 | `fa.nanyahui.com`、`yysg.nanyahui.com`、`test-agent.nanyahui.cn`（root 已是 `/www/server/stop`） | 只带配置 | 站点目录：fa 带（62M，公众号回滚备用）；yysg（9.5G）、test-agent（7.0G）不带，留在快照里 |
| 无站点的残留目录 | `tiancheng.nanyahui.com`、`sms-admin` 等 | 否 | 用户 11-08 已确认不要 |
| supervisor | 20 个程序：nyhAgent 队列（cashRefund、createOrderJobQueue×5、nyh-sms-worker）、nyhCenter 队列（fareJobQueue、orderPushJobQueue）、`nyh-line-core` 10 个 line-*、`nyh-notify` | 是 | **R2 重点**。`cashTransfer.ini` 是空文件，照原样带 |
| systemd | `guagua-api`（:3400）、`nyh-wechat-mp` + watchdog timer（:9871）、`site_total`（宝塔统计）、`fix-aliyun-dns-vs-tailscale` | 是 | |
| 容器 | `yunshu-api`、`acquilang-backend`、`acquilang-admin`、`richer-{engine,gateway,web}-1`、`richer-web` + `richer-nginx`、`archery`、`shared-redis` | 是 | 镜像用 `docker save` / `load` 带过去，不在新机重新构建 |
| 容器（已停） | `fa-mysql` | 只带数据目录 | 11-08 起停用，保留回滚用 |
| Redis | 宝塔 Redis 8.0.5 `:7480`（db0/5/6/7，共 226 个 key，13.5M，**没有过期时间**）；`shared-redis` `127.0.0.1:6379` | 是 | 7480 被 yunshu（`host.docker.internal`）和 docker 网络 `177.10.0.0/16` 里的容器使用 |
| 定时任务 | 宝塔计划任务 14 个（13 个启用）、root crontab 里的自定义任务（`backup-rds.sh`、`panel-cert-reload.sh`、`docker-panel-letsencrypt-renew.py`、yunshu `healthcheck.sh`、`cmm-sit-healthz.sh`） | 是 | 宝塔任务随面板数据带过去。**R2 重点**：`jobs:monitor`、`cash:cleanup`、`notification?action=timing` 等 |
| 证书 | 宝塔 `vhost/cert` 下 27 套（Let's Encrypt，面板续期）；certbot 只管 `guagua.honc.fun` | 是 | 整目录带过去；DNS 切过来后 HTTP-01 续期才能在新机成功 |
| Tailscale | 节点 `nyh-prod`（`100.78.12.107`），提供 Exit Node（用户手机固定出口 IP） | 是（新节点） | 新机以新节点加入；`do1-relay`（:8080 → `100.86.92.103:8080` sub2api）和 `cmm-sit-healthz` 都依赖 tailnet |
| 安全 | 云盾 Aegis（已在新机装好）、ThreatBook OneAV、fail2ban（sshd / ftpd）、ufw | 部分 | OneAV 默认不迁（见 Open Questions） |
| 其它 | `postfix-mta-sts-resolver`（postfix 本身没装，空跑）、`/etc/cron.d/tk-flywheel-backup`（指向的脚本已不存在，tk-flywheel 已在 qingfan-prod） | 否 | 残留，不带 |
| 外部 RDS | PG `pgm-j6cf5kaej216sx0z`（2027-11 到期）；MySQL `rm-j6cb0v171f2al0h41`（11-08 已到期，本机已无连接） | — | 不迁移，只改白名单 |

### Key Decisions

- KD1. **今天一次性切完，不分批。** 硬截止驱动；按项目分批意味着要跨天维护两台机器，而旧机今晚就停机。
- KD2. **保留宝塔。** 用户日常在宝塔里管站点、证书和计划任务；两台都是 Debian 13 / 6.12，宝塔 13.2.0 的面板数据、nginx 1.30.1、PHP 7.4.33（10-22 在 Debian 13 上自编译）、PHP 8.2.35 都可以原样拷过去用。改成纯 systemd + nginx 是更干净，但今天做不完。
- KD3. ~~建议续费旧 ECS~~ **用户已确认不续费（16:00 CST）**。00:00 以后不能切回旧机，出问题只能在新机上修。旧机的长期存档是数据盘快照 `s-j6c234k2untx79f5jjiu`。

### Success Criteria

- 公网解析全部指向 `8.217.145.133`，每个域名的 HTTPS 首页 / 健康检查返回值和切换前一致。
- 新机 supervisor 20 个程序全部 RUNNING，旧机为 0；宝塔计划任务只在新机启用。
- 切换后 1 小时内：nyhAgent 下单队列有正常消费记录，`nyh-wechat-mp` 收到公众号回调，`/healthz` 正常。

### Scope Boundaries

- 不升级任何组件（PHP、nginx、镜像版本都不变）。
- 不修旧机上本来就坏的东西（`api.ddricher.ai` 后端不在、宝塔 Redis 监听 `0.0.0.0` 等），只记录。
- 不清理业务代码、不动数据库。

#### Deferred to Follow-Up Work

- 宝塔 Redis 只绑回环 + docker 网段；去掉 LLMNR（5355）；整理 ufw。
- center 的 `runtime/log`（8.6G）加日志轮转。
- 旧机快照保留多久、何时删。

---

## Planning Contract

### Key Technical Decisions

- **KTD1. 网络：轻量服务器「内网互通」连 RDS。** 用户在控制台把 nyh-prod-2026 加入 `vpc-j6cy0gudplcfwatq8i43f`（和 qingfan-prod 的做法一样，见 `DigitalOcean/docs/hk-1-服务器运维手册.md`）。然后在 RDS 白名单加一个分组 `swas_nyh2026`，放新机内网 IP `172.21.63.219`。不开 RDS 公网地址。
- **KTD2. 用户和 UID。** 新机的 UID 和旧机冲突：`admin`(1000) 对 `www`(1000)，`systemd-timesync`(997) 对 `shared-redis`(997)，`systemd-resolve`(996) 对 `nyh-wechat-mp`(996)。做法：删掉镜像自带、没在用的 `admin`，`www` 用 1000；其它用户按名字新建，让系统分配 UID。rsync **不加** `--numeric-ids`，按用户名映射属主。`shared-redis` 容器的 `--user 997:987` 要换成新 UID 重建。
- **KTD3. 宝塔先装后覆盖。** 在新机用官方脚本装宝塔面板（只装面板，不装 LNMP），确认版本和旧机一样是 13.2.0（不一样就先升或降到一致）。然后停面板，用旧机的 `/www/server/panel` 覆盖（站点、计划任务、证书、面板 SSL、端口 10463、安全入口都会带过来）。nginx / PHP / Redis 的目录直接从旧机拷，`ldd` 检查缺少的库，用 apt 补。
- **KTD4. 进程分「无状态」和「会写数据」两类。** 无状态的（nginx、php-fpm、guagua-api、nyh-wechat-mp、容器 web 层）在 U4 提前起好，用 `curl --resolve` 测。会写数据的（supervisor 全部、宝塔计划任务、root crontab 里的业务任务、richer-engine 等有定时逻辑的容器）在 U4 保持停止 / 禁用，U5 先在旧机停，再在新机起。nyh-notify 在 supervisor 里，也按会写数据处理。
- **KTD5. 同步范围（约 16G）。** 16:10 已在旧机删掉停用站点、旧备份、旧日志和无引用目录（见 `docs/operations/nyh-prod.md` 同日条目），`/www` 只剩 16G。带：`/www` 全部，只排除 `reserve_space.pl` 和 `/www/backup/archive-20261110`（已下载到本地）。`/etc` 里带：supervisor 配置、`/etc/init.d/{bt,nginx,php-fpm-74,php-fpm-82,redis}`、自定义 systemd unit、`/etc/letsencrypt`、fail2ban jail、root crontab、`/root/.ssh/authorized_keys`（含 GitHub Actions 部署公钥）、`/usr/local/sbin` 下用到的脚本。`/var/lib/docker` 不拷，用到的镜像 `docker save` 后在新机 `docker load`。排除掉的东西都在 R4 的快照里。
- **KTD6. DNS 切换前先降 TTL。** Cloudflare 记录（灰云）现在就改 TTL 为 60s；`numbers.konghai.me` 是橙云，只改源站 IP。`guagua.honc.fun` 在 DNSPod，同样先降 TTL。
- **KTD7. 宝塔 Redis 数据在窗口内拷。** 旧机 `BGSAVE` 后停 Redis，拷 `dump.rdb` 到新机再启动。只有 13.5M，几秒钟。

### Assumptions

- 两边的 `/www/server/php/74` 等编译产物，只依赖 Debian 13 自带的库（U3 用 `ldd` 验证）。
- 第三方接口（VTSI / japitech、FD、xiaola、Gcash、微信公众号等）有一部分按来源 IP 做白名单。哪些有白名单，**需要用户确认**；没确认之前，假设都需要加新 IP。
- GitHub Actions 部署（ddricher、acquilangai、yunshu-bnsg、nyh 部署 key）在 Secrets 里写了 `47.239.167.8` 或旧主机公钥，切换后要改。

### Risks & Dependencies

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| 第三方 IP 白名单没加新 IP | 下单 / 查单 / 公众号 API 失败，用户看到的是业务报错 | U1 列清单让用户提前加；U5 起 worker 后先看 line-* 的日志 |
| 双跑 worker / cron | 重复下单、重复退款、重复发短信 | KTD4；U5 严格先停旧再起新，每一步都 `supervisorctl status` 两边对照 |
| DNS 缓存 | 切换后一段时间仍有请求到旧机 | 提前降 TTL；旧机 nginx 在窗口后继续运行到 23:30，只停写数据的进程。旧机上的 PHP 站点仍连同一个 RDS，短时间内兼容 |
| 磁盘不够 | 同步中断 | KTD5 排除清单；U2 先算总量再同步 |
| 00:00 前没切完 | 旧机停机，业务中断 | KD3 建议续费；不续费则 22:30 为 go / no-go 时间点：没切完就把剩下的项目在新机上直接起，不再回旧机 |
| 宝塔面板版本 / 绑定 | 面板打不开或要重新登录宝塔账号 | 面板打不开不影响 nginx / PHP 运行，可以之后再修 |

### Sources

- 只读盘点：本会话 2026-11-10 15:20–15:45 CST 在 nyh-prod 上的查询结果（站点表、vhost、supervisor、crontab、容器、端口、RDS 连接）。
- `docs/operations/nyh-prod.md`（11-07/08 的 nyh-wechat-mp、shared-redis、fa 下线记录）、`nyh-prod/README.md`。
- 阿里云：ECS `DescribeInstances`（到期时间、VPC），RDS `DescribeDBInstanceNetInfo` / `DescribeDBInstanceIPArrayList`。
- `DigitalOcean/docs/hk-1-服务器运维手册.md`（轻量服务器内网互通连 RDS）。

---

## Implementation Units

### U1. 用户侧准备（现在开始，并行进行）

需要用户做，Claude 提供逐项清单并在完成后验证：

1. **决定是否续费旧 ECS**（KD3）。
2. **控制台「内网互通」**：轻量服务器 → nyh-prod-2026 → 内网互通 → 关联 `vpc-j6cy0gudplcfwatq8i43f`。完成后 Claude 加 RDS 白名单分组，并在新机 `nc -zv 172.31.138.209 5432` 验证。
3. **降 TTL**：Cloudflare 两个账号（`konghai.me` / `ddricher.ai` 等在 `aiden`，`nanyahui.com` / `nanyahui.cn` 部分在 `kehlani`，以实际所在账号为准）和 DNSPod（`honc.fun`）里，上面清单里的所有 A 记录 TTL 改 60s。
4. **第三方 IP 白名单加 `8.217.145.133`**（先加不删旧的）：微信公众号「IP 白名单」、各充值 / 支付上游。由用户列出实际有白名单的接口。
5. **Tailscale**：准备一个 auth key，或者在 U3 时用登录链接授权新节点；切换后在 admin 里批准 Exit Node。

验证：内网互通生效后 RDS 端口能通。

### U2. 旧机快照与同步量核算

- aliyun CLI 给旧机系统盘、数据盘各打一个手动快照 `nyh-prod-final-20261110`，等到 accomplished。
- 用 KTD5 的排除规则 `rsync --dry-run --stats` 算出要传的总量，确认小于新机可用空间（约 72G）减去 10G 余量。
- `docker save` 正在用的镜像（`yunshu-api`、`acquilang-backend`、`acquilang-admin`、`richer-*:latest`、`richer_web-richer-nginx`、`ghcr.io/.../archery`、`redis:7.4.12`、`mysql:8.0.36`）到 `/www/backup/migrate-images/`。

### U3. 新机底座

- 删除 `admin` 用户；建 `www`(1000)、`redis`、`nyh-notify`、`nyh-wechat-mp`、`shared-redis`（KTD2）。
- apt：`supervisor`、`fail2ban`、`rsync`、`sqlite3`、`python3`、宝塔依赖；Docker CE（阿里云镜像源 `mirrors.cloud.aliyuncs.com/docker-ce`，trixie）；Tailscale（官方源）。
- 宝塔面板安装（KTD3），先不覆盖数据。
- Tailscale 加入 tailnet，主机名 `nyh-prod-2026`，`--advertise-exit-node`。
- 轻量服务器防火墙：放行 22、80、443/tcp、443/udp（HTTP/3）、10463（宝塔面板）、8080（do1-relay，见 Open Questions）、41641/udp。7480、888、20/21、39000-40000 **不放行**。
- 验证：`docker run --rm hello-world`、`tailscale status`、`supervisorctl version`。

### U4. 预同步并起无状态服务

- 第一次 `rsync -aHAX`（按 KTD5 范围，旧机推到新机，走公网 SSH）。`/etc` 文件按清单逐个拷。
- `ldd` 检查 `/www/server/{nginx/sbin/nginx,php/74/sbin/php-fpm,php/82/sbin/php-fpm,redis/src/redis-server}`，补库。
- 覆盖宝塔面板数据，启动面板，确认能登录、站点列表和计划任务都在。**立刻在面板里把所有计划任务设为停用**（或从 root crontab 注释掉宝塔写入的行），root crontab 里的业务任务也先注释掉。
- 起 nginx、php-fpm-74/82、宝塔 Redis（此时用的是预同步的旧数据，U5 会覆盖）、`guagua-api`、`nyh-wechat-mp`、`site_total`。supervisor 装好但**所有程序 `autostart=false` 或整体不启动**。
- `docker load` 镜像；按各自 compose 目录 `docker compose up -d` 起 `acquilang-*`、`richer-*`、`yunshu-api`、`archery`、`shared-redis`（新 UID 重建）。`richer-engine` 若有定时任务，先不起（启动前看它的 compose / 代码确认）。
- 验证：在新机上逐个域名 `curl -sk --resolve <域名>:443:127.0.0.1 https://<域名>/`，状态码和旧机一致（先在旧机上记一份基准）；RDS 能连；`yunshu`、`acquilang` 健康检查通过。

### U5. 切换窗口（建议 21:00–22:00 CST，需用户确认开始）

按顺序执行，每一步两边对照：

1. 旧机：宝塔计划任务全部停用；root crontab 业务任务注释掉。
2. 旧机：`supervisorctl stop all`（先确认队列积压为 0 或可接受）。停 `richer-engine` 等有定时逻辑的容器、`yunshu-api`、`acquilang-backend`、`guagua-api`、`nyh-wechat-mp`。nginx 和 php-fpm **继续运行**，接住 DNS 缓存带来的请求。
3. 旧机宝塔 Redis `BGSAVE` → 停 → 拷 `dump.rdb` 到新机 → 新机重启 Redis（KTD7）。
4. 最后一次增量 rsync（上传目录、Archery `data/`、guagua `uploads/`、acquilang `uploads/` `static/`、nyh-notify / nyh-wechat-mp 工作目录、`runtime/session`）。
5. 新机：起 supervisor 全部程序、恢复计划任务和 crontab、起剩下的容器和服务。
6. 用户改 DNS：全部 A 记录改 `8.217.145.133`（`numbers.konghai.me` 改源站）。
7. 验证（见 Verification Contract）。10 分钟内出现批量报错就回滚。

回滚：新机 `supervisorctl stop all`、停计划任务；旧机恢复第 1、2 步停掉的东西；DNS 改回 `47.239.167.8`。前提是旧机还没到期（KD3）。

### U6. 切换后收尾

- 观察访问日志：旧机 nginx 访问量降到接近 0 后（预计 30 分钟内），停旧机 nginx / php-fpm。
- 新机触发一次证书续期测试（宝塔「续签 Let's Encrypt」任务手动跑一次，certbot `renew --dry-run`）。
- 用户更新 GitHub Actions Secrets（主机 IP、known_hosts），各仓库触发一次部署或 `ssh` 冒烟。
- 用户手机切换 Tailscale Exit Node 到 `nyh-prod-2026`；`mp.nanyahui.com` 后台的 hosts 里，把 `100.78.12.107` 换成新机的 Tailscale IP。
- 更新档案和时间线：`nyh-prod-2026/README.md`（服务、目录、共享 Redis 登记表从 `nyh-prod/README.md` 移过来）、`docs/operations/nyh-prod-2026.md`、`docs/operations/nyh-prod.md`、`AGENTS.md` 服务器表（nyh-prod 标注退役 / 到期时间）。提交。

---

## Verification Contract

| 项目 | 标准 |
| --- | --- |
| 站点 | U4 记录的每个域名的状态码，在公网（DNS 生效后）和新机 `--resolve` 下一致 |
| 队列 | 新机 supervisor 20 个 RUNNING，旧机 0；`think jobs:monitor` 不报积压；`line-*` 日志里没有连接被拒 / 403 |
| 公众号 | `nyh-wechat-mp` `/healthz` 正常，`journalctl -u nyh-wechat-mp` 有新的回调记录 |
| 容器 | `docker ps` 和旧机切换前的列表一致（`fa-mysql` 停着），健康检查 healthy |
| RDS 连接 | 旧机到 `172.31.138.209:5432` 的连接数降到 0；新机有连接 |
| 定时任务 | 宝塔计划任务在新机启用、旧机停用；`notification?action=timing` 的日志只在新机增长 |
| 证书 | `openssl s_client` 看到的证书和旧机一致，没有过期 |

## Definition of Done

- Success Criteria 全部满足，旧机上没有会写数据的进程在运行。
- 旧机快照完成并记录 ID。
- 文档已更新并提交。

## Open Questions

1. **旧 ECS 续不续费？**（KD3）不续费就没有回滚。
2. **哪些第三方接口按 IP 白名单？**（U1-4）
3. **`do1-relay`（公网 8080 → sub2api）谁在用？** 如果客户端直接写的是 `47.239.167.8:8080`，换 IP 后要改客户端配置。
4. **宝塔面板 10463 是否继续对公网开放？** 建议只对 Tailscale 开放。
5. **ThreatBook OneAV 要不要装到新机？** 新机已有云盾，默认不装。
6. **`yysg`、`test-agent` 的站点目录（共 16.5G）** 只留在旧机快照里，可以吗？
