# rao-tizi 运维时间线

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
