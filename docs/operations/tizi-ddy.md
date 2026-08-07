# tizi-ddy 运维时间线

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`tizi-ddy`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN（轻量扫）。ioc=0。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-07-30 23:02 CST - REALITY minClientVer=1.0.0 修复 Shadowrocket 兼容

- 服务器：`tizi-ddy`
- 操作人：`Grok`
- 原因：同一 iPhone 上 `rao-tizi`（S-UI/sing-box）可用、电脑上同一 `konghai-test` 可用，但 Shadowrocket 连 `tizi-ddy`（3x-ui + Xray REALITY）失败。排查发现今日面板升至 **3.6.0 / Xray 26.7.28** 后日志反复警告：
  `REALITY: The default minimal client version is Xray-core v26.3.27, other clients may be refused to connect`。
  社区（Xray #6482、3x-ui #5922 等）与现象一致：新版 Xray 在 `minClientVer` 留空时默认要求客户端 ≥ 26.3.27；Shadowrocket 版本号格式对不上会被拒，桌面 Xray 客户端不受影响。
- 选型 / 影响：
  - 将入站 REALITY **最小客户端版本** 显式设为 `1.0.0`（放宽默认门槛，恢复 Shadowrocket 等非 Xray 版本号客户端）。
  - **数据面短暂中断**：`systemctl restart x-ui` 两次（约 23:01、23:02 CST）。
  - dest/SNI/密钥/shortIds/UUID 未改。
  - Xray 会额外警告：改低 `minClientVer` 可能略增 IP 被墙探测风险（官方提示）；与兼容性权衡后仍采用社区通行值 `1.0.0`。
- 备份：
  - `/root/backup/tizi-ddy-minclient-1.0.0-20260730-230143/`（首次误改 `minClient` 字段前的 `x-ui.db` + `config.json`）
  - `/root/backup/tizi-ddy-minclientver-1.0.0-20260730-230237/`（写入 `minClientVer` 前的 `x-ui.db` + `config.json`）
- 回滚方式：
  ```bash
  cp -a /root/backup/tizi-ddy-minclientver-1.0.0-20260730-230237/x-ui.db /etc/x-ui/x-ui.db
  cp -a /root/backup/tizi-ddy-minclientver-1.0.0-20260730-230237/config.json /usr/local/x-ui/bin/config.json
  systemctl restart x-ui
  ```
- 变更时序：
  1. 备份 DB + config.json  
  2. 首次只把 DB/运行时字段 `minClient` 写成 `1.0.0` 并 restart → **无效**：Xray JSON 只认 `minClientVer`，启动仍报 default min = 26.3.27  
  3. 再次备份；在 `inbounds.stream_settings.realitySettings` 写入 **`minClientVer":"1.0.0"`**（并同步 legacy `minClient`、补 `maxClientVer`/`maxTimeDiff`），`systemctl restart x-ui`  
  4. 运行时 `config.json` 已含 `minClientVer: 1.0.0`；`*:443` 由 xray 监听；本机 REALITY TLS 探针仍返回 `*.xbox.com`
- 验证：
  - 启动日志变为：`REALITY: Changing "minClientVer" will increase the likelihood of your server's IP being blocked by the GFW`（说明字段已生效）
  - **不再出现** `default minimal client version is Xray-core v26.3.27`
  - `x-ui` active，`Xray 26.7.28 started`，`:443` LISTEN
  - 待用户在 iPhone Shadowrocket 用原 `konghai-test` 节点复测通网

## 2026-07-30 13:01 CST - 对齐 tizi：Xray 强制 IPv4 解析（UseIPv4）

- 服务器：`tizi-ddy`
- 操作人：`Grok`
- 原因：与同 Provider 的 `tizi`/`tizi-cyp` 对齐；节点无公网 IPv6，REALITY dest（`assets-xbxweb.xbox.com`）有 AAAA，避免 handshake/出站误走 IPv6。
- 影响：
  - **数据面短暂中断**：`systemctl restart x-ui` 两次（约 12:59、13:00 CST），xray 重载后 `:443` 恢复监听。
  - inbound `in-443-tcp`：`stream_settings.sockopt.domainStrategy = UseIPv4`（贴近 S-UI `handshake.domain_strategy=ipv4_only`）。
  - freedom outbound `direct`：`domainStrategy = UseIPv4`（写入 settings `xrayTemplateConfig`，重启后持久）。
  - REALITY dest/SNI/密钥未改。
- 备份：`/root/backup/tizi-ddy-ipv4-only-20260730-125855/`（`x-ui.db`、`config.json`、`stream_settings.before.json`）。
- 回滚方式：
  ```bash
  cp -a /root/backup/tizi-ddy-ipv4-only-20260730-125855/x-ui.db /etc/x-ui/x-ui.db
  cp -a /root/backup/tizi-ddy-ipv4-only-20260730-125855/config.json /usr/local/x-ui/bin/config.json
  # 可选：sqlite 删除 key=xrayTemplateConfig 后恢复默认模板
  systemctl restart x-ui
  ```
- 变更时序：
  1. 备份 DB + config.json  
  2. 更新 `inbounds.stream_settings.sockopt.domainStrategy=UseIPv4`  
  3. 首次改 config.json outbound 后 restart → outbound 被默认模板冲回 `AsIs`；inbound sockopt 仍在  
  4. 将含 `UseIPv4` 的默认骨架写入 `settings.xrayTemplateConfig` 再 restart  
  5. 运行时 config：outbound `UseIPv4` + inbound sockopt `UseIPv4` 均保留；xray 26.7.11 started，无新 ERROR
- 验证：
  - `ss`：`*:443` xray、`100.75.133.13:2095` 面板  
  - config.json / DB 双处 `UseIPv4`  
  - 本机 `curl -4` 外网 200；dest 域名仍可走 A 记录连通

## 2026-07-30 12:55 CST - 对照 tizi 的 IPv6 处理方式（只读）

- 服务器：`tizi`（对照） / `tizi-ddy`（待对齐）
- 操作人：`Grok`
- 原因：用户要求查 `tizi` 如何处理 IPv6；`tizi-ddy` 与 `tizi` 同 Provider，应对齐。
- 影响：无（只读；**尚未**改 ddy 配置）。
- 结论摘要：
  1. **系统层（tizi / tizi-cyp / tizi-ddy 一致）**  
     - 无公网 IPv6，仅 eth0 `fe80::` + Tailscale ULA；无默认 IPv6 路由；`ping6`/`curl -6` 失败，`curl -4` 正常。  
     - 厂商 `ipv6net.service` + `/etc/init_ipv6_tunnel` 为 **空脚本 no-op**，未建 SIT。  
     - **没有** 在 sysctl 里 `disable_ipv6=1`。
  2. **应用层（tizi / tizi-cyp 的有意处理）**  
     - S-UI REALITY TLS：`reality.handshake.domain_strategy = "ipv4_only"`。  
     - 历史：`s-ui.db.before-ipv4-only-20260501`；`bash_history` 中  
       `json_set(..., '$.reality.handshake.domain_strategy', 'ipv4_only')`。  
     - 原因：dest `assets-xbxweb.xbox.com` 同时有 A + AAAA；节点无 IPv6 出站时 handshake 若走 AAAA 会失败。  
     - direct outbound **未**再设 domain strategy（`{}`）；listen 仍为 `::`（双栈入站）。
  3. **tizi-ddy 缺口（3x-ui / Xray）**  
     - REALITY `dest/target` = `assets-xbxweb.xbox.com:443`，**无** 等价 `ipv4_only`。  
     - freedom outbound `domainStrategy=AsIs`；routing `AsIs`。  
     - sniffing 开启，出站可能对嗅探域名再解析，存在选 AAAA 的风险。
  4. **建议对齐（待用户确认后执行；会触达 xray 重载）**  
     - inbound `stream_settings.sockopt.domainStrategy = UseIPv4`（对 REALITY dial dest 侧更贴近 sing-box 的 handshake 策略）；  
     - freedom outbound `domainStrategy = UseIPv4`；  
     - 备份 x-ui.db + config.json 后再改。
- 回滚方式：N/A（本条只读）。
- 验证：三台 `ip -6 route` / REALITY dest DNS A+AAAA / tizi tls JSON 已核对。

## 2026-07-30 12:43 CST - 只读检查系统/3x-ui 日志（重点 IPv6）

- 服务器：`tizi-ddy`
- 操作人：`Grok`
- 原因：用户要求检查代理服务器日志，特别关注 IPv6 相关报错。
- 影响：无（只读排查，未改配置/服务）。
- 备份：无。
- 回滚方式：无。
- 变更时序 / 排查结论：
  1. **服务状态**：`x-ui` active（PID 4407，自 2026-07-28 10:57 起）；内嵌 `xray 26.7.11`（PID 4417）；uptime ~2d；load 极低。
  2. **IPv6 报错**：**未发现**。
     - `journalctl -p err..alert` 近 7 天：`ipv6|IPv6|inet6|AF_INET6` 匹配 **0**。
     - `/var/log/x-ui/3xui.log`：无 ERROR/FATAL；与 IPv6 相关仅有历史 INFO「Web/Sub server running HTTP on `[::]:2095/2096`」（首启默认绑定，后已改为 Tailscale IPv4 `100.75.133.13:2095`）。
     - `journalctl -u x-ui`：无 Xray dial/listen 失败类日志。
  3. **IPv6 栈现状（重要，但不是“报错”）**：
     - `disable_ipv6=0`，但 **eth0 无公网 IPv6**，仅 `fe80::` link-local；Tailscale ULA `fd7a:115c:a1e0::13a:850e/128`。
     - **无默认 IPv6 路由**：`ip -6 route get 2001:4860:4860::8888` → `Network is unreachable`；`ping6` / `curl -6` 失败；`curl -4` 正常。
     - `ipv6net.service`（SIT tunnel）enabled 且 active(exited)，但 `/etc/init_ipv6_tunnel` 内容为空 no-op，**未建立任何 sit 接口**。
  4. **数据面**：xray 监听 `*:443`（双栈 socket）；当前 ESTAB 连接均为 IPv4-mapped（`[::ffff:80.251.215.131]:443` ↔ 国内 IPv4 客户端）；路由 `domainStrategy=AsIs`，outbound freedom 同为 `AsIs`。
  5. **其它日志噪音（非 IPv6）**：
     - 公网 SSH 扫描：`kex_exchange_identification: Connection reset by peer` 大量；偶发 `maximum authentication attempts exceeded`；fail2ban sshd 正常 ban/unban。
     - 面板：`Unauthorized WebSocket connection attempt from 100.92.181.15`（自 07-30 03:22 起间歇，多为浏览器会话过期/未登录 WS 探测，来源为管理端 Tailscale IP）。
     - UFW 持续 BLOCK 非 22/443 扫描端口（预期行为）。
  6. **日志可见性限制**：xray `loglevel=warning`、`access=none`、`error=""`（stderr 进 x-ui journal）；若客户端经代理访问 **纯 IPv6 目标**，理论上可能出现 dial 失败，但当前 journal 中**没有**此类 warning；若要深挖出站 IPv6 失败需临时把 loglevel 提到 `info`/`debug`（需确认后改）。
- 验证：只读命令已执行；结论如上。

## 2026-07-28 11:15 CST - 分享链接永久使用域名 ddy-tizi.skysms.xyz

- 服务器：`tizi-ddy`
- 操作人：`Grok`
- 原因：分享链接默认出现 `@80.251.215.131` / Tailscale IP，希望统一为 `ddy-tizi.skysms.xyz`，避免每次手改。
- 影响：
  - **DNS**：`ddy-tizi.skysms.xyz` → `80.251.215.131`（已生效）。
  - **现有 inbound `ddy-tizi`**：`shareAddrStrategy=custom`，`shareAddr=ddy-tizi.skysms.xyz`；复制链接 `@` 后即为域名。
  - **Hosts**：面板 Hosts 组绑定域名 `ddy-tizi.skysms.xyz` 到全部 inbound（当前 id=1）。
  - **面板 webDomain / subDomain**：设为 `ddy-tizi.skysms.xyz`（订阅仍关闭；作 public host 兜底）。
  - **运维脚本**（新建 inbound 后一键对齐）：`/root/bin/xui-set-share-domain.sh`  
    会把**所有** inbound 的 share 改为 custom+域名，并重建 Hosts 绑定全部 inboundIds。
- 说明（3x-ui 行为）：
  - 新建 inbound 默认策略是 `node`/`listen`，分享 host 会落到面板访问地址（本机常为 Tailscale IP），**没有**全局「默认 External 域名」开关。
  - 想免手改 IP：创建时表单选 **Share Address Strategy = Custom**，填 `ddy-tizi.skysms.xyz`；或创建后执行上述脚本。
- 备份：无新增敏感项；配置在 x-ui DB / settings。
- 回滚：inbound 改回 `shareAddrStrategy=node` 并清空 `shareAddr`；Hosts 删除域名组；`webDomain` 置空。
- 验证：
  - `panel/api/clients/links/test-ddy` → `@ddy-tizi.skysms.xyz:443`
  - `inbounds/options` → `shareAddr=ddy-tizi.skysms.xyz` / `custom`
  - `getent hosts ddy-tizi.skysms.xyz` → `80.251.215.131`

## 2026-07-28 10:58 CST - 对齐 tizi-cyp：建 VLESS+REALITY inbound，关闭订阅

- 服务器：`tizi-ddy`
- 操作人：`Grok`
- 原因：按 `tizi-cyp` 数据面形态启用代理；用户明确**不支持订阅**。
- 影响：
  - **Inbound `ddy-tizi`**（tag `in-443-tcp`）：VLESS + REALITY，监听 `*:443`，网络 TCP，flow `xtls-rprx-vision`。
  - **REALITY**（密钥本机新生成，**不**复制 cyp）：
    - SNI / serverNames：`assets-xbxweb.xbox.com`
    - dest / target：`assets-xbxweb.xbox.com:443`
    - uTLS fingerprint：`chrome`
    - shortIds：`""` + 一组随机 hex（与 cyp 双 shortId 形态一致）
  - **测试客户端**：`test-ddy`（仅测试号，无流量上限/过期）
  - **External 地址**：后改为域名 `ddy-tizi.skysms.xyz`（见同日 11:15 条目）
  - **订阅关闭**：`subEnable=false`，`subClashEnable=false`，`subJsonEnable=false`，`subListen=127.0.0.1`；进程不再监听 `2096`；公网 `2096` 不通。
  - **面板时区**：`timeLocation=Asia/Tehran`（与 tizi / tizi-cyp 一致；系统时区仍为 `Asia/Shanghai`）。
- 备份：`/root/backup/tizi-ddy-20260728/`（`settings-before.json`、`x-ui.db.after-inbound`、`reality-keys.txt`、`test-ddy.sharelink` 等，root 600）。
- 回滚方式：
  - 删 inbound：面板删除或 API `POST /panel/api/inbounds/del/1`
  - 停数据面：`systemctl stop x-ui` 或仅 disable inbound
  - 恢复 DB：从 `x-ui.db.initial` / `x-ui.db.after-inbound` 拷回后 `systemctl restart x-ui`
- 验证：
  - `ss -lntp`：`*:443` xray；`100.75.133.13:2095` 面板；**无** `2096`
  - 公网 `80.251.215.131:443` 通；`:2096` 不通
  - `panel/api/inbounds/list` → 1 条 `ddy-tizi` enable
  - settings：`subEnable=false`，`webListen=100.75.133.13`
- 备注：
  - 分享链接 / REALITY 私钥 / UUID **不入库**；见服务器备份目录或面板「复制链接」。
  - 与 cyp 差异：面板栈 3x-ui/xray vs S-UI/sing-box；对外域名 cyp 已有 `cyp-tz.skysms.xyz`，ddy 暂用公网 IP。
  - 正式用户请在面板另建 client，勿长期共用 `test-ddy`。

## 2026-07-28 10:25 CST - 完成代理节点基线部署（3x-ui + ufw + BBR + vnstat）

- 服务器：`tizi-ddy`（公网 `80.251.215.131` / Tailscale `100.75.133.13`）
- 操作人：`Grok`
- 原因：新代理节点纳入管理；对齐 `tizi-cyp` 的运维形态（纯代理、面板仅 Tailscale、公网仅 `22`+`443`），面板栈按用户指定使用 **3x-ui**（非 S-UI）。
- 影响：
  - **系统基线**：hostname `admired-bliss-1.localdomain` → `tizi-ddy`；时区 `UTC` → `Asia/Shanghai`；生成 `en_US.UTF-8` locale。
  - **BBR**：运行时与持久配置均为 `tcp_congestion_control=bbr` + `default_qdisc=fq`（镜像模板已有；补写 `/etc/sysctl.d/99-bbr.conf`）。
  - **Tailscale**：部署前已登录；节点名 `tizi-ddy`，IPv4 `100.75.133.13`。
  - **3x-ui `v3.5.0`**（官方 install 脚本，`XUI_NONINTERACTIVE=1`）：SQLite 后端；面板端口 `2095`；随机 WebBasePath；**未**配面板 SSL（仅经 Tailscale 访问，与 `tizi-cyp` 面板暴露策略一致）。
  - **面板绑定**：`listenIP=100.75.133.13`（仅 Tailscale）；公网 `2095` 不可达。
  - **订阅端口**：安装默认 `*:2096`（ufw 未放行公网，外网不可达）；后续可在面板 UI 改 listen/关闭。
  - **ufw**（Debian 对应 `tizi-cyp` 的 firewalld）：default deny incoming；放行 `OpenSSH` + `443/tcp`；`tailscale0` 全放行；已 enable。
  - **SSH**：`PasswordAuthentication no`（密钥已验证可用）；备份见 `/root/backup/tizi-ddy-20260728/`。
  - **vnstat**：监控 `eth0` + `tailscale0`，已 active。
  - **fail2ban**：安装脚本顺带启用（3x-ui IP Limit 用）。
  - 公网暴露面：`22` + `443`（inbound 见同日 10:58 条目）。
- 备份：`/root/backup/tizi-ddy-20260728/`（`sshd_config*`、`ufw-*`、`x-ui.db.initial`、`install-result.env` 等）。
- 回滚方式（按需）：
  - 停面板/代理：`systemctl disable --now x-ui`
  - 恢复 DB：从备份拷回 `/etc/x-ui/x-ui.db` 后 `systemctl restart x-ui`
  - 防火墙急救：`ufw disable`（仅连通性急救）
  - 恢复密码登录：从备份还原 `sshd_config` 后 `sshd -t && systemctl reload ssh`
- 变更时序：SSH 别名 → 基线（hostname/时区/BBR/vnstat）→ 装 3x-ui → 面板绑 TS → ufw → 关密码登录 → 文档。
- 验证：
  - `ssh tizi-ddy` BatchMode 成功；`PasswordAuthentication no`
  - `systemctl is-active x-ui tailscaled vnstat fail2ban` → active；`ufw status` → active
  - `ss -lntp`：`100.75.133.13:2095` x-ui；无公网 `2095`
  - 本机经 Tailscale：`http://100.75.133.13:2095/<webBasePath>/` → HTTP 200
  - 公网 `80.251.215.131:2095` → 不通；`:22` → 通
  - `sysctl`：`bbr` + `fq`
  - `vnstat -i eth0` 已有初始数据
- 备注：
  - 面板初始账号/密码/API Token/WebBasePath **不写入仓库**；见服务器 `/etc/x-ui/install-result.env`（mode 600）及本机密码管理器。
  - 用户称「已安装证书」：本机未发现 `/root/cert` 或 acme 域名证书；面板刻意走 Tailscale HTTP。若 inbound 要用域名 TLS/REALITY，在 3x-ui 面板内配置即可。
  - 与 `tizi-cyp` 差异：OS=Debian 13 / 面板=3x-ui(xray) / 防火墙=ufw；角色同为**扩容代理节点**。
  - 后续：inbound/订阅已在同日 10:58 完成；可按需加流量重置 cron、配置 ddy 域名 External。

## 2026-07-28 10:21 CST - 纳入 SSH 别名 `tizi-ddy` 并只读复核

- 服务器：`tizi-ddy`
- 操作人：`Grok`
- 原因：新机器 `80.251.215.131` 纳入本机 SSH 别名管理。
- 影响：
  - 本机 `~/.ssh/config` 增加 `Host tizi-ddy`（`HostName 80.251.215.131`，`User root`，`IdentityFile ~/.ssh/id_ed25519`）。
  - 只读发现：Debian 13；Tailscale 已 online（节点名已是 `tizi-ddy`，`100.75.133.13`）；BBR 已生效；监听仅 `22` + tailscaled；未装面板。
- 备份：无（只读）。
- 回滚方式：删除 `~/.ssh/config` 中对应 Host 块。
- 验证：`ssh tizi-ddy` BatchMode 成功。
