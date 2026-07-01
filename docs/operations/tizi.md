# tizi 运维时间线

## 2026-07-01 09:25 CST - 调整并立即执行 S-UI 用户流量重置

- 服务器：`tizi`
- 操作人：`Codex`
- 原因：`tizi` VPS 服务商流量重置日期为每月 30 日，需要让 S-UI 用户流量在服务商周期前一天归零；原 root crontab 为每月 1 日 23:59 重置，和服务商周期不一致。用户同时确认改完后立即执行一次重置。
- 影响：
  - root crontab 中 S-UI 用户用量归零任务从每月 1 日 23:59 改为每月 29 日 23:59。
  - 已立即执行一次 `UPDATE clients SET up = 0, down = 0;`，所有 S-UI 用户当前累计 `up/down` 归零。
  - 未重启 `s-ui`、Nginx 或系统服务，未修改防火墙。
- 回滚：
  - 定时任务回滚：`crontab /root/backup/s-ui-traffic-reset/root-crontab.before-reset-date-20260701092524.txt`
  - 数据回滚：用 `/root/backup/s-ui-traffic-reset/s-ui.db.before-immediate-traffic-reset-20260701092524` 恢复 `/usr/local/s-ui/db/s-ui.db`；注意会覆盖回滚前产生的新流量统计。
- 变更：
  - 备份 root crontab：`/root/backup/s-ui-traffic-reset/root-crontab.before-reset-date-20260701092524.txt`
  - 备份 S-UI 数据库：`/root/backup/s-ui-traffic-reset/s-ui.db.before-immediate-traffic-reset-20260701092524`
  - 将原任务 `59 23 1 * * /usr/bin/sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE clients SET up = 0, down = 0;"` 改为 `59 23 29 * * /usr/bin/sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE clients SET up = 0, down = 0;"`
  - 执行一次：`sqlite3 /usr/local/s-ui/db/s-ui.db 'UPDATE clients SET up = 0, down = 0;'`
- 验证：
  - 改动前 `clients` 汇总：`25|124036769780|357822449097`
  - `crontab -l` 已显示新任务：`59 23 29 * * /usr/bin/sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE clients SET up = 0, down = 0;"`
  - 立即重置后 `clients` 汇总：`25|0|0`

## 2026-06-19 15:00 CST - 安装 vnstat 流量统计（监控方案第一步）

- 服务器：`tizi`
- 操作人：`Claude`
- 原因：实施 `tizi-traffic-accounting-plan-2026-06-19.md` 第一步，部署网卡级精确流量统计，后续与 VPS 面板对账并接 nftables 计数器 + Telegram 告警。
- 影响：
  - 安装 `vnstat-2.9`（EPEL 源，`epel-release` 已装、完整 `epel` 仓库原为 disabled，安装时用 `--enablerepo=epel` 临时启用，未持久改动 repo 状态）。
  - `systemctl enable --now vnstat`，服务 active 且开机自启。
  - vnstat 只读 `/proc/net/dev` 内核计数器，不抓包、不过流量，对转发性能无影响。
  - 已识别接口 `eth0`、`tailscale0`；刚装数据库为空（`Not enough data available yet`），需自行积累。
- 回滚：`systemctl disable --now vnstat && dnf remove -y vnstat`（数据库在 `/var/lib/vnstat/`，如需彻底清理一并删除）。
- 验证：`systemctl is-active vnstat` → active；`vnstat --iflist` 列出 eth0/tailscale0。
- 后续：等 1~2 天积累数据后用 `vnstat -m`（月）与 VPS 面板对账，再做 nftables 计数器与 Telegram 告警。

## 2026-06-19 14:00 CST - S-UI 面板 2095 改为只监听 tailscale 接口

- 服务器：`tizi`
- 操作人：`Claude`
- 原因：用户在 `tizi` 安装并登录 tailscale（节点名 `tizi`，tailscale IP `100.90.28.83`），希望直接通过 tailscale 网络访问 S-UI 面板，取代原先「先建 SSH 隧道再访问 `http://127.0.0.1:2095/`」的方式。
- 影响：
  - S-UI 面板（`sui` 进程）监听地址从 `127.0.0.1:2095` 改为 `100.90.28.83:2095`，即只在 tailscale 接口 `tailscale0` 上监听。
  - 公网网卡 `eth0`（`74.211.103.83`）上不再有进程监听 2095，公网无法访问面板。
  - **原 SSH 隧道访问 `http://127.0.0.1:2095/` 方式失效**，以后改用 tailscale 客户端访问 `http://100.90.28.83:2095/app/`。
  - 订阅端口 2096（`subListen`）保持 `127.0.0.1` 不变，本次未动。
  - firewalld：将 `tailscale0` 接口绑定到内置 `trusted` zone（target ACCEPT，放行 tailscale 网络内所有入站）。公网 `eth0`/`public` zone 策略不变，仍只开 `ssh/80/443/8443`。
  - 未改动 nginx、443 数据面（翻墙连接不受影响）。
  - 重启 `s-ui` 期间面板短暂中断约几秒，xray/sing-box 数据面不受影响。
- 回滚：
  1. `cp -a /usr/local/s-ui/db/s-ui.db.before-tailscale-panel-20260619 /usr/local/s-ui/db/s-ui.db`
  2. 或直接 `sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE settings SET value=\"127.0.0.1\" WHERE key=\"webListen\";"`
  3. `systemctl restart s-ui`
  4. firewalld 回滚：`firewall-cmd --permanent --zone=trusted --remove-interface=tailscale0 && firewall-cmd --reload`
- 变更：
  - 备份数据库：`cp -a /usr/local/s-ui/db/s-ui.db{,.before-tailscale-panel-20260619}`
  - `systemctl stop s-ui`
  - `sqlite3 /usr/local/s-ui/db/s-ui.db "UPDATE settings SET value=\"100.90.28.83\" WHERE key=\"webListen\";"`
  - `systemctl start s-ui`
  - `firewall-cmd --permanent --zone=trusted --add-interface=tailscale0 && firewall-cmd --reload`
- 验证：
  - `ss -tlnp | grep 2095` 显示监听地址为 `100.90.28.83:2095`（原为 `127.0.0.1:2095`）
  - `sui setting -show` 显示 `Panel IP: 100.90.28.83`
  - 本机探测公网 `74.211.103.83:2095` → `Connection refused`（公网不可达，符合预期）
  - `firewall-cmd --get-zone-of-interface=tailscale0` 返回 `trusted`
  - 用户本机（tailscale IP `100.92.181.15`）浏览器访问 `http://100.90.28.83:2095/app/` 正常打开面板
- 说明：
  - 用户的两个客户端设备 tailscale IP 为 `100.92.181.15`、`100.108.64.126`。本次未在 firewalld 上按 IP 限制 —— 因 `sui` 只在 tailscale 接口监听，公网已天然隔离，tailscale 网络内设备均可访问面板，符合用户「不限制 tailscale 网络内 IP」的要求。
  - 排查中踩坑：只改 `webListen` 后客户端访问仍 `ERR_CONNECTION_REFUSED`。根因是 `tailscale0` 接口此前 `no zone`，入站走默认 `public` zone，而 2095 未在 public 放行；tizi 本机能连是因走 loopback 不过 firewalld。把 `tailscale0` 划入 `trusted` zone 后即通。面板路径为 `/app/`，须访问 `http://100.90.28.83:2095/app/`，根路径 `/` 会失败。
  - `webListen=127.0.0.1` 自面板搭建起就是默认状态，并非历史某次改动结果；db 目录下 `s-ui.db.before-localhost-panel-20260502` 备份来历文档未记录，用户推测为定期重置用户用量前的备份，与本次无关。

## 2026-05-20 10:29 CST - litellm-us DNS 流量切出到 rao-tizi

- 服务器：`tizi`
- 操作人：`Codex`
- 原因：用户已在 Cloudflare 将 `litellm-us.konghai.me` 切到 `64.64.253.141`，由 `rao-tizi` 接管反向代理流量。
- 影响：未修改 `tizi` 上的 Nginx、firewalld、证书、crontab 或 `s-ui`；`tizi` 仍保留原 Nginx 服务作为短期 DNS 回滚目标。
- 回滚：将 `litellm-us.konghai.me` DNS 改回 `tz.skysms.xyz` 或 `74.211.103.83`。
- 变更：
  - 本机未执行配置变更。
- 验证：
  - `nyh-prod` 已解析 `litellm-us.konghai.me` 到 `64.64.253.141`
  - `rao-tizi` 上已签发新证书并通过五个代理路径验证
- 后续：
  - 切换稳定前保留 `tizi` 上原 Nginx 配置和证书。
  - 若要停用 `tizi` 上的 Nginx，需要再次确认后执行。

## 2026-05-20 09:51 CST - 为 litellm-us 反向代理迁移创建回滚备份

- 服务器：`tizi`
- 操作人：`Codex`
- 原因：`tizi` 流量接近限额并存在关机风险，准备将 `litellm-us.konghai.me` 的 Nginx 反向代理迁移到备用代理 `rao-tizi`。
- 影响：只创建备份并读取状态；未修改 Nginx、firewalld、crontab、DNS 或 `s-ui`。
- 回滚：本次未改运行状态，不需要服务级回滚。若后续迁移步骤需要恢复 `tizi` 原配置，可使用 `/root/backup/litellm-migration-20260520095153/` 中的备份。
- 变更：
  - 创建迁移前备份目录：`/root/backup/litellm-migration-20260520095153/`
  - 备份 `/etc/nginx` 到 `etc-nginx.tgz`
  - 备份 `litellm-us.konghai.me` 的 Let's Encrypt live/archive 证书与 SSL 参数到 `etc-letsencrypt-litellm.tgz`
  - 记录 firewalld、root crontab、监听端口和 `nginx -T` 输出
- 验证：
  - `nginx` 仍为 `active` / `enabled`
  - `nginx -t` 通过
  - `80/tcp` 和 `8443/tcp` 仍由 Nginx 监听
  - `443/tcp` 仍由 `sui` 监听
  - 当前证书有效期仍为 `2026-02-24 09:59:46 CST` 到 `2026-05-25 09:59:45 CST`
- 后续：
  - DNS 切换前保留 `tizi` 上现有 Nginx 服务作为回滚目标。
  - 切换稳定前不删除 `tizi` 上的配置、证书或日志。
