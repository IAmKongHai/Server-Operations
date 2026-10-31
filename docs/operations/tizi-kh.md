# tizi-kh 运维时间线

> 2026-10-31 起由 `tizi` 改名为 `tizi-kh`（同一台 VPS，公网 `74.211.103.83`）。以下 10-31 之前的条目里写的 `tizi` 都指这台机器的旧系统（Rocky 9.7 + S-UI）。

## 2026-10-31 12:40 CST - 删除误导入的 RSA 私钥文件；Tailscale 机器名已改为 tizi-kh

- 服务器：`tizi-kh`
- 操作人：`Claude`（用户确认删除）；Tailscale 改名由用户在 admin console 完成
- 原因：处理 11:10 条目的两项遗留。
- 影响：无，不涉及任何服务。
- 回滚方式：私钥文件已用 `shred -u` 删除，不可恢复，也不需要恢复（这把私钥按已泄露处理，不再使用）。
- 做了什么：
  1. 删之前核对：`/root/authorized_keys.contained-private-key-20261031`（600，1675 字节），内容开头是 `-----BEGIN RSA PRIVATE KEY-----`
  2. `shred -u` 删除该文件
- 验证：
  - 文件已不存在
  - `/root/.ssh/authorized_keys` 中 `PRIVATE KEY` 计数为 0
  - `tailscale status --self` 显示 HostName `tizi-kh`，MagicDNS `tizi-kh.taila93443.ts.net`

## 2026-10-31 11:10 CST - 整装为 Debian 13 + 3x-ui，沿用旧 REALITY 身份，改名 tizi-kh

- 服务器：`tizi-kh`（原 `tizi`，公网 `74.211.103.83`，Tailscale `100.90.28.83`）
- 操作人：`Claude`（用户已在服务商控制台重装为 Debian 13，并要求改名为 `tizi-kh`、代理服务端改装 3x-ui）
- 原因：从 Rocky 9.7 + S-UI 1.4.1 统一到其它节点的标准栈（Debian 13 + 3x-ui + Xray），见 `docs/runbooks/proxy-node-reinstall-upgrade.md`。
- 选型（用户确认）：
  - 沿用旧身份：REALITY 私钥、24 个 shortId、18 个客户端的 UUID / 额度 / 启用状态全部按重装前备份原样迁入，客户端不用改配置
  - Tailscale 恢复旧 `/var/lib/tailscale`，节点身份和 `100.90.28.83` 不变
  - 系统升级并重启、SSH 关密码登录、时区改为上海、装 fail2ban + vnstat
  - **LLM 反代没有恢复**：用户选的是"恢复"，但核对后发现 `litellm-us.konghai.me` 已经 CNAME 到 `rao-tz.skysms.xyz`（`rao-tizi`），旧 tizi 上这张证书 2026-05-25 就过期了，这台机的反代早已不在用。nginx / certbot 不装，配置留在备份里，重装 `rao-tizi` 时在那边恢复
- 备份：重装前全量备份见下方 10:18 条目（本机 `_backups/tizi-pre-reinstall-20261031/`）；机上另有 `/root/x-ui.db.fresh-install-20261031`（3x-ui 刚装完的空库）、`/root/vnstat.db.fresh-20261031`、`/etc/network/interfaces.bak.20261031`、`/etc/hosts.bak.20261031`
- 回滚方式：
  - 面板 / 入站：`systemctl stop x-ui`，用备份库覆盖 `/etc/x-ui/x-ui.db`，再 `systemctl start x-ui`
  - SSH 密码登录：删除 `/etc/ssh/sshd_config.d/00-hardening.conf` 后 `systemctl reload ssh`
  - 防火墙：`ufw disable`（不推荐）或 `ufw delete` 对应规则
  - 回到 Rocky + S-UI：只能重装系统，再从本机备份恢复
- 变更时序：
  1. 本机 `~/.ssh/config` 改为 `Host tizi-kh tizi`（旧别名保留兼容，改前备份 `~/.ssh/config.bak.20261031`），清理 `74.211.103.83` / `100.90.28.83` 的旧 known_hosts
  2. 控制台导入时把一把 **RSA 私钥** 写进了 `/root/.ssh/authorized_keys`，导致所有密钥都登录不上。先用控制台密码登录，把文件挪到 `/root/authorized_keys.contained-private-key-20261031`（600），换成本机 `id_ed25519.pub`（`konghai@konghai.me`）
  3. `hostnamectl set-hostname tizi-kh`，`/etc/hosts` 同步（cloud-init 已禁用，重启后主机名不会被改回去）
  4. 时区 `Asia/Shanghai`；locale `en_US.UTF-8`；`apt full-upgrade`（内核 `6.12.88` → `6.12.113`，修复 CVE-2026-98432）；装 `curl sqlite3 ufw fail2ban python3-systemd vnstat socat jq`
  5. SSH：`/etc/ssh/sshd_config.d/00-hardening.conf` 设 `PasswordAuthentication no`、`KbdInteractiveAuthentication no`、`PermitRootLogin prohibit-password`；fail2ban `sshd` jail 用 systemd backend
  6. 重启进新内核。`networking.service` 报 failed，原因是镜像的 `/etc/network/interfaces` 写了 `auto eth1`，但没有 eth1；改成 `allow-hotplug eth1`。eth0 的 DHCP 租约时长是无限期（`4294967295`），dhclient 不在也不影响
  7. Tailscale 1.104.4（官方 apt 源）：首次启动前放回旧 state，IP 仍是 `100.90.28.83`；`tailscale set --hostname=tizi-kh`。MagicDNS 名当时仍是 `tizi.taila93443.ts.net`，要在 admin console 改机器名（12:40 前用户已改，现为 `tizi-kh.taila93443.ts.net`）
  8. ufw：default deny；放行 `22/tcp`、`443/tcp`、`tailscale0` 全通（先开防火墙再装面板，免得面板端口在公网暴露）
  9. 3x-ui v3.11.0 + Xray 26.10.21：`XUI_NONINTERACTIVE=1 XUI_PANEL_PORT=2095 XUI_SSL_MODE=none` 安装；面板 `-listenIP 100.90.28.83 -port 2095`，`subListen=127.0.0.1`。安装脚本另外加了 fail2ban `3x-ipl` jail
  10. 用 3x-ui API（`/panel/api/inbounds/add`，Bearer `XUI_API_TOKEN`）建入站：remark `tizi-kh`，VLESS + REALITY `:443`，target/SNI `assets-xbxweb.xbox.com`，flow `xtls-rprx-vision`，`minClientVer=1.0.0`，sockopt `UseIPv4`。payload 由 S-UI 备份的 `clients` / `tls` / `inbounds` 生成。之后停服务改库：`share_addr_strategy=custom`、`share_addr=tz.skysms.xyz`，并迁入本期已用流量
  11. root crontab：`59 23 29 * * sqlite3 /etc/x-ui/x-ui.db "UPDATE client_traffics SET up = 0, down = 0;"`（对齐服务商每月 30 日重置；2 月没有 29 日，那个月不会自动清零）
  12. vnstat 2.13：恢复旧库 `/var/lib/vnstat/vnstat.db`，7 月以来的月度流量接上了
- 验证：
  - `uname -r` = `6.12.113+deb13-amd64`；`systemctl --failed` 为空；`x-ui`、`tailscaled`、`fail2ban`、`vnstat`、`ufw`、`cron` 均 active
  - `ss`：`*:443` xray；`100.90.28.83:2095` x-ui；`127.0.0.1:2096` 订阅；公网探测 2095 / 2096 都不通
  - Xray 运行配置 `/usr/local/x-ui/bin/config.json`：16 个客户端（等于库里启用数）；24 个 shortId；`minClientVer=1.0.0`。启用 UUID + 私钥 + shortId 的哈希和备份一致
  - 公网 TLS 探针：SNI `assets-xbxweb.xbox.com` 返回 `CN=*.xbox.com`
  - 端到端：本机用 Xray 26.10.21，以 `konghai_Air` 身份连 `tz.skysms.xyz:443`，出口 IP `74.211.103.83`，Google 204、GitHub 200
  - 密码登录被拒（`Permission denied (publickey)`）；公网和 Tailscale 两条 SSH 路径都能用密钥登录
- 面板入口：`http://100.90.28.83:2095/<webBasePath>/`，账密和 webBasePath 在机上 `/etc/x-ui/install-result.env`（600），**不入库**
- 遗留：
  - ~~`/root/authorized_keys.contained-private-key-20261031` 里是一把 RSA 私钥，等用户确认后删除~~（12:40 已删，见上条）；这把私钥应视为已泄露，不要再用
  - ~~Tailscale admin console 里把机器名改成 `tizi-kh`~~（用户已改，见上条）
  - 客户端 `konghai家里路由器` 和 `景阳` 保持禁用（和重装前一致）；家里路由器从 10-11 起已经改走 `tizi-cyp`

## 2026-10-31 10:18 CST - 整装 Debian 13 前全量备份用户与配置到本机

- 服务器：`tizi`
- 操作人：`Claude`
- 原因：用户计划把 `tizi` 从 Rocky 9.7 整装为 Debian 13，重装会抹掉整盘（包括 `/root/backup`），要先把用户与配置拉回本机。
- 影响：只读。在 `/root` 下生成备份目录和 tar 包，没有改服务、配置、防火墙和 crontab，也没有重启。
- 回滚方式：无服务器变更。备份包在服务器 `/root/tizi-pre-reinstall-20261031-101744*`，可以删，重装时也会一起被抹掉。
- 做了什么：
  - 新增脚本 `scripts/backup-proxy-node-pre-reinstall.sh`，执行方式：`ssh tizi 'bash -s' -- tizi < scripts/backup-proxy-node-pre-reinstall.sh`
  - 本机位置（`_backups/` 已 gitignore，含密钥，不入库）：`_backups/tizi-pre-reinstall-20261031/tizi-pre-reinstall-20261031-101744.tar.gz`（58M）+ `.sha256`，同目录下有解包副本
  - 备份内容：
    - S-UI 1.4.1 / sing-box v1.13.4：用 `sqlite3 .backup` 做在线一致性备份；`clients` / `inbounds` / `tls` / `settings` / `users` 等表另外导出为 JSON（体积大的 `stats` / `changes` 只在 db 里）
    - 账户：`/etc/passwd`、`shadow`、`group`、`sudoers`（没有 UID≥1000 的普通用户）；`/root/.ssh`；`/etc/ssh` 整目录（含主机密钥）
    - nginx（`:8443` LLM API 反代 `llm-proxy.conf`）、`/etc/letsencrypt`（`litellm-us.konghai.me`）、firewalld、sysctl（bbr/fq、fastopen、rp_filter）、自定义 systemd unit、root crontab、`/var/lib/tailscale`、`/var/lib/vnstat`、`/opt`、`/root` 下的小文件（旧 S-UI 库副本和二进制只留清单）
    - 现场快照：`ip addr`/`route`、`ss`、`ps`、`rpm -qa`、已启用服务列表
    - certbot 是 `/usr/local/bin/certbot`（pip 装在 python3.13 下），cron 一天两次 `renew` 后 reload nginx；`/opt/envoy` 只有一个二进制，没在运行
- 验证：
  - 本机 `shasum -a 256 -c` OK，解包后 S-UI 库 `PRAGMA integrity_check` = `ok`
  - 客户端数 18（启用 16），和线上一致；入站只有 1 个 `vless-reality`；TLS 记录 1 条
  - `authorized_keys` 只有一把 `ssh-ed25519 konghai@konghai.me`
  - 线上 `/root/.ssh` 目录权限是 `600`（没有 x 位），解包后本机进不去；本机副本已 `chmod 700`，包里的文件完整
- 重建要点（Debian 13）：
  - 网络：eth0 走 DHCP，没有其它网卡配置要迁
  - Tailscale：先停 `tailscaled`，把备份的 `/var/lib/tailscale` 放回去再启动，可以保留原节点身份和 `100.90.28.83`（面板 `webListen` 绑的是这个 IP）。如果改成重新登录，要在控制台删掉旧节点，面板监听也要改成新 IP
  - SSH：放回 `/etc/ssh/ssh_host_*`，客户端就不会报 host key 变更
  - 防火墙：Debian 用 ufw，对应现有规则：22、80、443、8443/tcp 对公网，`tailscale0` 全放行
  - 流量月清 cron：每月 29 日 23:59
  - 面板选型（照 S-UI 原样恢复，还是按 `docs/runbooks/proxy-node-reinstall-upgrade.md` 迁到 3x-ui）等重装时再定

## 2026-10-31 09:24 CST - 只读：CVE-2026-98432 内核漏洞暴露面排查

- 服务器：`tizi`
- 操作人：`Claude`
- 原因：CVE-2026-98432（IPv4 TCP use-after-free，Anthropic 演示了对 MPTCP 监听服务器远程拿 root）公开，需要确认各服务器是否受影响。
- 影响：只读（`uname`、`net.mptcp.enabled`、`ss -Mlnp`、已装内核列表）。没升级、没重启。
- 回滚方式：无服务器变更，无需回滚。
- 结果：Rocky 9.7，运行 `5.14.0-611.49.1`，受影响；`net.mptcp.enabled=0`，没有 MPTCP 监听，但 bug 在通用 TCP 路径，仍有风险。RHEL 系还没出修复包。
- 汇总与建议：`docs/reviews/2026-10-31-cve-2026-98432-kernel-exposure.md`

## 2026-10-11 15:40 CST - 排查家里断网：client「konghai家里路由器」超流量被自动禁用

- 服务器：`tizi`（s-ui，`vless-reality` 入站 `:443`，域名 `tz.skysms.xyz`）
- 操作人：`Claude`。用户反馈 mac-mini 上的 GitHub Actions runner 全部离线，并且重启 `home-router` 后仍然不通。
- 原因：s-ui client id `8`「konghai家里路由器」的流量额度是 200 GiB，已用 200.22 GiB，`enable` 被自动置为 `0`，而且没开 `auto_reset`。从 `2026-10-11 14:02 CST` 起，s-ui 日志开始对家里公网 IP `112.117.x.x` 报 `unknown UUID: 03021f5d-…`。
- 排查链路：
  - `home-router` Passwall 正常运行（xray + chinadns-ng），唯一节点是 `tz.skysms.xyz:443`，也就是 `tizi`。
  - 从家里能 ping 通 `74.211.103.83`，TCP 443 也能连上，但走 socks `1080` 访问 GitHub 失败。
  - 所有境外 DNS（Passwall 远程 DNS `8.8.8.8`）和境外 HTTPS 都依赖这个节点，所以一起失败。国内直连正常。
- 影响：只做了只读排查，没有改 s-ui，没有改路由器。
- 回滚方式：无变更，无需回滚。
- 修复建议：在 s-ui 面板里给该 client 重置流量（或调大额度）并重新启用，必要时打开 `auto_reset`。

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
