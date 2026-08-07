# tizi 运维时间线

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`tizi`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN（轻量扫）。ioc=0。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-07-10 02:02 CST - 用户分享链接改用域名 tz.skysms.xyz

- 服务器：`tizi`
- 操作人：`Grok`
- 原因：域名 `tz.skysms.xyz` 已指向公网 `74.211.103.83`；此前 S-UI 未配置 External 地址，复制链接多为裸 IP 或面板 Host（`127.0.0.1` / Tailscale IP），需手动改域名，运维成本高。与 `tizi-cyp`（`cyp-tz.skysms.xyz`）对齐做法。
- 影响：
  - 入站 `vless-reality` 的 **`addrs`（External）** 设为 `tz.skysms.xyz:443`。
  - `out_json.server` 由 `74.211.103.83` 改为 `tz.skysms.xyz`。
  - **全部 25 个** 用户 `links` 主机名统一改为 `tz.skysms.xyz`（原先分布：公网 IP / `127.0.0.1` / `100.90.28.83`）。
  - 曾 `systemctl restart s-ui`（配置 addrs 时）；数据面短暂中断约数秒。后续仅改 links 未再重启。
  - REALITY 密钥、UUID、面板 `webListen`、订阅监听、firewalld **未改**。
  - **已在客户端用旧链接的用户不受影响**（仍连原 IP/主机）；重新复制链接后才是域名。
- 备份：`/root/backup/tizi-share-domain-20260710020042/s-ui.db.before`
- 回滚：
  ```bash
  cp -a /root/backup/tizi-share-domain-20260710020042/s-ui.db.before /usr/local/s-ui/db/s-ui.db
  systemctl restart s-ui
  ```
- 验证：
  - DNS：`tz.skysms.xyz` → `74.211.103.83`
  - `addrs` / `out_json.server` = `tz.skysms.xyz`
  - 25 个 client links 主机均为 `tz.skysms.xyz`
  - `s-ui` active，`*:443` 监听
- 面板维护：Inbounds → `vless-reality` → External 保留 Server=`tz.skysms.xyz` Port=`443`；清空会回退为「打开面板时的 Host」。


## 2026-07-02 21:21 CST - 查询 S-UI 当日流量前 5 用户

- 服务器：`tizi`
- 操作人：`Codex`
- 原因：用户要求列出 S-UI 今天流量消耗前 5 的用户。
- 影响：只读查询 S-UI SQLite `stats` 表，未修改 S-UI、Nginx、firewalld、crontab、数据库或系统服务，未重启任何进程。
- 回滚：本次未改运行状态，不需要回滚。
- 查询口径：按服务器本地日期 `2026-07-02`，聚合 `/usr/local/s-ui/db/s-ui.db` 中 `stats` 表 `resource='user'` 的 `traffic`，按用户 `tag` 排序取前 5；`direction0`、`direction1` 沿用 S-UI 原始方向字段。
- 结果：
  - `konghai家里路由器`：`11.83 GiB`（`direction0 11.05 GiB`，`direction1 0.78 GiB`）
  - `昭姝-路由器`：`8.75 GiB`（`direction0 2.58 GiB`，`direction1 6.17 GiB`）
  - `rao-办公室路由器`：`5.99 GiB`（`direction0 4.27 GiB`，`direction1 1.72 GiB`）
  - `hong家路由器`：`5.60 GiB`（`direction0 3.25 GiB`，`direction1 2.35 GiB`）
  - `尹朋飞`：`1.06 GiB`（`direction0 1.05 GiB`，`direction1 0.01 GiB`）

## 2026-07-02 21:13 CST - 排查 S-UI 与 vnstat 今日流量统计差异

- 服务器：`tizi`
- 操作人：`Codex`
- 原因：用户发现 S-UI 面板统计值与 `vnstat` 差异较大；`vnstat` 显示 2026-07-02 当日截至排查时已使用约 74 GiB。
- 影响：只读排查，未修改 S-UI、Nginx、firewalld、crontab、数据库或系统服务，未重启任何进程。
- 回滚：本次未改运行状态，不需要回滚。
- 排查：
  - `vnstat -d` 显示 `eth0` 当日 `rx 37.70 GiB`、`tx 36.75 GiB`、合计 `74.45 GiB`；`tailscale0` 当日流量约 1 MiB，可忽略。
  - S-UI 服务为单进程 `/usr/local/s-ui/sui`，管理端监听 `127.0.0.1:2096`，数据面监听 `*:443`；未发现独立 `xray`、`sing-box`、`v2ray` 进程。
  - S-UI SQLite 表 `stats` 今日按 `resource='user'` 聚合为 `direction 0: 22.96 GiB`、`direction 1: 11.42 GiB`，合计 `34.38 GiB`。
  - `stats` 同时保存 `user`、`inbound`、`outbound` 三类资源；直接汇总所有行会得到约 `103.12 GiB`，属于重复计数，不应用来对账。
  - S-UI 日志今日有 `REALITY: processed invalid connection` 约 1249 条、`mux connection closed` 约 4782 条，这些失败/扫描连接和协议开销会被网卡统计计入，但不一定完整进入用户用量。
- 结论：
  - `vnstat` 是公网网卡 `eth0` 的双向字节口径。代理转发一次用户流量时，公网网卡通常会同时产生「目标站到服务器」和「服务器到客户端」两段字节，因此 `rx + tx` 天然接近 S-UI 用户流量的两倍。
  - 本次对账中，S-UI 用户流量 `34.38 GiB * 2 = 68.76 GiB`，与 `vnstat` 的 `74.45 GiB` 差约 `5.69 GiB`；差额主要来自协议开销、失败/扫描连接、Nginx/系统其它流量以及统计刷新时间差。
- 验证：S-UI 小时级用户流量峰值出现在 14:00-16:00（约 `3.75 GiB`、`4.07 GiB`、`3.94 GiB`），与 `vnstat -h` 同时段网卡峰值（约 `7.95 GiB`、`8.61 GiB`、`8.41 GiB`）基本呈约 2 倍关系。

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
