# nyh-prod-2026

**生产服务器**。2026-11-10 17:52 起接替 `nyh-prod`（旧 ECS 11-11 00:00 到期，不续费）。承载南亚汇（NYH）、AcquiLang / Kanova、DDRicher、yunshu（bnsg）、guagua 等项目的生产站点与后台任务；业务库在阿里云 RDS PG，不在本机。

**不装宝塔**，全部由 Claude 维护：apt / systemd / Docker / certbot，配置源码都在本目录，服务器上是副本。改配置的流程是：改仓库里的文件 → 推到服务器 → `nginx -t` / 重启对应服务 → 记录到 [`docs/operations/nyh-prod-2026.md`](../docs/operations/nyh-prod-2026.md) → commit。

迁移计划与过程：`docs/plans/2026-11-10-1545-ops-nyh-prod-to-nyh-prod-2026-migration-plan.md`，以及两台机器 11-10 的运维时间线。

## 连接与实例

```bash
ssh nyh-prod-2026   # = ssh root@8.217.145.133，用 ~/.ssh/id_ed25519
```

| 项目 | 值 |
| --- | --- |
| 公网 IP | `8.217.145.133`（DNS 全部指向这里） |
| Tailscale | `100.113.16.89`，节点名 `nyh-prod-2026`，`--advertise-exit-node --accept-dns=false` |
| 内网 IP | `172.21.63.219`（轻量服务器「内网互通」到 `vpc-j6cy0gudplcfwatq8i43f`，RDS 白名单分组 `swas_nyh2026`） |
| 云厂商 / 地域 | 阿里云**轻量应用服务器**（SWAS），`cn-hongkong` |
| 实例 | `a9670f44600c4671a95c2a46a795657a`（控制台名 `Debian-uccj`），套餐 `swas.s.c4m16s80b1.linux`，到期 `2027-11-10` |
| aliyun CLI | `--profile default`（不是 `new-hk`，那是 qingfan-prod 所在账号）；swas 命令用新语法，例如 `aliyun swas-open list-firewall-rules --profile default --biz-region-id cn-hongkong --instance-id <实例>` |
| 系统盘 | `d-j6c31h3s5ffawxajzmpq`，ESSD 80G，单盘 |
| 系统 | Debian 13.7 (trixie)，内核 `6.12.116+deb13-amd64`，UEFI（`grub-efi-amd64` + shim） |
| 规格 | 4 vCPU / 16G（`free -h` 显示 14Gi：crashkernel 预留和固件地址空间）/ 无 swap |
| 时区 | `Asia/Shanghai`（CST） |
| SSH | 只允许公钥，root 可直接登录，端口 22；`authorized_keys` 见下表（迁移用的旧机临时密钥 11-10 已删） |

### root 的 `authorized_keys` 与 CI 部署

| 注释 | 用途 |
| --- | --- |
| `konghai@konghai.me` | 本机 konghai 的 `~/.ssh/id_ed25519` |
| `github-actions@acquilangai` | `IAmKongHai/Kanova` 部署（Secrets `SERVER_HOST` / `SERVER_USER` / `SSH_PRIVATE_KEY`；known_hosts 在 workflow 里现场 `ssh-keyscan`） |
| `github-actions@yunshu-bnsg` | `konghai-friends-lab/YPF-YunShu` 部署与运维 workflow（`SSH_HOST` / `SSH_USER` / `SSH_PORT` / `SSH_KNOWN_HOSTS` / `SSH_PRIVATE_KEY`） |
| `github-actions-deploy-key-ddricher` | `konghai-friends-lab/ddricherAi` 部署（`HOST` / `USERNAME` / `PORT` / `KEY`，appleboy/ssh-action） |
| `hon-2026` | 同事 hon 的个人密钥（ED25519 `SHA256:t5JxvwYZEe9z6KOnXyd08lYm/3rRTIrfzSM8J1k3e+0`），2026-11-11 应用户要求加入，以 root 登录 |

三把 CI 公钥 2026-11-10 从旧机原样复制过来，三个仓库的主机 Secret 已改为 `8.217.145.133`、YunShu 的 `SSH_KNOWN_HOSTS` 换成新机指纹（ED25519 `SHA256:2GQoiNC5ZF89UtpYve3XaLGnaTFAlHZ9xQQW+TXULNg`）。旧机上另有 `hon-2025`、`hon-2026`、`konghai-recovery-2025`、`deploy_key_for_nyh_2025` 四把，当时**没有迁过来**（`hon-2026` 已于 11-11 单独补加）；以后哪个用途需要再单独加。重装系统或换主机密钥后，记得同步改 YunShu 的 `SSH_KNOWN_HOSTS`。

### 轻量服务器防火墙

只开放：TCP `80`、`443`、`22`，UDP `443`（HTTP/3）、`41641`（Tailscale），ICMP。

容器发布在 `0.0.0.0` 上的 `3001`、`8000`、`8181`、`8888`、`9100`、`9200`，以及 nginx 的 `888`、`8080`，**都靠这层防火墙挡住**，不要在控制台随手放开。`8080`（do1-relay）只给 tailnet 用。

## 服务一览

| 服务 | 形态 | 位置 / 源码 | 说明 |
| --- | --- | --- | --- |
| nginx 1.26 | apt + systemd | `/etc/nginx/nginx.conf`、`/etc/nginx/nyh/`（仓库 `nginx/`） | 全部站点 |
| PHP 7.4 FPM | 容器 `php74-fpm`，host 网络 `127.0.0.1:9074` | `/opt/stacks/php/`（仓库 `docker/php/`） | NYH 各站点 |
| PHP 8.2 FPM | 容器 `php82-fpm`，`127.0.0.1:9082` | 同上 | |
| PHP 队列 | 容器 `php74-worker`（compose profile `worker`），容器内 supervisor 跑 9 个队列进程 | 同上，`worker-supervisor/` | cashRefund、createOrderJobQueue×5、fareJobQueue、nyh-sms-worker、orderPushJobQueue；队列在 RDS `jobs` 表 |
| Redis 7480 | 容器 `redis-7480`（`redis:8.0.5`），`127.0.0.1:7480` 与 `172.17.0.1:7480` | `/opt/stacks/redis-7480/`（仓库 `docker/redis-7480/`），数据 `/opt/stacks/redis-7480/data` | 原宝塔 Redis，密码沿用；以 `redis7480`(992) 运行 |
| shared-redis | 容器 `shared-redis`（`redis:7.4.12`），`127.0.0.1:6379` | `/www/docker/shared-redis/` | 多项目共享，见下文登记表 |
| line-* ×10、nyh-notify | 宿主机 supervisor | `/etc/supervisor/conf.d/`（仓库 `supervisor/`） | 线路提交 / 查询；nyh-notify 监听 `127.0.0.1:9870` |
| nyh-wechat-mp | systemd，`127.0.0.1:9871` | 仓库 `systemd/`；程序 `/www/server/nyh-wechat-mp/` | 公众号；`nyh-wechat-mp-watchdog.timer` 巡检 |
| guagua-api | systemd，`127.0.0.1:3400` | 仓库 `systemd/guagua-api.service` | `guagua.honc.fun` |
| yunshu-api | 容器，`127.0.0.1:3300` | `/www/yunshu/infra/prod/` | `bnsg.konghai.me` |
| Kanova backend / admin | 容器 `acquilang-backend` `:8000` / `acquilang-admin` `:3001`（名字待发版时换成 `kanova-*`） | `/www/wwwroot/python/kanova/docker-compose.prod.yml`（compose `name: acquilang`）；旧路径 `/www/wwwroot/python/acquilang` 是指向它的符号链接 | `api.kanova.app`、`admin.kanova.app`；移动端静态站 `kanova.app` 是 `kanova-mobile-web/out` |
| richer engine / gateway / web | 容器 `richer-*-1`，`:9200` / `:9100` / `:8181` | `/www/wwwroot/ddricher/richer/docker-compose.prod.yml` | `ddricher.ai`、`gateway.ddricher.ai` |
| richer_web | 容器 `richer-web` + `richer-nginx`（`:8888`） | `/www/wwwroot/ddricher/richer_web/` | `admin.ddricher.ai`；依赖外部网络 `richer_strategy_plus_network`（177.10.0.0/16，手工建的） |
| new-api | 容器 `new-api`（`127.0.0.1:3200`）+ `new-api-redis`（不发布端口，以 `newapi-redis` 991:988 运行） | `/opt/stacks/new-api/`（仓库 `docker/new-api/`）；`.env`、`redis.conf` 只在服务器上 | `tovo.sh`，AI API 网关；库在 RDS `new_api`（账号 `new_api_user`）；镜像固定 `calciumion/new-api:v1.0.0-rc.49`；站内 1 计费单位 = ¥1（OpenAI 模型按官方美元价 ×7.3 设 `ModelRatio = USD_in × 3.65`）；上游对接 `do-1` `sub2api` 采用 `default` 组主备双通道：渠道 #2 主 `https://sub.tovo.sh`（优先级 10，`do-1` 仅放行 `8.217.145.133` + Tailscale 白名单）、渠道 #3 备 `http://100.86.92.103:8080`（优先级 0，Tailscale 直连），`test_model=gpt-6-luna` |
| 跨洋 TCP 调优 | sysctl + modules-load | `/etc/sysctl.d/98-cross-ocean-tcp.conf`（仓库 `sysctl/`）、`/etc/modules-load.d/bbr.conf` | 开启 `bbr` + `fq`、`tcp_slow_start_after_idle=0`、32MiB TCP 缓冲区上限（与 `do-1` 对称配置） |
| archery | 容器，`127.0.0.1:3100` | `/www/wwwroot/Archery/` | SQLite 在站点目录里 |
| fix-aliyun-dns-vs-tailscale | systemd oneshot | 仓库 `sbin/`、`systemd/` | 见「坑」第 1 条 |
| 云盾 Aegis | `aegis.service` | — | eBPF 模式，见下文 |

### 常用操作

```bash
# nginx：改完先测再 reload（平滑，不断连接）
nginx -t && systemctl reload nginx

# PHP：改 php.ini / FPM 池后
cd /opt/stacks/php && docker compose restart php74-fpm php82-fpm
cd /opt/stacks/php && docker compose --profile worker restart php74-worker
docker exec php74-worker supervisorctl status          # 9 个队列

# 宿主机上执行 PHP CLI（cron 和 CI 的 php74 think … 都走这个包装，在 php74-fpm 容器里以 www 身份、当前目录执行）
cd /www/wwwroot/load.nanyahui.com && php74 think jobs:monitor

# supervisor（line-* / nyh-notify）
supervisorctl status
supervisorctl restart line-xiaola-submit

# systemd 服务
systemctl restart nyh-wechat-mp guagua-api
```

注意 `php74` 包装脚本和 `docker exec -i` 会吞 stdin：在 ssh heredoc 里调用时加 `</dev/null`，或者写成脚本文件再执行。

## 定时任务

全部在 `/etc/cron.d/nyh-tasks`（仓库 `cron/nyh-tasks`，每条注明来自旧机哪个宝塔任务），日志 `/var/log/nyh-cron/<任务名>.log`，logrotate 配置 `/etc/logrotate.d/nyh`（仓库 `cron/logrotate-nyh`）。

- 停用某条：行首加 `#OFF# `；全部停用：`sed -i 's/^\([^#A-Z].*\)$/#OFF# \1/' /etc/cron.d/nyh-tasks`。
- 队列巡检 `jobs:monitor` 每 5 分钟一次，正常输出是 `异常 0 组，动作 none`。
- 证书续期由 `certbot.timer` 负责，不在这里。

## 证书

- 全部由 certbot 管理（`/etc/letsencrypt/live/<证书名>/`），webroot 统一是 `/var/www/letsencrypt`。各 vhost 都 `include /etc/nginx/nyh/snippets/acme.conf`（里面有 `allow all`，所以带 IP 白名单的站点如 `mp.nanyahui.com` 也能验证）。例外：`guagua.honc.fun` 的 vhost 是手写的，webroot 是 `/www/wwwroot/guagua/acme`，续期配置与之一致。
- 续期：`certbot.timer` 每天两次；每张证书都配了 `--deploy-hook "systemctl reload nginx"`。演练：`certbot renew --dry-run`。
- 新站点签证书：

  ```bash
  certbot certonly --webroot -w /var/www/letsencrypt --cert-name <域名> -d <域名> [-d 其它域名] \
    --non-interactive --agree-tos --keep-until-expiring --deploy-hook "systemctl reload nginx"
  ```

  证书签下来之前 vhost 不能引用它（`nginx -t` 会失败）：新域名先放一个只有 80 端口 + `include acme.conf` 的临时 vhost，签完再换成正式配置（kanova.app 就是这样做的）。
- 证书名与域名：`kanova.app`（含 admin / api）、`ddricher.ai`（含 www）、`load.nanyahui.com`（含 `api.nanyahui.com`），其余每个域名一张。
- `/etc/nginx/nyh/cert/` 是旧机宝塔带过来的证书，只剩默认站点（自签）和不再使用的站点在引用：`-al.konghai.me` 三个（Kanova 旧域名，DNS 已删，证书到 2027-02 过期），不会续期。废弃站点 `zen-design-hualu.konghai.me`、`nyh-2025.konghai.me`（原宝塔面板入口）的 vhost、证书、网站文件和日志 2026-11-10 已删除，备份 `/root/cutover-20261110/abandoned-sites-20261110.tar.gz`。
- Cloudflare：`numbers.konghai.me` 是橙云（回源走 443），其余 Cloudflare 记录必须保持灰云，否则 HTTP-01 和 IP 白名单都会出问题。

## nginx 结构

- `/etc/nginx/nginx.conf`：手写（仓库 `nginx/nginx.conf`）。http 块里固定了 `ssl_ecdh_curve`，**不要删**，见「坑」第 2 条。
- `/etc/nginx/nyh/`：由 `scripts/convert-baota-nginx.py` 从宝塔配置转写而来（`http.conf`、`vhost/`、`extension/`、`rewrite/`、`snippets/`）。之后手工改过：vhost 证书路径（→ `/etc/letsencrypt/live/`）、新增 `kanova.app` / `admin.kanova.app` / `api.kanova.app` 三个 vhost、API CORS 白名单、`snippets/acme.conf`。**不要再重新跑转写脚本覆盖**，直接改仓库里的文件。
- 站点日志：`/www/wwwlogs/<站点>.log` / `.error.log`；全局 error log `/www/wwwlogs/nginx_error.log`，级别 `crit`（TLS 握手失败不会记录，排查时用 `tcpdump`）。

## shared-redis（共享 Redis）

从 nyh-prod 迁来，2026-11-07 起供本机各项目共用（第一个接入方是 `nyh-wechat-mp`）。本仓库负责它的升级、登记表和备份策略。

| 项 | 值 |
| --- | --- |
| 容器 | `shared-redis`，镜像 `redis:7.4.12`（固定小版本），`--restart=always`，`--memory=256m --memory-swap=256m`，日志 10m×3 |
| 运行身份 | 宿主机专用系统用户 `shared-redis`，**本机是 `993:991`**（旧机 UID 不同，迁移时已按新 UID 重建）；不要用镜像默认的 uid 999，它在这台机器上是 `nyh-notify` |
| 端口 | 只绑 `127.0.0.1:6379`（原宝塔 Redis 在 7480，与此无关） |
| 目录 | `/www/docker/shared-redis/`（root 700）：`data/`（RDB）、`conf/redis.conf`、`conf/users.acl`、`.admin_pw`、`.<项目>_pw`（root 600） |
| 内存 | `maxmemory 200mb`，`maxmemory-policy volatile-lru` |
| 持久化 | RDB：`save 900 1 / 300 10 / 60 10000`，无 AOF |

### 约定（所有接入项目都要遵守）

- **只放可以丢的数据**（缓存、会话、计数等）。业务数据放数据库。
- **所有 key 必须设过期时间**。淘汰策略是 `volatile-lru`，只淘汰带 TTL 的 key；不带 TTL 的 key 写满后会导致写入报错，影响所有项目。
- **每个项目一个 ACL 账号，key 限定在自己的前缀下**，不靠 DB 编号隔离。模板：

  ```
  user <项目账号> on #<密码 sha256> ~<前缀>:* resetchannels +@all -@dangerous -@admin -scan -randomkey
  ```

  `-@dangerous -@admin` 挡住 `FLUSHALL`、`CONFIG`、`KEYS` 等能影响其它项目的命令；`SCAN`、`RANDOMKEY` 不在 `@dangerous` 里且不受前缀限制，必须单独去掉，否则能列出所有项目的 key 名。
- `default` 用户关闭；`admin` 是运维账号（`~* &* +@all`），只给人用。
- ACL 文件里只存密码的 sha256，明文密码在宿主机 root 600 文件里，不出现在命令行。

### 运维操作

```bash
# 用某个账号执行命令（密码经 stdin 传进容器，不进命令行；用文件形式执行，别塞进 ssh heredoc）
docker exec -i shared-redis sh -c 'read -r P; REDISCLI_AUTH="$P" redis-cli --no-auth-warning --user admin "$@"' _ INFO memory < /www/docker/shared-redis/.admin_pw
```

- **新增项目账号**：生成密码存 `/www/docker/shared-redis/.<项目>_pw`（root 600），按模板在 `conf/users.acl` 追加一行（写 sha256），再用 admin 执行 `ACL LOAD`（不用重启），最后更新下面的登记表。
- **升级**：换镜像小版本需要重建容器（数据在 `data/`，RDB 会保留），会短暂中断所有接入方，先在登记表里确认各项目都能容忍 Redis 不可用。
- **备份**：当前只放可丢数据，不单独备份 RDB。

### 登记表

| 项目 | ACL 账号 | key 前缀 | 用途 | 预计内存 | Redis 不可用时的影响 | 接入时间 |
| --- | --- | --- | --- | --- | --- | --- |
| nyh-wechat-mp | `nyh_wechat_mp` | `wxmp:*` | access_token 缓存、后台会话、登录失败计数 | < 1MB | 回调不受影响；token 退回进程内缓存；后台登录提示「会话服务不可用」 | 2026-11-07 |

## 坑（都踩过）

- **HTTP/3**：`reuseport` 只在 `0.default.conf` 的 `listen 443 quic reuseport;` 声明一次，新 vhost 写不带参数的 `listen 443 quic;`。没有 reuseport 时所有 worker 共用一个 UDP socket，h3 连接会中断（11-10 全站 h3 不可用就是这个原因）。反代一律用 `proxy_set_header Host $host;`，**不要用 `$http_host`**：h3 请求没有 Host 头，上游会收到空 Host 回 400。

1. **阿里云 + Tailscale：所有 `100.100.x.x` 的阿里云内网服务回包都会被 Tailscale 的 `ts-input` 链丢弃**（源地址落在 100.64/10）。已知受影响：VPC DNS `100.100.2.136/138`（解析卡死，表现为连 RDS 超时、FPM 启动 40s），apt 源 `mirrors.cloud.aliyuncs.com`（`100.100.2.148`）。处理：`fix-aliyun-dns-vs-tailscale.service` 把 DNS 改成 223.5.5.5 / 223.6.6.6 / 8.8.8.8（改完后已有容器要重建才能拿到新的 resolv.conf）；apt 源已改为公网 `https://mirrors.aliyun.com`（11-10）。以后再接入阿里云内网服务（如 OSS 内网 endpoint），先确认不是 100.100 段。
2. **Debian 13 的 OpenSSL 3.5 + Cloudflare 回源 = 525**。默认密钥交换组配置会对只带 X25519 key share 的客户端发 HelloRetryRequest 要求 X25519MLKEM768，Cloudflare 的第二个 ClientHello 被判 `illegal_parameter`。`nginx.conf` 里的 `ssl_ecdh_curve X25519MLKEM768:X25519:prime256v1:secp384r1;`（单个优先级组，不发 HRR）就是为此加的。
3. **Sury 的 PHP-FPM 构建内置遥测**（`telemetry.sury.org`，没有关闭开关），compose 里用 `extra_hosts` 指向 `127.0.0.1`，数据不会出去。重建镜像时保留这一项。
4. **Debian 13 不认 `date.timezone = PRC`**（退回 UTC），php.ini 用 `Asia/Shanghai`，镜像装了 `tzdata-legacy`。
5. **Docker 地址池**：`daemon.json` 固定 `bip 172.17.0.1/16`（应用里写死了 172.17.0.1）和 `default-address-pools 10.210.0.0/16`。默认池会撞上本机内网 `172.21.0.0/18` 或 RDS 的 `172.31.x`，把路由劫持掉。
6. **从本机 rsync 到服务器一律加 `--chown=root:root`**，否则文件属主变成本机的 uid 501；`rsync -a dir/ host:/etc/x/` 还会改目标目录本身的属主。
7. **ssh heredoc 里的 `docker exec -i`、`php74`、内层 ssh 会吞掉剩余 stdin**，后面的命令静默不执行。加 `</dev/null`，或者先写成脚本文件。

## 已知问题（迁移前就存在，没处理）

- `richer-gateway-1` 日志大量 Telegram `401 Unauthorized` 和 Tiger 美股行情 `permission denied`（旧机上一天就各有 4 万多条）。
- `api.ddricher.ai` 反代 `127.0.0.1:7800`，没有进程在听（旧机也一样）。
- richer_web 的 `.env-docker` MySQL 指向 11-07 已到期的 RDS `rm-j6cb0v171f2al0h41`，`admin.ddricher.ai` 可能本来就不能用。
- Kanova 服务器上的代码还是旧版（`cdcffd45`，10-19，remote 仍是 `AcquiLangAI.git`），写死旧域名 `*-al.konghai.me`；GitHub main 已全面改名为 kanova（子目录、容器 `kanova-*`、网络 `kanova-network`、域名 `kanova.app`）。11-10 只把服务器目录改成了 CI 的路径（`python/kanova/kanova-*`），换成 main 代码和 `kanova-*` 容器由用户另开 session 做（注意：新容器占同样的 8000 / 3001，要先停旧容器；`backup-rds.sh` 里的容器名 `acquilang-backend` 要一起改；之后可删 `acquilang` 符号链接和 compose 的 `name: acquilang`）。
- 到 mas-sit（`100.109.223.53`）tailscale ping 不通（旧机也不通）。

## 云盾 Aegis

2026-11-10 升级后用官方免密钥脚本 `http://update2.aegis.aliyun.com/download/install.sh` 重装，客户端 `aegis_11_37`，`aegis.service` enabled。在 6.12 内核上**不加载 `AliSecGuard` 内核模块**，改用 eBPF 挂钩，内核 `tainted=0`，云安全中心显示 `online`。以后升级内核不需要重装，升级后检查 `systemctl is-active aegis` 和云安全中心在线状态即可。要卸载：它有内核自保护，按升级手册第 3 节用开机参数 `systemd.mask=aegis.service` 绕过后再卸。

云助手 `aliyun.service` 保留，用于免 SSH 应急执行命令。

## 快照

| 快照 ID | 名称 | 说明 |
| --- | --- | --- |
| `s-j6cf8ldl9p1wznd46hrm` | `debian12-before-upgrade` | 升级前，**云盾还在**；可删 |
| `s-j6ch07g86tunb409g1tf` | `debian13-baseline-20261110` | 升级完成、还没重装云盾时的基线；可删 |
| `s-j6cct8y5ay0igrzzwuhb` | `nyh-prod-2026-live-20261110` | 业务切换完成、证书改 certbot 后（2026-11-10 19:03），删除废弃站点之前 |

## 升级参考

Debian 12 → 13 原地升级完全按 `/Users/konghai/Code/Project/DigitalOcean/docs/阿里云轻量服务器-Debian12原地升级13-操作手册.md`（本机路径）。现在装的已经是 `grub-efi-amd64`，以后 apt 升级 grub 不需要额外处理。
