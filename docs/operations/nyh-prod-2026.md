# nyh-prod-2026 运维操作时间线

## 2026-11-10 16:30–17:35 CST - 迁移准备（计划 U2–U4）：搭环境、首轮同步、起无状态服务

- 服务器：`nyh-prod-2026`（只读访问 `nyh-prod`，在旧机 `/www/backup/migrate-images/` 写了镜像导出文件、`/root/.ssh/migrate_nyh2026` 临时迁移密钥）
- 操作人：`Claude`（用户确认按计划执行；新机不装宝塔，PHP、Redis 用 Docker）
- 计划：`docs/plans/2026-11-10-1545-ops-nyh-prod-to-nyh-prod-2026-migration-plan.md`
- 影响：新机还没有线上流量（DNS 仍指向旧机）；旧机业务不受影响。
- 备份：旧机系统盘快照 `s-j6c9be0n6eh1zjh04l8w`（`nyh-prod-system-final-20261110`）；数据盘快照见 16:10 条目。
- 回滚方式：新机上的东西都可以直接停掉 / 删除，旧机没动。
- 做了什么：
  1. 用户：删除镜像自带的 `admin`；新建 `www`(1000)、`nyh-notify`(999)、`nyh-wechat-mp`(994)、`shared-redis`(993)、`redis7480`(992)。
  2. apt 装 nginx 1.26.3、supervisor、certbot、fail2ban、logrotate 等；Docker CE 29.7.2（阿里云内网源，GPG 公钥从 download.docker.com 取，指纹 `9DC8 5822 9FC7 DD38 854A E2D8 8D81 803C 0EBF CD88`）；Tailscale 1.104.5。
  3. Docker `daemon.json`：`bip 172.17.0.1/16`（应用里写死了 172.17.0.1），`default-address-pools 10.210.0.0/16 /24`。**原因**：新机内网是 `172.21.0.0/18`、RDS 在 `172.31.x`，docker 默认池会挑 172.18–31 的 /16，撞上就会把网关或 RDS 的路由劫持掉。
  4. Tailscale：节点 `nyh-prod-2026`（`100.113.16.89`），`--advertise-exit-node --accept-dns=false`，IP 转发已开。用户已授权登录。
  5. **DNS 被 Tailscale 搞坏（已修）**：`tailscale up` 之后阿里云 VPC DNS `100.100.2.136/138` 的应答被 Tailscale 的 `ts-input` 链丢弃（源地址在 100.64/10），所有域名解析卡死。照搬旧机的 `fix-aliyun-dns-vs-tailscale.service`（DNS 改用 223.5.5.5 / 223.6.6.6 / 8.8.8.8），在它之前创建的容器全部重建以拿到新的 resolv.conf。
  6. PHP：自建镜像 `nyh/php74:7.4.33`、`nyh/php82:8.2.35`（debian:trixie + Sury），`/opt/stacks/php/`，`php74-fpm` :9074、`php82-fpm` :9082，host 网络；`php74-worker`（9 个队列进程）在 compose profile `worker` 里，未启动。php.ini / FPM 池参数按旧机导出值；模块与旧机对比无缺失。
     - 旧机 `date.timezone = PRC` 在 Debian 13 无效（会退回 UTC），改成 `Asia/Shanghai`，镜像另装 `tzdata-legacy`。
     - **Sury 的 PHP-FPM 构建内置 "Secure DNS Telemetry"**（`/usr/lib/php/php-common.mk`：`TELEMETRY_HOST=telemetry.sury.org`、端口 53），启动时会联系 `telemetry.sury.org`，没有关闭开关；CLI 二进制里没有。容器 `extra_hosts` 把它指向 `127.0.0.1`，数据不会出去。
     - `/usr/local/bin/php74`、`php82` 是包装脚本（`docker exec -u www -w $PWD`），cron 和 CI 的 `php74 think …` 不用改。
  7. Redis 7480：容器 `redis-7480`（`redis:8.0.5`，`/opt/stacks/redis-7480/`），配置来自旧机（密码不变），以 `redis7480` 用户运行，端口发布 `127.0.0.1:7480` 与 `172.17.0.1:7480`。数据目录放 `/opt/stacks/redis-7480/data`，不放 `/www/docker`（迁移 rsync 带 `--delete`）。
  8. nginx：`scripts/convert-baota-nginx.py` 把宝塔 26 个站点转写到 `/etc/nginx/nyh/`（仓库 `nyh-prod-2026/nginx/`），去掉 lua well-known、site_total、WAF，ACME 统一走 `/var/www/letsencrypt`；证书 27 套 + `/etc/letsencrypt` 由旧机直接推送。`nginx -t` 通过并启动。
  9. 首轮 rsync（旧机经临时密钥推送，`from="47.239.167.8"` 限制）：`/www/wwwroot` 9.1G 等，镜像 3.5G；16:38–16:56。
  10. 起了：`php74-fpm`、`php82-fpm`、`redis-7480`、`shared-redis`（新 UID 重建）、`acquilang-admin`、`richer-web` + `richer-nginx`（先建外部网络 `richer_strategy_plus_network` 177.10.0.0/16）、`archery`、`nyh-wechat-mp`。
     **没起（有定时逻辑，U5 再起）**：`php74-worker`、宿主机 supervisor（10 个 line-* + nyh-notify）、`yunshu-api`（reminder.scheduler）、`acquilang-backend`（`ENABLE_METRICS_SCHEDULER=true`）、`richer-engine` / `richer-gateway`（策略 / 行情告警）、`richer-web-1`（反代依赖 engine）、`guagua-api`（每分钟轮询 push_jobs）、`/etc/cron.d/nyh-tasks`（全部 `#OFF#`）、nyh-wechat-mp watchdog timer。
  11. 轻量服务器防火墙加 443/udp（HTTP/3）、41641/udp（Tailscale）；8080（do1-relay 只允许 tailnet）、7480 不对公网开放。
- 验证：
  - 25 个域名在新机 `--resolve 127.0.0.1` 下与旧机基准逐行对比：全部 PHP 站点及 smith、duowei、admin-al、m-al 的状态码、关键响应头、证书**完全一致**；ddricher.ai / gateway / api-al / bnsg API / guagua 为 502（后端按计划未起）；fa.nanyahui.com 不再建站（403）。
  - PHP 容器经 ThinkPHP 只读查询 RDS：`wq_url`、`jobs` 积压 0 正常；FPM 启动 1.6s。
  - nyh-wechat-mp `/healthz`：pg / redis 正常，rules=6。
  - Python venv（3.13.5）可导入 `nyh_line`；nyh-notify、guagua-api 二进制可运行。
  - Tailscale：到 do-1 直连，sub2api 返回 200。mas-sit 不通，旧机也不通；菜苗苗 SIT 反代早已不在，`cmm-sit-healthz` 不再迁移。

## 2026-11-10 15:55 CST - 内网互通后打通 RDS PostgreSQL

- 服务器：`nyh-prod-2026`、RDS `pgm-j6cf5kaej216sx0z`
- 操作人：用户在控制台开通轻量服务器「内网互通」（关联 `vpc-j6cy0gudplcfwatq8i43f`）；`Claude` 加白名单并验证
- 原因：迁移计划 U1-2，新机要连 nyh-prod 各业务共用的 RDS PG。
- 影响：RDS 新增白名单分组 `swas_nyh2026` = `172.21.63.219`（新机内网 IP），现有分组没动；新机装了 `postgresql-client`（17.11）。
- 回滚方式：`aliyun rds ModifySecurityIps --profile default --DBInstanceId pgm-j6cf5kaej216sx0z --DBInstanceIPArrayName swas_nyh2026 --SecurityIps 172.21.63.219 --ModifyMode Delete`。
- 验证：
  - 只开内网互通、没加白名单时，`nc 172.31.138.209 5432` 仍然超时（RDS 对不在白名单的来源直接丢包，不是拒绝）。
  - 加白名单后 `nc` 成功；用不存在的账号 `conn_probe` 登录返回 `password authentication failed`，说明已经走到 PG 认证这一步。域名 `pgm-j6cf5kaej216sx0z.pg.cnhk.rds.aliyuncs.com` 在新机解析为 `172.31.138.209`，和旧机一致，应用配置不用改。

## 2026-11-10 14:30–14:45 CST - 核对内存；重装适配 6.12 内核的云盾 Aegis

- 服务器：`nyh-prod-2026`
- 操作人：`Claude`（用户要求）
- 原因：用户指出套餐是 16G 内存，档案里写的 14G 不对；并要求 Debian 13 升级完成后把云盾装回去，装适配当前内核的版本。
- 影响：空机器；为验证开机自启重启 1 次。
- 备份 / 回滚：快照 `s-j6ch07g86tunb409g1tf`（`debian13-baseline-20261110`，装云盾前，已 `accomplished`）。
- 内存核对：套餐 `swas.s.c4m16s80b1.linux` 就是 16G。`lsmem` 在线内存 15.5G，`MemTotal` 15569516 kB；`crashkernel` 按 `4G-16G:256M` 预留了 256M，再扣掉固件 / PCI 地址空间，`free -h` 按 GiB 显示成 `14Gi`。内存没有少，是之前档案写错了，已改正。
- 做了什么：
  1. 下载并读过官方脚本 `http://update2.aegis.aliyun.com/download/install.sh`（阿里云实例内免安装密钥，自动绑定所属账号）和 `AliAqsInstall_64.sh`（需要控制台密钥，没用），存到 `/root/aegis-install/`。
  2. 执行 `bash install.sh`（日志 `/root/aegis-install/install.log`），退出码 0，`Aegis successfully installed`。客户端自更新到 `aegis_11_37`，自己写了 `/etc/systemd/system/aegis.service` 并 enable，删掉了安装脚本放的 `/etc/init.d/aegis`。
  3. `systemctl daemon-reload` 后重启，验证开机自启。
- 内核适配：`AliYunDunUpdate` 会按运行中的内核下发组件。6.12.116 上没有 `.ko`，**不加载 `AliSecGuard` 内核模块**，改用 eBPF（`AliYunDunMonitor` 持有 89 个 bpf fd），`/proc/sys/kernel/tainted` = 0。不需要我们手动挑版本。
- 验证（重启后）：
  - `systemctl is-system-running` = `running`，无失败 unit；`aegis` / `aliyun` 都是 `active`；`AliYunDunUpdate`、`AliYunDun`、`AliYunDunMonitor` 三个进程开机即起。
  - `journalctl -b -p err` 除已知可忽略项外无新报错。
  - `aliyun sas DescribeCloudCenterInstances`：`InternetIp 8.217.145.133`、`ClientStatus online`、`Kernel 6.12.116+deb13-amd64`。

## 2026-11-10 14:05–14:25 CST - 纳入仓库，卸载云盾，Debian 12 原地升级到 13

- 服务器：`nyh-prod-2026`（`root@8.217.145.133`，阿里云香港轻量服务器，实例 `a9670f44600c4671a95c2a46a795657a`）
- 操作人：`Claude`（用户要求）
- 原因：用户新购这台机器替代 `nyh-prod`，要求先能用公钥登录，再升级到 Debian 13。
- 影响：空机器，没有业务；共重启 2 次。
- 备份：
  - 快照 `s-j6cf8ldl9p1wznd46hrm`（`debian12-before-upgrade`，升级前）
  - 服务器：`/root/.ssh/authorized_keys.bak.20261110`（原为空）、`/root/grub.default.bak`、`/root/grub.default.pre-efi.bak`、`/root/sources.list.bookworm.bak`
  - 本机：`~/.ssh/config.bak.20261110`
- 回滚方式：`aliyun swas-open stop-instance` → `reset-disk --disk-id d-j6c31h3s5ffawxajzmpq --snapshot-id s-j6cf8ldl9p1wznd46hrm` → `start-instance`（`--profile default --biz-region-id cn-hongkong`），回滚后 `ssh-keygen -R 8.217.145.133`。回滚后云盾会回来。
- 做了什么：
  1. 本机公钥（`id_ed25519` / root / `ecs-user` / `admin` 等组合）全部 `Permission denied`：镜像里 root 的 `authorized_keys` 是空的。在 aliyun `default` profile 下找到这台实例，云助手在线，用 `swas-open run-command` 把 `~/.ssh/id_ed25519.pub` 写入 `/root/.ssh/authorized_keys`。
  2. 本机 `~/.ssh/config` 追加 `Host nyh-prod-2026`。
  3. 按手册 2.2 节核对，镜像特征完全一致：`grub-pc` + `grub-efi-amd64-bin/signed`，无 `grub-efi-amd64`；`cloud-init` 被 hold；`GRUB_SERIAL_COMMAND="serial --speed=115200n8"`；云盾 `AliSecGuard` 模块已加载。
  4. 打快照 `debian12-before-upgrade`。
  5. 卸载云盾（用户确认）：加开机参数 `systemd.mask=aegis.service module_blacklist=AliSecGuard` 重启 → 跑官方 `uninstall.sh` / `quartz_uninstall.sh` → 删残留 → 还原 `/etc/default/grub`。
  6. `systemd-run --unit=upgrade-trixie` 后台跑 `/root/upgrade-trixie.sh`（日志 `/root/upgrade-trixie.log`），`Result=success`，无 `E:` / `dpkg: error`。
  7. 修 grub：预设 debconf（ESP `/dev/disk/by-id/virtio-j6c31h3s5ffawxajzmpq-part2`、`force_efi_extra_removable`），修正 `GRUB_SERIAL_COMMAND`，`grub-pc` 换成 `grub-efi-amd64`，`grub-install --target=x86_64-efi --uefi-secure-boot --force-extra-removable`，`update-grub`。
  8. 重启前检查全部通过后重启。
  9. 打基线快照 `s-j6ch07g86tunb409g1tf`（`debian13-baseline-20261110`）。
- 验证：
  - 重启前：模块 `2.12-9+deb13u2`、`bli.mod` 存在；ESP 两处 shim 哈希 `e103c5d02657`、grub 哈希 `425ffb5b84e8` 均与包内签名文件一致；只缺允许的 `ieee1275_fb` / `vbe` / `vga`；只装 `grub-efi-amd64`，无 hold、无半安装包；`sshd -t` 通过；cloud-init `25.1.4` 能 import。
  - 重启后一次开机成功：`13.7`、`6.12.116+deb13-amd64`、`systemctl is-system-running` = `running`、无失败 unit、`cloud-init status: done`、`eth0 routable`、时钟已同步、云助手 `active`、无 `AliYunDun` 进程。`journalctl -p err` 只有手册列出的可忽略项（RETBleed、AF_VSOCK、dhclient `/bin/true`）。
- 待办：
  - 确认稳定后删除快照 `debian12-before-upgrade`。
  - 上线业务前：关 LLMNR（5355 对公网监听）、配防火墙、决定是否保留 root 直登。
