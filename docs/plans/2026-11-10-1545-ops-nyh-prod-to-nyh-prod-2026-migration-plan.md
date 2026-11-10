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

> 修订记录
> - 15:45 初稿（新机装宝塔、整体覆盖）。
> - 16:10 用户确认旧机不续费；旧机 `/www` 已清理到 16G。
> - 16:25 **用户决定新机不装宝塔**：以后服务器全部由 Claude 维护，不再人工在面板里操作。本版按纯 Debian（apt + systemd + certbot）重写 U3–U6。
> - 16:35 **用户决定 PHP 用 Docker 运行**（以后这台机器上的服务都尽量用 Docker）；Redis 按 Claude 建议也用 Docker。见 KTD8，KTD1 表中 PHP / Redis / supervisor 三行以 KTD8 为准。

## Goal Capsule

- **Objective:** nyh-prod（ECS `i-j6chyzdlvn2vkqw0jbgv`，`47.239.167.8`）上所有在用的站点、队列 worker、容器、定时任务，今天全部改由 nyh-prod-2026（SWAS `a9670f44600c4671a95c2a46a795657a`，`8.217.145.133`）提供。用户和第三方看到的域名、证书、行为都不变。
- **硬截止：** 旧机是包年包月实例，**到期时间 `2026-11-10T16:00Z` = 2026-11-11 00:00 CST，用户确认不续费**。00:00 以后不能切回旧机。
- **Means:** 新机不装宝塔，用 Debian 13 的标准组件重建运行环境：nginx（apt）、PHP 7.4 / 8.2（Sury 源，与旧机同版本 7.4.33 / 8.2.35）、Redis（apt）、supervisor（apt）、Docker CE、certbot、`/etc/cron.d`。**应用目录保持 `/www/wwwroot/...` 不变**，这样应用配置、supervisor 命令、CI 部署脚本都不用改。先在新机把所有服务起好，但不跑会写数据的进程；再在一个短窗口内停旧机的 worker / 定时任务，做最后一次增量同步，起新机的 worker，切 DNS。数据库都在 RDS PG 上，两台共用，不迁移。
- **Authority:** 用户在本次会话中确认的范围 > 本计划 KTD > 单元内细节。`AGENTS.md` 的「生产服务器操作守则」始终有效：停旧机进程、切 DNS 都要用户确认。
- **Stop conditions:**
  - U4 里任何一个核心站点（load / center / vip / mp / ddricher / acquilang / bnsg）在新机上用 `--resolve` 测不通，不进入 U5。
  - U5 里新机起 worker 后 10 分钟内出现批量报错：先停新机 worker 排查。**22:30 之前**仍可回旧机（旧机恢复 worker、DNS 改回）；22:30 以后不再回旧机，只在新机上修。
- **Who finishes:** Claude 经 `ssh nyh-prod`、`ssh nyh-prod-2026`、aliyun CLI（`--profile default`）执行服务器侧操作。DNS（Cloudflare + DNSPod）、第三方 IP 白名单、GitHub Secrets 由用户操作，Claude 给出逐条清单。

---

## Product Contract

### Summary

把一台用宝塔管理的 2C/8G ECS 上的约 20 个站点、20 个 supervisor 进程、9 个运行中的容器和 20 来个定时任务，搬到一台 4C/16G 的轻量服务器上。新机不装宝塔，宝塔原来的职责逐项换成标准组件（见 KTD1）。

### Problem Frame

- 旧 ECS 今晚到期，不续费。
- 公网 IP 是 ECS 固定公网 IP，带不走：必须切 DNS，按 IP 白名单的第三方都要加 `8.217.145.133`。
- RDS PG 只有内网地址。**已解决**：用户开通轻量服务器「内网互通」，RDS 加白名单分组 `swas_nyh2026`，新机已验证可连（`docs/operations/nyh-prod-2026.md` 15:55）。
- **已解决**：新盘 80G 不够整盘照搬的问题。旧机 `/www` 已清理到 16G（`docs/operations/nyh-prod.md` 16:10）。
- 新问题：去掉宝塔后，宝塔管着的 27 个 nginx 站点配置、27 张证书的自动续期、13 个计划任务、PHP-FPM 池、日志切割都要换成标准组件，不能漏。

### Requirements

- R1. 下表「迁移」为「是」的服务，切换后在新机上正常工作，域名、证书、端口不变。
- R2. 队列 worker 和会写数据的定时任务，任何时刻只在一台机器上运行（两台共用同一个 RDS，双跑会重复下单、重复发短信 / 通知）。
- R3. 本地状态完整带过去：宝塔 Redis（7480）的数据、上传文件、Archery 的 SQLite、guagua uploads、nyh-notify / nyh-wechat-mp 的工作目录。
- R4. 旧机数据盘已有手动快照 `s-j6c234k2untx79f5jjiu`；切换前再给系统盘打一个。
- R5. 证书续期由 certbot 接管，切换当晚至少跑通一次 `certbot renew --dry-run`。
- R6. 新机的服务、目录、定时任务、续期方式写进 `nyh-prod-2026/README.md`，以后 Claude 按档案维护；运维时间线照常记录。

### 服务清单（2026-11-10 只读盘点，已扣除 16:10 清理掉的部分）

| 类别 | 服务 | 迁移 | 新机实现 |
| --- | --- | --- | --- |
| PHP 7.4 站点 | `load.nanyahui.com`（+`api.nanyahui.com`）、`load.nanyahui.cn`、`center.nanyahui.com`、`vip.nanyahui.com`、`vip.nanyahui.cn` | 是 | Sury `php7.4-fpm` |
| PHP 8.2 站点 | `konghai.me`、`nyh-2025.konghai.me`、`numbers.konghai.me`（Cloudflare 橙云）、`127.0.0.1`（richer_web） | 是 | Sury `php8.2-fpm` |
| 静态 / 反代 | `mp.nanyahui.com`、`vip-dev.nanyahui.com`、`zen-design-hualu.konghai.me`、`ddricher.ai`(+www)、`gateway.ddricher.ai`、`admin.ddricher.ai`、`api.ddricher.ai`、`admin-al` / `api-al` / `m-al.konghai.me`、`bnsg.konghai.me`、`smith.konghai.me`、`duowei.konghai.me`、`guagua.honc.fun`、`do1-relay`（:8080） | 是 | apt `nginx`。`api.ddricher.ai` 反代的 `127.0.0.1:7800` 在旧机上就没有进程，照原样带 |
| 已停用站点 | `fa.nanyahui.com`（目录保留，供公众号回滚）；`yysg`、`test-agent`（目录已删） | 否 | 不建 vhost。fa 目录随 `/www` 同步 |
| supervisor | 20 个程序：nyhAgent 队列（cashRefund、createOrderJobQueue×5、nyh-sms-worker）、nyhCenter 队列（fareJobQueue、orderPushJobQueue）、`nyh-line-core` 10 个 line-*、`nyh-notify` | 是 | apt `supervisor`，ini 原样放到 `/etc/supervisor/conf.d/`。**R2 重点** |
| systemd | `guagua-api`、`nyh-wechat-mp` + watchdog / alert、`fix-aliyun-dns-vs-tailscale` | 是 | unit 原样拷贝 |
| 容器 | `yunshu-api`、`acquilang-backend`、`acquilang-admin`、`richer-{engine,gateway,web}-1`、`richer-web` + `richer-nginx`、`archery`、`shared-redis`；`fa-mysql`（停用，只带数据） | 是 | Docker CE；镜像 `docker save` / `load`，不重新构建 |
| Redis | 宝塔 Redis 8.0.5 `:7480`（226 个 key，无过期，13.5M）；`shared-redis` `127.0.0.1:6379` | 是 | apt `redis-server` 8.0.2，同端口、同密码，RDB 在窗口内拷 |
| 宝塔计划任务（13 个启用） | 2 个 `notification?action=timing`（每 2/3 分钟）、2 个 `jobs:monitor`（每 5 分钟）、`cash:cleanup`（周一 03:10）、3 个 myPoster 二维码清理、NYH-Center / NYH-Agent 定时任务（toUrl）、续签证书、面板证书、切割日志、木马查杀 | 是（业务类） | 业务类写成 `/etc/cron.d/nyh-*`；续签证书 → certbot；切割日志 → logrotate；面板证书、木马查杀 → 不再需要 |
| root crontab 自定义 | `backup-rds.sh`（02:00）、yunshu `healthcheck.sh`、`cmm-sit-healthz.sh` | 是 | `/etc/cron.d/` |
| root crontab 自定义 | `panel-cert-reload.sh`、`docker-panel-letsencrypt-renew.py` | 否 | 宝塔专用 |
| 证书 | 宝塔 `vhost/cert` 下 27 套 Let's Encrypt；certbot 管 `guagua.honc.fun` | 是 | 先拷现有证书文件直接用；DNS 切换后逐个用 certbot（webroot）重签并接管续期 |
| Tailscale | 节点 `nyh-prod`（`100.78.12.107`），Exit Node | 是（新节点） | 新节点 `nyh-prod-2026` |
| 安全 | 云盾（新机已装）、fail2ban（sshd）、ufw、ThreatBook OneAV | 部分 | 防火墙用轻量服务器自带的；fail2ban 只开 sshd；OneAV 待定 |
| 宝塔自身 | 面板 :10463、`BT-FirewallServices`、`site_total`、WAF、phpMyAdmin :888 | 否 | 不再需要 |
| 其它残留 | `postfix-mta-sts-resolver`（postfix 没装）、`/etc/cron.d/tk-flywheel-backup`（脚本已不存在） | 否 | |

### Key Decisions

- KD1. 今天一次性切完，不分批。
- KD2. **新机不装宝塔**（用户 16:25 决定）。维护全部由 Claude 通过 SSH 完成，用标准 Debian 组件，靠档案和时间线记录状态。
- KD3. 旧机不续费（用户 16:00 确认）。旧机的长期存档是数据盘快照 `s-j6c234k2untx79f5jjiu`，加上切换前的系统盘快照。
- KD4. **目录不变**：`/www/wwwroot/...`、`/www/wwwlogs/`、`/www/server/nyh-notify`、`/www/server/nyh-wechat-mp`、`/www/yunshu`、`/www/docker` 保持原路径。只有宝塔自己的东西（`/www/server/{panel,nginx,php,redis}`）不再使用。

### Success Criteria

- 公网解析全部指向 `8.217.145.133`，每个域名的状态码和切换前一致。
- 新机 supervisor 20 个程序 RUNNING，旧机为 0；业务定时任务只在新机运行。
- 切换后 1 小时内：nyhAgent 下单队列正常消费，`nyh-wechat-mp` 收到公众号回调，`/healthz` 正常。
- `certbot renew --dry-run` 通过（DNS 已经切过来的域名）。

### Scope Boundaries

- 不升级应用；PHP 版本与旧机一致（7.4.33 / 8.2.35）。nginx 从宝塔的 1.30.1 换成 Debian 的 1.26.3（有安全更新），配置语法兼容性在 U4 用 `nginx -t` 验证。
- 不修旧机上本来就坏的东西（`api.ddricher.ai` 后端不在、Kanova CI 指向 `python/kanova` 而服务器目录是 `python/acquilang`），只记录。
- 不动数据库。

#### Deferred to Follow-Up Work

- center `runtime/log` 的日志轮转（ThinkPHP 自己写的日志，不归 logrotate 管）。
- Kanova CI 部署路径核对。
- 宝塔 Redis 改名为普通 Redis 后，是否和 `shared-redis` 合并。

---

## Planning Contract

### Key Technical Decisions

- **KTD1. 宝塔职责替换表。**

  | 宝塔原来做的 | 新机怎么做 |
  | --- | --- |
  | 编译的 nginx 1.30.1，配置在 `/www/server/panel/vhost/nginx/` | apt `nginx`；每个站点一个 `/etc/nginx/sites-enabled/<域名>.conf`，由宝塔配置转写（KTD2） |
  | PHP 7.4 / 8.2，socket `/tmp/php-cgi-74.sock` 等 | Sury `php7.4-fpm` / `php8.2-fpm`，socket `/run/php/php7.4-fpm.sock`；FPM 池参数、`php.ini` 里改过的项从旧机对比后照搬；`/usr/local/bin/php74` → `/usr/bin/php7.4`（supervisor、cron 里写的是 `php74`） |
  | 宝塔 Redis 8.0.5 | apt `redis-server`，端口 7480、密码不变，`bind` 回环 + docker 网关 |
  | 计划任务（写进 root crontab，脚本在 `/www/server/cron/`） | 每个业务任务一行写进 `/etc/cron.d/nyh-tasks`，日志写 `/var/log/nyh-cron/` |
  | 证书申请与续期 | certbot + webroot（`/var/www/letsencrypt`），nginx 每个站点都放行 `/.well-known/acme-challenge/`；`deploy-hook` reload nginx |
  | 日志切割 | logrotate 管 `/www/wwwlogs/*.log` |
  | 防火墙 / 面板 / WAF / 统计 | 轻量服务器防火墙；其它不要 |
  | `.user.ini` 的 open_basedir | Sury PHP-FPM 同样读 `.user.ini`（`user_ini.filename` 默认值），文件随目录同步，不用改 |

- **KTD8. PHP 与 Redis 容器化（16:35 用户决定）。**
  - 镜像：自建 `nyh/php74`、`nyh/php82`，`FROM debian:trixie` + Sury 包（与旧机同版本、同扩展），容器内建 `www`(1000)。**不用官方 `php:7.4-fpm`**（2022 年停更，底层是未打补丁的 Debian 11）。Dockerfile 和 compose 放本仓库 `nyh-prod-2026/docker/php/`，服务器上在 `/opt/stacks/php/`。
  - 运行：compose 项目 `php`，三个容器：`php74-fpm`（`127.0.0.1:9074`）、`php82-fpm`（`127.0.0.1:9082`）、`php74-worker`（容器内 supervisord 跑 9 个 PHP 队列进程：cashRefund、createOrderJobQueue×5、nyh-sms-worker、fareJobQueue、orderPushJobQueue）。全部 `network_mode: host`，挂载 `/www/wwwroot`、`/www/php_session`（同路径），`TZ=Asia/Shanghai`。host 网络保证应用里的 `127.0.0.1` 地址、RDS 白名单、出口 IP 都不变。
  - nginx 留在宿主机（apt），`fastcgi_pass 127.0.0.1:9074` / `9082`；`SCRIPT_FILENAME` 路径与容器内一致，`.user.ini` 的 open_basedir 照常生效。
  - 宿主机 `/usr/local/bin/php74`、`php82` 是包装脚本：`docker exec -i -u www -w "$PWD" php74-worker php "$@"`（82 进 `php82-fpm`）。cron 和 CI 里的 `php74 think ...` 不用改。**队列 worker 不用这个包装脚本跑**：`docker exec` 的客户端被杀时容器里的进程不会退出，会留下孤儿 worker，所以常驻 worker 一律在 `php74-worker` 容器自己的 supervisord 里。
  - `php74-worker` 容器在 U5 之前**不启动**，这就是 R2 的开关。
  - Redis（原宝塔 7480）：`redis:8.0.x` 固定小版本，compose 项目 `redis-7480`，数据 `/www/docker/redis-7480/`，端口发布到 `127.0.0.1:7480` 和 `172.17.0.1:7480`（现有容器用 `host.docker.internal:7480`，不改应用配置），密码不变。
  - 宿主机 supervisor 只剩 Python 的 10 个 line-* 和 `nyh-notify`（今天不容器化，后续再说）。
- **KTD2. nginx 配置转写。** 不手写 27 个站点。脚本逐个读取宝塔 vhost，做固定替换：`include enable-php-74.conf` → `include snippets/php74.conf`（`fastcgi_pass 127.0.0.1:9074`，见 KTD8），82、00 同理；`/www/server/panel/vhost/rewrite/` → `/etc/nginx/nyh/rewrite/`，`extension/` → `/etc/nginx/nyh/extension/`（目录原样拷过去）；证书路径 → `/etc/nginx/certs/<站点>/`（先放旧证书，certbot 签完再改成 `/etc/letsencrypt/live/`）；去掉宝塔专用的行（`site_total` 日志格式、WAF、`#error_page` 注释块等）。`http` 级别的公共配置（`0.websocket.conf`、`0.fastcgi_cache.conf`、HSTS、TLS 套件）放进 `/etc/nginx/conf.d/`。转写后 `nginx -t` 必须通过。
- **KTD3. 用户和 UID。** 新机 `admin`(1000) 与 `www`(1000)、`systemd-timesync`(997) 与 `shared-redis`(997)、`systemd-resolve`(996) 与 `nyh-wechat-mp`(996) 冲突。删掉镜像自带、没在用的 `admin`，`www` 用 1000；其它用户按名字新建、让系统分配 UID。rsync 不加 `--numeric-ids`，按用户名映射属主。`shared-redis` 容器的 `--user` 换成新 UID 重建。PHP-FPM 池用户设为 `www`（和旧机一样）。
- **KTD4. 进程分「无状态」和「会写数据」两类。** 无状态的（nginx、php-fpm、guagua-api、nyh-wechat-mp、容器 web 层）在 U4 提前起好，用 `curl --resolve` 测。会写数据的（supervisor 全部、`/etc/cron.d/nyh-tasks`、`backup-rds`、richer-engine 等有定时逻辑的容器）在 U4 保持停止 / 注释，U5 先停旧机再起新机。
- **KTD5. 同步范围（约 16G）。** `/www` 里带：`wwwroot`、`wwwlogs`（只带最近 7 天）、`docker`、`yunshu`、`dk_project`、`server/nyh-notify`、`server/nyh-wechat-mp`、`php_session`。不带：`server/{panel,nginx,php,redis,…}`（宝塔自身，只把 vhost / rewrite / extension / cert 单独拷出来做转写）、`backup/`、`reserve_space.pl`。`/etc` 里带：supervisor ini、自定义 systemd unit、`/etc/letsencrypt`、`/root/.ssh/authorized_keys`（含 GitHub Actions 部署公钥）、`/usr/local/sbin` 下用到的脚本。`/var/lib/docker` 不拷，镜像 `docker save` / `load`。
- **KTD6. DNS 切换前先降 TTL**（用户随时可改解析，切换时一次性改完）。
- **KTD7. Redis 数据在窗口内拷**：旧机 `BGSAVE` → 停 → 拷 `dump.rdb` → 新机启动。

### Assumptions

- Sury 的 `php7.4` / `php8.2` 扩展覆盖旧机 `php -m` 的全部模块（16:20 已核对包列表：pgsql、redis、swoole、mcrypt、gmp、igbinary、xmlrpc、soap、intl、zip、gd 等都有）。U3 装完再用 `php -m` 对比一遍。
- 有一部分第三方接口按来源 IP 做白名单，**需要用户确认清单**；没确认的先假设需要加。
- GitHub Actions 部署只依赖 `/www/wwwroot/...` 路径和 PATH 里的 `nginx`（16:20 抽查了 Kanova 的 3 个 workflow），换 Secrets 里的 `SERVER_HOST` 即可。

### Risks & Dependencies

| 风险 | 影响 | 应对 |
| --- | --- | --- |
| nginx 转写漏掉某个站点的特殊配置（rewrite、反代头、HSTS、访问白名单） | 某个站点行为变了 | 转写脚本只做固定替换；U4 逐站对比新旧机的状态码和关键响应头；`mp.nanyahui.com` 的访问白名单专门测公网 403 |
| PHP 配置差异（上传大小、`disable_functions`、时区、FPM 进程数） | 上传失败、函数被禁、时间错乱 | U3 对比旧机 `php -i` 与新机输出，差异逐项照搬 |
| 双跑 worker / cron | 重复下单、重复退款、重复发短信 | KTD4；U5 严格先停旧再起新，两边对照 |
| 第三方 IP 白名单没加新 IP | 下单 / 查单失败 | U1 列清单；U5 起 worker 后先看 line-* 日志 |
| DNS 缓存 | 切换后仍有请求到旧机 | 降 TTL；旧机 nginx / php-fpm 在 23:30 前不停，只停写数据的进程 |
| 证书续期 | 某张证书到期前没续上 | 拷过去的证书有效期都在 1 个月以上（U4 核对）；当晚 certbot 重签全部域名 |
| 00:00 前没切完 | 旧机停机，业务中断 | 时间表倒排（见下）；22:30 为最后回滚点 |

### Sources

- 只读盘点：2026-11-10 15:20–15:45、16:15–16:25 CST 在 nyh-prod 上的查询结果。
- `docs/operations/nyh-prod.md`、`docs/operations/nyh-prod-2026.md`、`nyh-prod/README.md`。
- Sury 源 `packages.sury.org/php` trixie 的包列表；Debian 13 `nginx 1.26.3`、`redis-server 8.0.2`、`certbot 4.0.0`、`supervisor 4.2.5`。
- `IAmKongHai/Kanova` `.github/workflows/deploy-{admin,backend,mobile-web}.yml`。

---

## 时间表（CST）

| 时间 | 单元 |
| --- | --- |
| 16:30–17:15 | U2 快照 / 镜像导出、U3 新机底座 |
| 17:15–19:30 | U4 同步、nginx 转写、PHP 配置、起无状态服务、逐站测试 |
| 19:30–20:30 | U4 收尾：容器、cron 文件写好待启用；用户确认第三方白名单 |
| 21:00–22:00 | U5 切换窗口 |
| 22:00–23:30 | U6 证书重签、观察、文档 |

---

## Implementation Units

### U1. 用户侧准备（并行）

1. ~~决定是否续费~~（不续费）。~~内网互通~~（已完成）。
2. **降 TTL**：Cloudflare、DNSPod 里清单上的 A 记录 TTL 改 60s。
3. **第三方 IP 白名单加 `8.217.145.133`**：微信公众号、各充值 / 支付上游，由用户列出。
4. **Tailscale**：U3 时用登录链接授权新节点；切换后在 admin 里批准 Exit Node。
5. 回答 Open Questions。

### U2. 旧机快照与镜像导出

- 系统盘手动快照 `nyh-prod-system-final-20261110`。
- `docker save` 在用的镜像（`yunshu-api`、`acquilang-backend`、`acquilang-admin`、`richer-*:latest`、`richer_web-richer-nginx`、archery、`redis:7.4.12`、`mysql:8.0.36`）到 `/www/backup/migrate-images/`。
- 导出旧机运行参数，作为 U3/U4 的对照：`php -i`（7.4 / 8.2）、FPM 池配置、宝塔 Redis 配置、每个域名的状态码和关键响应头基准。

### U3. 新机底座

- 删 `admin`；建 `www`(1000)、`nyh-notify`、`nyh-wechat-mp`、`shared-redis`（KTD3）。
- apt：`nginx`、`supervisor`、`certbot`、`fail2ban`、`rsync`、`sqlite3`、`logrotate`；Docker CE（阿里云镜像源）；Tailscale。PHP、Redis 不用 apt 装（KTD8）。
- 构建 `nyh/php74`、`nyh/php82` 镜像；`php -m` 与旧机对比一致。
- PHP：对比旧机 `php -i`，把改过的 `php.ini` 项和 FPM 池参数（`pm`、`max_children`、`request_terminate_timeout` 等）写进镜像里的 `conf.d/99-nyh.ini`、`pool.d/www.conf`；装 `/usr/local/bin/php74`、`php82` 包装脚本（KTD8）。
- Redis：容器 `redis-7480`（KTD8），配置同旧机（密码、持久化策略）。
- 轻量服务器防火墙：放行 22、80、443/tcp、443/udp、41641/udp；8080 视 Open Question 3 决定。
- Tailscale 加入，主机名 `nyh-prod-2026`，`--advertise-exit-node`。
- 验证：`php7.4 -m` / `php8.2 -m` 与旧机一致；`docker run --rm hello-world`；`tailscale status`。

### U4. 同步、转写、起无状态服务

- 第一次 `rsync -aHAX`（KTD5），旧机推到新机。
- 宝塔 vhost / rewrite / extension / cert 拷到新机暂存目录，跑转写脚本（KTD2）生成 `/etc/nginx/sites-enabled/*.conf`，`nginx -t` 通过后启动。核对每张证书的到期时间。
- 起 `php74-fpm`、`php82-fpm`、`redis-7480`（此时是预同步的旧数据）、`guagua-api`、`nyh-wechat-mp`。**`php74-worker` 不起**。宿主机 supervisor 装好 Python line-* 和 nyh-notify 的 ini，但设 `autostart=false` 且不启动（U5 再改）。
- `docker load` 镜像；按各 compose 目录 `docker compose up -d` 起 web 层容器；`shared-redis` 用新 UID 重建。`richer-engine` 先看 compose / 代码是否有定时逻辑，有就先不起。
- 写好 `/etc/cron.d/nyh-tasks`（全部注释）、logrotate、certbot webroot。
- 验证：新机上逐个域名 `curl -sk --resolve <域名>:443:127.0.0.1`，状态码和关键响应头与 U2 基准一致；`mp.nanyahui.com` 从公网访问是 403；PHP 站点能连 RDS（load 首页正常）。

### U5. 切换窗口（21:00–22:00，开始前需用户确认）

1. 旧机：宝塔计划任务全部停用；root crontab 的业务任务注释掉。
2. 旧机：确认队列积压后 `supervisorctl stop all`；停 `richer-engine` 等有定时逻辑的容器、`yunshu-api`、`acquilang-backend`、`guagua-api`、`nyh-wechat-mp`。nginx / php-fpm 继续运行。
3. 旧机宝塔 Redis `BGSAVE` → 停 → 拷 `dump.rdb` → 新机重启 Redis。
4. 最后一次增量 rsync（上传目录、Archery `data/`、guagua `uploads/`、acquilang `uploads/` `static/`、nyh-notify / nyh-wechat-mp 工作目录、`runtime/session`）。
5. 新机：`docker compose up -d php74-worker`；宿主机 supervisor 的 ini 改 `autostart=true` 并启动；启用 `/etc/cron.d/nyh-tasks`；起剩下的容器和服务。
6. 用户改 DNS：所有 A 记录改 `8.217.145.133`（`numbers.konghai.me` 改 Cloudflare 源站）。
7. 验证（Verification Contract）。

回滚（仅 22:30 前）：新机 `docker stop php74-worker`、`supervisorctl stop all`、注释 `nyh-tasks`；旧机恢复第 1、2 步；DNS 改回。

### U6. 切换后收尾

- 证书：DNS 生效后逐个域名 `certbot certonly --webroot`，成功后把 vhost 的证书路径改到 `/etc/letsencrypt/live/`，`nginx -t && reload`；`certbot renew --dry-run`。
- 观察旧机访问日志降到接近 0 后，停旧机 nginx / php-fpm；系统盘快照确认完成。
- 用户更新 GitHub Actions Secrets（`SERVER_HOST`、known_hosts）；各仓库触发一次部署或 `ssh` 冒烟。
- 用户手机 Exit Node 换成 `nyh-prod-2026`；`mp.nanyahui.com` 后台的 hosts 改成新机 Tailscale IP。
- 文档：`nyh-prod-2026/README.md` 写完整档案（服务、目录、cron、证书续期、Redis、共享 Redis 登记表）；`docs/operations/` 两台机器的时间线；`AGENTS.md` 服务器表（nyh-prod 标注到期退役、nyh-prod-2026 改为按生产对待）。提交。

---

## Verification Contract

| 项目 | 标准 |
| --- | --- |
| 站点 | U2 基准里每个域名的状态码和关键响应头，在新机上一致 |
| 队列 | 新机 `php74-worker` 容器内 9 个 + 宿主机 supervisor 11 个 RUNNING，旧机 0；`think jobs:monitor` 不报积压；`line-*` 日志无连接被拒 / 403 |
| 公众号 | `nyh-wechat-mp` `/healthz` 正常，有新的回调记录 |
| 容器 | `docker ps` 与旧机切换前一致（`fa-mysql` 停着），健康检查 healthy |
| RDS 连接 | 旧机到 `172.31.138.209:5432` 的连接降到 0，新机有连接 |
| 定时任务 | `/var/log/nyh-cron/` 有新记录；旧机宝塔计划任务全部停用 |
| 证书 | 每个域名证书有效；`certbot renew --dry-run` 通过 |

## Definition of Done

- Success Criteria 全部满足，旧机上没有会写数据的进程。
- 旧机两块盘的快照 ID 已记录。
- 新机档案能让后续维护不依赖宝塔：每个服务在哪、怎么重启、怎么续证书、cron 在哪，都写清楚。

## Open Questions

1. 哪些第三方接口按 IP 白名单？（U1-3）
2. ~~宝塔面板 10463 是否对公网开放~~（不装宝塔，不存在了）。
3. `do1-relay`（公网 8080 → sub2api）谁在用？客户端如果直接写 `47.239.167.8:8080`，换 IP 后要改。
4. ThreatBook OneAV 要不要装到新机？默认不装（已有云盾）。
