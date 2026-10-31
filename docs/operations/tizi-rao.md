# tizi-rao 运维时间线

> 2026-10-31 起由 `rao-tizi` 改名为 `tizi-rao`（同一台 VPS，公网 `64.64.253.141`）。以下 10-31 之前的条目里写的 `rao-tizi` 都指这台机器的旧系统（Rocky 9.7 + S-UI）。

## 2026-10-31 12:00 CST - 整装为 Debian 13 + 3x-ui，沿用旧 REALITY 身份，恢复 LLM 反代，改名 tizi-rao

- 服务器：`tizi-rao`（原 `rao-tizi`，公网 `64.64.253.141`，Tailscale `100.75.71.21`）
- 操作人：`Claude`（用户已在服务商控制台重装为 Debian 13，要求按统一格式改名为 `tizi-rao`，流程同 `tizi-kh`）
- 原因：从 Rocky 9.7 + S-UI 1.4.1 统一到 Debian 13 + 3x-ui + Xray；同时这台是 `litellm-us.konghai.me`（CNAME `rao-tz.skysms.xyz`）实际所在的机器，nginx `:8443` 的 LLM API 反代要原样恢复。
- 选型：和 `tizi-kh` 相同（沿用旧身份、恢复 Tailscale state、升级内核并重启、SSH 只用密钥、时区上海、fail2ban + vnstat）。另外：
  - REALITY 伪装站沿用 `iosapps.itunes.apple.com`
  - 分享地址：旧入站没设 External，旧链接主机名是 IP（`100.75.71.21`、`64.64.253.141`、`127.0.0.1`）。新入站设成 `rao-tz.skysms.xyz`。已在用旧链接的客户端连的是同一个 IP，不受影响
  - 恢复 LLM 反代：nginx + certbot（nginx 插件），证书 lineage `litellm-us-konghai-me-20260520`（有效期到 2026-12-16），过期的旧 lineage `litellm-us.konghai.me` 一并放回，它没有续期配置，不会触发续期
- 备份：重装前全量备份见下方 10:18 条目（本机 `_backups/rao-tizi-pre-reinstall-20261031/`）；机上另有 `/root/x-ui.db.fresh-install-20261031`、`/root/vnstat.db.fresh-20261031`、`/root/llm-proxy.conf.bak.20261031`、`/etc/letsencrypt.debian-default.20261031`、`/etc/network/interfaces.bak.20261031`、`/etc/hosts.bak.20261031`
- 回滚方式：
  - 面板 / 入站：`systemctl stop x-ui`，用备份库覆盖 `/etc/x-ui/x-ui.db`，再 `systemctl start x-ui`
  - LLM 反代：`cp /root/llm-proxy.conf.bak.20261031 /etc/nginx/conf.d/llm-proxy.conf && nginx -t && systemctl reload nginx`
  - SSH 密码登录：删除 `/etc/ssh/sshd_config.d/00-hardening.conf` 后 `systemctl reload ssh`
  - 回到 Rocky + S-UI：只能重装系统，再从本机备份恢复
- 变更时序：
  1. 本机 `~/.ssh/config` 改为 `Host tizi-rao rao-tizi`（改前备份 `~/.ssh/config.bak.20261031-rao`），清理 `64.64.253.141` / `100.75.71.21` 的旧 known_hosts。这次控制台导入的公钥正确，直接用 `id_ed25519` 就登录上了，没用到密码
  2. `hostnamectl set-hostname tizi-rao`，`/etc/hosts` 同步；镜像同样写了不存在的 `auto eth1`，改成 `allow-hotplug eth1`（重启后 `systemctl --failed` 为空）
  3. 时区 `Asia/Shanghai`；locale `en_US.UTF-8`；`apt full-upgrade`（内核 `6.12.88` → `6.12.113`，修复 CVE-2026-98432）；装 `curl sqlite3 ufw fail2ban python3-systemd vnstat socat jq`；SSH `00-hardening.conf`；fail2ban `sshd` jail 用 systemd backend；重启
  4. Tailscale 1.104.4：放回旧 state，IP 仍是 `100.75.71.21`；`tailscale set --hostname=tizi-rao`，MagicDNS 名已自动变成 `tizi-rao.taila93443.ts.net`
  5. ufw：default deny；放行 `22/tcp`、`443/tcp`、`80/tcp`（certbot HTTP-01 / 跳转）、`8443/tcp`（LLM 反代）、`tailscale0` 全通
  6. 3x-ui v3.11.0 + Xray 26.10.21，非交互安装；面板 `100.75.71.21:2095`，`subListen=127.0.0.1`。安装日志 `/root/3x-ui-install.log` 含面板账密，已 `chmod 600`
  7. 用 API 建入站 remark `tizi-rao`（VLESS + REALITY `:443`，flow `xtls-rprx-vision`，`minClientVer=1.0.0`，sockopt `UseIPv4`），payload 由 S-UI 备份生成；停服务改库：`share_addr=rao-tz.skysms.xyz`，迁入本期已用流量（11 个客户端有用量）
  8. root crontab：`59 23 11 * * sqlite3 /etc/x-ui/x-ui.db "UPDATE client_traffics SET up = 0, down = 0;"`（对齐服务商每月 11 日重置）
  9. vnstat 2.13 恢复旧库，历史月度流量接上
  10. nginx 1.26 + certbot：放回 `/etc/letsencrypt`（保留 live → archive 符号链接）和 `conf.d/llm-proxy.conf`；`listen 8443 ssl http2` 改成 `listen 8443 ssl;` + `http2 on;`（新版 nginx 不再推荐旧写法）；`certbot.timer` 已启用
- 验证：
  - `uname -r` = `6.12.113+deb13-amd64`；`x-ui`、`tailscaled`、`fail2ban`、`vnstat`、`ufw`、`cron`、`nginx`、`certbot.timer` 均 active，`systemctl --failed` 为空
  - Xray 运行配置：15 个客户端（等于库里启用数），24 个 shortId，target `iosapps.itunes.apple.com:443`，`minClientVer=1.0.0`；启用 UUID + 私钥 + shortId 的哈希和备份一致
  - 公网 TLS 探针：SNI `iosapps.itunes.apple.com` 返回 `CN=itunes-ssl.itunes.apple.com`
  - 端到端：本机 Xray 以 `空海测试-2` 身份连 `rao-tz.skysms.xyz:443`，出口 IP `64.64.253.141`，Google 204、GitHub 200
  - LLM 反代：`https://litellm-us.konghai.me:8443/{openai,anthropic,xai,groq/openai}/v1/models` 不带 key 返回上游 401，`cerebras` 返回 429（上游限流），说明请求到达了上游；`:80` 301 跳 HTTPS；证书 `CN=litellm-us.konghai.me`，到期 2026-12-16
  - `certbot renew --dry-run --cert-name litellm-us-konghai-me-20260520` 成功
  - 公网 2095 / 2096 不通；密码登录被拒；公网和 Tailscale 两条 SSH 路径都能用密钥登录
- 面板入口：`http://100.75.71.21:2095/<webBasePath>/`，账密在机上 `/etc/x-ui/install-result.env`（600），**不入库**
- 遗留：客户端 `饶家里路由器` 本期已用 254 / 300 GiB，11-11 才月清，可能提前用完被自动停用

## 2026-10-31 10:18 CST - 整装 Debian 13 前全量备份用户与配置到本机

- 服务器：`rao-tizi`
- 操作人：`Claude`
- 原因：用户计划把 `rao-tizi` 从 Rocky 9.7 整装为 Debian 13，重装会抹掉整盘（包括 `/root/backup`），要先把用户与配置拉回本机。
- 影响：只读。在 `/root` 下生成备份目录和 tar 包，没有改服务、配置、防火墙和 crontab，也没有重启。
- 回滚方式：无服务器变更。备份包在服务器 `/root/rao-tizi-pre-reinstall-20261031-101809*`，可以删，重装时也会一起被抹掉。
- 做了什么：
  - 新增脚本 `scripts/backup-proxy-node-pre-reinstall.sh`，执行方式：`ssh rao-tizi 'bash -s' -- rao-tizi < scripts/backup-proxy-node-pre-reinstall.sh`
  - 本机位置（`_backups/` 已 gitignore，含密钥，不入库）：`_backups/rao-tizi-pre-reinstall-20261031/rao-tizi-pre-reinstall-20261031-101809.tar.gz`（23M）+ `.sha256`，同目录下有解包副本
  - 备份内容：
    - S-UI 1.4.1 / sing-box v1.13.4：用 `sqlite3 .backup` 做在线一致性备份；`clients` / `inbounds` / `tls` / `settings` / `users` 等表另外导出为 JSON（体积大的 `stats` / `changes` 只在 db 里）
    - 账户：`/etc/passwd`、`shadow`、`group`、`sudoers`（没有 UID≥1000 的普通用户）；`/root/.ssh`；`/etc/ssh` 整目录（含主机密钥）
    - nginx（`:8443` LLM API 反代 `llm-proxy.conf`）、`/etc/letsencrypt`（`litellm-us.konghai.me`）、firewalld、sysctl（bbr/fq、fastopen、rp_filter）、自定义 systemd unit、root crontab、`/var/lib/tailscale`、`/var/lib/vnstat`、`/opt`、`/root` 下的小文件（旧 S-UI 库副本和二进制只留清单）
    - 现场快照：`ip addr`/`route`、`ss`、`ps`、`rpm -qa`、已启用服务列表
    - `/etc/letsencrypt/live` 下有两套 lineage，nginx 实际用的是 `litellm-us-konghai-me-20260520`（`litellm-us.konghai.me` 是旧的）；续期靠 `certbot-renew.timer`，不在 crontab 里
- 验证：
  - 本机 `shasum -a 256 -c` OK，解包后 S-UI 库 `PRAGMA integrity_check` = `ok`
  - 客户端数 18（启用 15），和线上一致；入站只有 1 个 `vless-reality`；TLS 记录 1 条
  - `authorized_keys` 只有一把 `ssh-ed25519 konghai@konghai.me`
  - 线上 `/root/.ssh` 目录权限是 `600`（没有 x 位），解包后本机进不去；本机副本已 `chmod 700`，包里的文件完整
- 重建要点（Debian 13）：
  - 网络：eth0 走 DHCP，没有其它网卡配置要迁
  - Tailscale：先停 `tailscaled`，把备份的 `/var/lib/tailscale` 放回去再启动，可以保留原节点身份和 `100.75.71.21`（面板 `webListen` 绑的是这个 IP）。如果改成重新登录，要在控制台删掉旧节点，面板监听也要改成新 IP
  - SSH：放回 `/etc/ssh/ssh_host_*`，客户端就不会报 host key 变更
  - 防火墙：Debian 用 ufw，对应现有规则：22、80、443、8443/tcp 对公网，`tailscale0` 全放行
  - 流量月清 cron：每月 11 日 23:59
  - 面板选型（照 S-UI 原样恢复，还是按 `docs/runbooks/proxy-node-reinstall-upgrade.md` 迁到 3x-ui）等重装时再定

## 2026-10-31 09:24 CST - 只读：CVE-2026-98432 内核漏洞暴露面排查

- 服务器：`rao-tizi`
- 操作人：`Claude`
- 原因：CVE-2026-98432（IPv4 TCP use-after-free，Anthropic 演示了对 MPTCP 监听服务器远程拿 root）公开，需要确认各服务器是否受影响。
- 影响：只读（`uname`、`net.mptcp.enabled`、`ss -Mlnp`、已装内核列表）。没升级、没重启。
- 回滚方式：无服务器变更，无需回滚。
- 结果：Rocky 9.7，运行 `5.14.0-611.49.1`，受影响；`net.mptcp.enabled=0`，没有 MPTCP 监听，但 bug 在通用 TCP 路径，仍有风险。RHEL 系还没出修复包。
- 汇总与建议：`docs/reviews/2026-10-31-cve-2026-98432-kernel-exposure.md`

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`rao-tizi`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN（轻量扫）。ioc=0。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-06-19 15:00 CST - 安装 vnstat 流量统计（监控方案第一步）

- 服务器：`rao-tizi`
- 操作人：`Claude`
- 原因：实施 `rao-tizi-traffic-accounting-plan-2026-06-19.md` 第一步，与 `tizi` 同步部署网卡级流量统计。
- 影响：
  - 安装 `vnstat-2.9`（EPEL 源，安装时用 `--enablerepo=epel` 临时启用 disabled 的完整 epel 仓库，未持久改动 repo）。
  - `systemctl enable --now vnstat`，服务 active 且开机自启。
  - 只读 `/proc/net/dev`，不抓包，对转发与 nginx 透传性能无影响。
  - 已识别接口 `eth0`、`tailscale0`；数据库刚建为空，需自行积累。
- 回滚：`systemctl disable --now vnstat && dnf remove -y vnstat`（数据库在 `/var/lib/vnstat/`）。
- 验证：`systemctl is-active vnstat` → active；`vnstat --iflist` 列出 eth0/tailscale0。
- 后续：积累数据后与 VPS 面板对账，再做 nftables 计数器与 Telegram 告警。

## 2026-06-19 14:20 CST - S-UI 面板 2095 改为只监听 tailscale 接口

- 服务器：`rao-tizi`
- 操作人：`Claude`
- 原因：与主代理 `tizi` 做相同配置——在 `rao-tizi` 安装并登录 tailscale（tailscale IP `100.75.71.21`），希望直接经 tailscale 网络访问 S-UI 面板，取代原先「先建 SSH 隧道再访问 `http://127.0.0.1:2095/`」的方式。参见 `tizi.md` 2026-06-19 同名记录。
- 影响：
  - S-UI 面板（`sui` 进程）监听地址从 `127.0.0.1:2095` 改为 `100.75.71.21:2095`，只在 tailscale 接口 `tailscale0` 上监听。
  - 公网网卡（公网 IP `64.64.253.141`）上不再有进程监听 2095，公网无法访问面板。
  - **原 SSH 隧道访问 `http://127.0.0.1:2095/` 方式失效**，以后改用 tailscale 客户端访问 `http://100.75.71.21:2095/app/`。
  - 订阅端口 2096（`subListen`）保持 `127.0.0.1` 不变，本次未动。
  - firewalld：将 `tailscale0` 接口绑定到内置 `trusted` zone（target ACCEPT，放行 tailscale 网络内所有入站）。公网 `public` zone 策略不变，仍只开 `ssh/80/443/8443`。
  - 未改动 nginx、443 数据面（翻墙/反代连接不受影响）。
  - 重启 `s-ui` 期间面板短暂中断约几秒，数据面不受影响。
- 回滚：
  1. `cp -a /usr/local/s-ui/db/s-ui.db.before-tailscale-panel-20260619 /usr/local/s-ui/db/s-ui.db`
  2. 或直接 `sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE settings SET value=\"127.0.0.1\" WHERE key=\"webListen\";"`
  3. `systemctl restart s-ui`
  4. firewalld 回滚：`firewall-cmd --permanent --zone=trusted --remove-interface=tailscale0 && firewall-cmd --reload`
- 变更：
  - 备份数据库：`cp -a /usr/local/s-ui/db/s-ui.db{,.before-tailscale-panel-20260619}`
  - `systemctl stop s-ui`
  - `sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE settings SET value=\"100.75.71.21\" WHERE key=\"webListen\";"`
  - `systemctl start s-ui`
  - `firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 && firewall-cmd --reload`
- 验证：
  - `ss -tlnp | grep 2095` 显示监听地址为 `100.75.71.21:2095`（原为 `127.0.0.1:2095`）
  - `sui setting -show` 显示 `Panel IP: 100.75.71.21`
  - 本机探测公网 `64.64.253.141:2095` → `Connection refused`（公网不可达，符合预期）
  - `firewall-cmd --get-zone-of-interface=tailscale0` 返回 `trusted`
  - 从客户端 tailscale 设备访问 `http://100.75.71.21:2095/app/`（面板路径为 `/app/`，根路径 `/` 会失败）
- 说明：经验来自 `tizi` 同日操作——`tailscale0` 默认 `no zone`，仅改监听 IP 不够，必须把接口划入 `trusted` zone，否则 tailnet 客户端被 firewalld 拒（`ERR_CONNECTION_REFUSED`），而本机自连因走 loopback 不过 firewalld 会有「已 OK」假象。

## 2026-06-11 12:25 CST - 调整 S-UI 用户流量月度重置时间

- 服务器：`rao-tizi`
- 操作人：`Codex`
- 原因：服务商对该服务器的流量重置时间为每月 11 日，原 S-UI 用量重置定时任务在每月 1 日执行，和服务商周期不一致。
- 影响：root crontab 中 S-UI 用户用量归零任务从每月 1 日 23:59 改为每月 11 日 23:59；未重启服务，未修改当前数据库用量数据。
- 回滚：
  - 恢复修改前 root crontab：`crontab /root/crontab.bak.20260611-122514`
  - 或将任务日期改回每月 1 日：`59 23 1 * * /usr/bin/sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE clients SET up = 0, down = 0;"`
- 变更：
  - 修改前备份 root crontab 到 `/root/crontab.bak.20260611-122514`
  - 将原任务 `59 23 1 * * /usr/bin/sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE clients SET up = 0, down = 0;"` 改为 `59 23 11 * * /usr/bin/sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE clients SET up = 0, down = 0;"`
- 验证：
  - `crontab -l` 已显示新任务：`59 23 11 * * /usr/bin/sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE clients SET up = 0, down = 0;"`

## 2026-05-20 10:29 CST - 接管 litellm-us DNS 流量并签发正式证书

- 服务器：`rao-tizi`
- 操作人：`Codex`
- 原因：用户已在 Cloudflare 将 `litellm-us.konghai.me` 改为 A 记录 `64.64.253.141`，生产服务器 `nyh-prod` 解析和访问已切到 `rao-tizi`。
- 影响：`litellm-us.konghai.me:8443` 正式由 `rao-tizi` 上的 Nginx 承载；`s-ui` 仍占用 `443/tcp`，未修改或重启。
- 回滚：
  - DNS 回滚到旧值 `tz.skysms.xyz` 或 `74.211.103.83`
  - 如需回滚证书路径，可恢复 `/etc/nginx/conf.d/llm-proxy.conf.bak.202605201029` 后执行 `nginx -t && systemctl reload nginx`
- 变更：
  - 使用 certbot 为 `litellm-us.konghai.me` 正式签发新证书，lineage 为 `litellm-us-konghai-me-20260520`
  - 将 Nginx 证书路径从复制证书切换到 `/etc/letsencrypt/live/litellm-us-konghai-me-20260520/`
  - 备份切换前 Nginx 配置到 `/etc/nginx/conf.d/llm-proxy.conf.bak.202605201029`
  - 移走第一次同名签发失败留下的无效 renewal 配置：`/etc/letsencrypt/renewal/litellm-us.konghai.me.conf.invalid.202605201032`
- 验证：
  - `nyh-prod` 解析 `litellm-us.konghai.me` 为 `64.64.253.141`
  - `nyh-prod` 访问 `https://litellm-us.konghai.me:8443/openai/` 返回上游 `421`
  - `nyh-prod` 访问 `/anthropic/`、`/cerebras/`、`/xai/`、`/groq/` 分别返回上游 `404`、`405`、`421`、`404`
  - 端口证书 issuer 为 Let's Encrypt `E7`，有效期为 `2026-05-20 09:31:17 CST` 到 `2026-08-18 09:31:16 CST`
  - `certbot certificates` 仅列出有效 lineage `litellm-us-konghai-me-20260520`
  - `certbot renew --dry-run --cert-name litellm-us-konghai-me-20260520 --no-random-sleep-on-renew` 成功
  - `nginx -t` 通过，Nginx 仍只监听 `80/tcp` 和 `8443/tcp`，`443/tcp` 仍由 `sui` 监听
- 后续：
  - 继续观察 Nginx access/error log 和 `certbot-renew.timer`。
  - 切换稳定后如需停用 `tizi` 上 Nginx，需要另行确认。

## 2026-05-20 09:51 CST - 预置 litellm-us 反向代理备用入口

- 服务器：`rao-tizi`
- 操作人：`Codex`
- 原因：准备接管 `tizi` 上的 `litellm-us.konghai.me` Nginx 反向代理，降低主代理服务器流量超额关机风险。
- 影响：安装 Nginx / certbot，新增 Nginx 服务监听 `80/tcp` 和 `8443/tcp`，firewalld 新增放行 `80/tcp` 和 `8443/tcp`；未修改 DNS，未停止或重启 `s-ui`。
- 回滚：
  - 停止并禁用 Nginx：`systemctl disable --now nginx`
  - 移除新增防火墙端口：`firewall-cmd --permanent --remove-port=80/tcp`、`firewall-cmd --permanent --remove-port=8443/tcp` 后 reload
  - 如需恢复执行前状态，参考备份目录 `/root/backup/litellm-migration-20260520095153/`
- 变更：
  - 创建迁移前备份目录：`/root/backup/litellm-migration-20260520095153/`
  - 安装 `nginx-1.20.1`、`certbot-3.1.0`、`python3-certbot-nginx-3.1.0`
  - certbot 来自 EPEL；服务器已安装 `epel-release`，本次安装用 `--enablerepo=epel`
  - 从 `tizi` 通过 SSH 管道迁移 `/etc/nginx/conf.d/llm-proxy.conf` 和 `litellm-us.konghai.me` 当前证书文件；私钥未落到本地仓库
  - firewalld 新增放行 `80/tcp` 和 `8443/tcp`
  - 启用并启动 Nginx
  - 启用并启动 `certbot-renew.timer`
  - 新增 certbot deploy hook：`/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh`
- 验证：
  - `nginx -t` 通过
  - Nginx 为 `active` / `enabled`
  - `certbot-renew.timer` 为 `active` / `enabled`
  - Nginx 只监听 `80/tcp` 和 `8443/tcp`
  - `443/tcp` 仍由 `sui` 监听
  - firewalld 当前放行 `443/tcp 80/tcp 8443/tcp`
  - `64.64.253.141:8443` 使用 SNI `litellm-us.konghai.me` 返回复制证书，证书有效期为 `2026-02-24 09:59:46 CST` 到 `2026-05-25 09:59:45 CST`
  - 使用指定解析到 `64.64.253.141` 的预切验证结果：
    - `/openai/` 返回上游 `421`
    - `/anthropic/` 返回上游 `404`
    - `/cerebras/` 返回上游 `405`
    - `/xai/` 返回上游 `421`
    - `/groq/` 返回上游 `404`
- 后续：
  - DNS 尚未切换，正式流量仍在 `tizi`。
  - 复制证书即将在 `2026-05-25 09:59:45 CST` 到期；DNS 切到 `rao-tizi` 后必须立即用 certbot 为 `litellm-us.konghai.me` 正式签发/接管续期。
  - 当前 `certbot certificates` 尚不会列出该复制证书；正式签发后才会形成可自动续期的 certbot lineage。
