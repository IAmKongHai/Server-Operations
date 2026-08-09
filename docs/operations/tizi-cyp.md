# tizi-cyp 运维时间线

## 2026-08-09 02:02 CST - 重装后完成 Debian 13 + 3x-ui REALITY 基线与跳板

- 服务器/设备：`tizi-cyp`（公网 `89.208.242.203`，Tailscale **现** `100.116.91.14`；重装前 TS 为 `100.88.178.78`）
- 操作人：`Grok`（用户已登录 Tailscale；授权完成剩余重建）
- 原因：用户重装 OS 为 Debian 13 后，恢复纯代理节点（**3x-ui + Xray**，对齐 ddy；弃用 S-UI/sing-box）。
- 选型 / 影响：
  - **OS 基线**：hostname `tizi-cyp`；时区 `Asia/Shanghai`；`en_US.UTF-8`；BBR + `fq`；包：`curl`/`ufw`/`fail2ban`/`socat`/`sqlite3`/`vnstat`；SSH `PasswordAuthentication no`。
  - **3x-ui v3.6.0** + **Xray 26.7.28**：VLESS + REALITY `*:443`，remark `cyp-tizi`，dest/SNI `assets-xbxweb.xbox.com`，flow `xtls-rprx-vision`，`minClientVer=1.0.0`；**UUID / REALITY 私钥 / shortIds** 从本机备份 `migration-export` / `s-ui.db` 原样迁入（6 客户端，5 启用）。
  - **面板**：仅 `100.116.91.14:2095`（webBasePath 随机，安装时生成）；sub 绑 `127.0.0.1:2096`；**无**公网面板端口。
  - **ufw**：default deny；放行 `22/tcp`、`443/tcp`、`tailscale0` 全通。
  - **mssql-ref-proxy**：`socat` 仅听 **`100.116.91.14:1433` → `100.124.140.78:1433`**，`MemoryMax=256M`，enabled。
- 备份：
  - 本机（gitignored）：`_backups/tizi-cyp-pre-reinstall-20260809/`
  - 机上：`/root/migrate-payload.json`（敏感）、`/root/mssql-ref-proxy.README`、`/etc/x-ui/install-result.env`（面板账密，mode 600）
- 回滚方式：
  - 面板/入站：改 `/etc/x-ui/x-ui.db` 后 `systemctl restart x-ui`（需保留备份库）
  - 跳板：`systemctl disable --now mssql-ref-proxy && rm -f /etc/systemd/system/mssql-ref-proxy.service && systemctl daemon-reload`
  - 防火墙：`ufw disable`（不推荐）或按 `ufw status` 回改规则
- 变更时序：基线软件包 → 3x-ui 官方安装 → 写 REALITY 入站/客户端 → 面板绑 TS:2095 → ufw → mssql-ref-proxy → 验收。
- 验证：
  - `scripts/verify-tizi-cyp-baseline.sh` → `VERIFY_TIZI_CYP_OK`
  - `ss`：`*:443` xray；`100.116.91.14:2095` x-ui；`100.116.91.14:1433` socat；无 `0.0.0.0:2095/1433`
  - 迁移对账：6 UUID 与私钥匹配；`minClientVer=1.0.0`；禁用客户端未进运行时 config
  - 公网 TLS 探针：`:443` SNI `assets-xbxweb.xbox.com` 返回 `CN=*.xbox.com`（REALITY 握手面）
- 备注：
  - 客户端侧 **无需改 UUID/密钥**（域名 `cyp-tz.skysms.xyz` 未动）。
  - 面板 URL 仅经 Tailscale：`http://100.116.91.14:2095/<webBasePath>/`（path 见机上 `install-result.env`，**勿写入 git**）。
  - 明日全量客户端上线前建议各抽测一条路由器节点。
  - **经验落盘（后续节点升级用）**：
    - Runbook：`docs/runbooks/proxy-node-reinstall-upgrade.md`
    - 通用选型：`docs/solutions/best-practices/proxy-node-3x-ui-debian-upgrade-2026-08-09.md`
    - 本机样板：`docs/solutions/tizi-cyp/best-practices/debian-3xui-reinstall-from-s-ui-2026-08-09.md`

## 2026-08-09 01:38 CST - 重装前全量备份（已拉回本机）

- 服务器/设备：`tizi-cyp`
- 操作人：`Grok`（用户确认运维窗口、计划 Debian 13.5 + 3x-ui 重装）
- 原因：重装 OS/面板前落盘可恢复材料；备份优先拉回本机，磁盘上的 `/root/backup` 重装后会丢。
- 影响：只读备份 + 打包传输；**未**停服务、**未**改配置、**未**重装。S-UI 在线 `sqlite3 .backup`，`integrity_check=ok`。
- 服务端路径：
  - 目录：`/root/backup/tizi-cyp-pre-reinstall-20260809-013659/`
  - 包：`/root/backup/tizi-cyp-pre-reinstall-20260809-013659.tar.gz`（~23–24M，含迁移 JSON 的刷新包）
  - SHA256 同目录 `*.sha256`
- 本机路径（**不入库**，见 `.gitignore` `_backups/`）：
  - `/Users/konghai/Code/Project/Server/_backups/tizi-cyp-pre-reinstall-20260809/tizi-cyp-pre-reinstall-20260809-013659.tar.gz`
  - 已解压同名目录；关键：`s-ui/s-ui.db`、`s-ui/migration-export.json`、`MIGRATE-TO-3XUI.md`、`mssql-ref-proxy/`、`tailscale/`、`ssh/`
- 备份内容摘要：S-UI 1.5.3 DB + dump、客户端 6 条、firewalld/ssh/cron/sysctl、mssql-ref-proxy unit、Tailscale state、主机元数据、历史 `/root/backup/tizi-cyp-20260710`
- 校验：本机 `shasum -a 256 -c …sha256` → OK
- 回滚：无变更；重装后依赖本机 `_backups/` 恢复
- 备注：S-UI DB **不能**直接导入 3x-ui；UUID/REALITY 密钥在 `migration-export.json`（敏感，勿提交 git）

## 2026-08-09 01:16 CST - 只读对照 tizi-ddy：系统/面板现状与重装选型调研

- 服务器/设备：`tizi-cyp`（对照 `tizi-ddy`）
- 操作人：`Grok`
- 原因：用户计划重装 `tizi-cyp` 系统与代理面板，需两机现状对比 + 全网口碑（AlmaLinux/S-UI vs Debian/3x-ui）。
- 影响：只读 SSH 排查；**未**改配置、未重启、未重装。
- 快照（2026-08-09）：
  - **OS**：AlmaLinux 9.8（kernel `5.14.0-611.55.1.el9_7`，EOL 2032-06-01）
  - **硬件**：3 vCPU AMD EPYC-Genoa / 2 GiB RAM / 40G disk（用 6%）/ KVM
  - **面板栈**：S-UI **1.5.3** + Sing-Box **v1.13.14**（单进程 `/usr/local/s-ui/sui`，RSS ~430 MiB，DB ~39M）
  - **数据面**：`*:443`（VLESS，inbound 名 `cyp-tizi`）；客户端约 6 条（多为家里/办公室路由器）
  - **面板暴露**：仅 Tailscale `100.88.178.78:2095`（path `/app/`）；sub `127.0.0.1:2096`
  - **公网**：`22` + `443/tcp`（firewalld public）；另 `mssql-ref-proxy` 仅 TS `1433`
  - **流量**：2026-07 eth0 **1.72 TiB**；2026-08 迄今 ~118 GiB
  - **共性**：BBR+fq、Tailscale 1.102.2、无 Docker
- 口碑要点（社区/GitHub，见对话）：S-UI ~9.7k★，适合 sing-box 新协议；3x-ui ~44k★ 生态更大；代理节点重装常见选 Debian + 3x-ui。
- 重装前必迁：面板 DB/客户端 UUID·REALITY 密钥、域名 `cyp-tz.skysms.xyz`、firewalld/ufw 策略、Tailscale、**`mssql-ref-proxy` unit**、流量清零 cron。
- 备份：无（只读）。
- 回滚：无变更。

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`tizi-cyp`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN（轻量扫）。ioc=0。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-07-21 14:15 CST - 决议：第二跳暂不改；Peer Relay 备选记入日志

- 服务器：`tizi-cyp`（第二跳 underlay 决策）
- 操作人：`Grok` / 用户确认
- 原因：用户评估后保持 `mssql-ref-proxy` + DERP 现状；不推进家宽 UPnP / km-landui Peer Relay。
- 影响：**无变更**。`mssql-ref-proxy` 继续仅监听 `100.88.178.78:1433`。
- 备选（未做）：
  - **km-landui Peer Relay（方案 A）**：在 `43.228.79.237` 装 Tailscale 并 `--relay-server-port`，供 `tizi-cyp`↔家宽 hard NAT 时走自建 UDP 中继。详见 `docs/operations/dev-cypresso.md` 同日「决议」条目。
  - **家宽真 direct（方案 B）**：因 CGNAT + miniupnpd 未运行且用户不修，搁置。
- 回滚：无。

## 2026-07-21 13:30 CST - 部署 mssql-ref Tailscale 跳板（姿势 1）

- 服务器：`tizi-cyp`（TS `100.88.178.78` / 公网 `89.208.242.203`）
- 操作人：`Grok`（用户确认采用姿势 1，放弃公网 1433）
- 原因：`dev-cypresso` → `mssql-ref` 直连走 DERP，延迟/抖动差；`dev-cypresso` → `tizi-cyp` 为 **TS direct ~61ms**，借跳板稳定第一跳。
- 影响：
  - 新增 systemd 服务 `mssql-ref-proxy.service`（enabled）。
  - **仅**监听 `100.88.178.78:1433`（Tailscale），**未**绑公网；`tailscale0` 已在 firewalld `trusted` zone。
  - 后端：`TCP 100.124.140.78:1433`（`mssql-ref`）。
  - 实现：`socat`（本机已装）；`MemoryMax=256M`，避免拖垮 S-UI。
  - 说明文件：`/root/mssql-ref-proxy.README`
- 备份：无覆盖既有文件；unit 为新增。
- 回滚：
  ```bash
  ssh tizi-cyp 'systemctl disable --now mssql-ref-proxy && rm -f /etc/systemd/system/mssql-ref-proxy.service && systemctl daemon-reload'
  # 同时把 dev-cypresso DB_*_HOST 改回 100.124.140.78 并 recreate api/worker
  ```
- 验证：
  - `systemctl is-active mssql-ref-proxy` → `active`
  - `ss -lntp`：`100.88.178.78:1433` socat；公网无 1433
  - 从 `dev-cypresso` TCP 建连：proxy 热路径 ~61ms vs direct ~650–950ms
  - `sqlcmd` 可连上同一实例 `mssql-ref`
- 备注：第二跳 `tizi-cyp`→`mssql-ref` 仍为 DERP ~185ms；端到端 RTT 约 240–260ms，收益主要在第一跳稳定与建连。

## 2026-07-10 01:35 CST - 用户分享链接改用域名 cyp-tz.skysms.xyz

- 服务器：`tizi-cyp`
- 操作人：`Grok`
- 原因：已将 `cyp-tz.skysms.xyz` A 记录指向公网 `89.208.242.203`；希望面板复制/生成的客户端联机地址使用域名而非裸 IP。
- 影响：
  - S-UI 入站 `vless-reality` 的 **`addrs`（External / 对外地址）** 设为 `cyp-tz.skysms.xyz:443`。
  - `out_json.server` 同步为域名（JSON 导出一致）。
  - 已有用户 `test-cyp` 的 `links` 主机名由 IP 改为域名。
  - **之后在面板新建/编辑用户时**，只要入站 `addrs` 保留，生成链接会继续用该域名（不依赖你从哪个 Host 打开面板）。
  - 短暂重启 `s-ui`（数据面约数秒中断）；REALITY 密钥、UUID、面板监听未改。
- 备份：`/root/backup/tizi-cyp-20260710/s-ui.db.before-domain-*`
- 回滚：
  ```bash
  cp -a /root/backup/tizi-cyp-20260710/s-ui.db.before-domain-XXXXXX /usr/local/s-ui/db/s-ui.db
  systemctl restart s-ui
  ```
- 验证：
  - DNS：`cyp-tz.skysms.xyz` → `89.208.242.203`
  - `addrs` / `out_json.server` 均为 `cyp-tz.skysms.xyz`
  - `test-cyp` 链接主机为 `cyp-tz.skysms.xyz`
  - `s-ui` active，`*:443` 仍监听
- 面板操作提示（以后维护）：
  - Inbounds → `vless-reality` → **External / Addresses / 外部地址** 中应保留一行：Server=`cyp-tz.skysms.xyz`，Port=`443`。
  - 若清空该列表，S-UI 会回退为「用你打开面板时的 Host 生成链接」；本机面板在 Tailscale IP 上打开时，回退会得到 `100.88.178.78`（不可给外网用户）。


## 2026-07-10 01:17 CST - 完成代理节点部署（S-UI + firewalld + vnstat）

- 服务器：`tizi-cyp`
- 操作人：`Grok`
- 原因：按 `docs/plans/2026-07-09-001-ops-tizi-cyp-proxy-deploy-plan.md` 将本机建成与 `tizi` 同构的纯代理节点（扩容/分流，不装 Nginx/litellm）。
- 影响：
  - **系统基线**：时区 `UTC` → `Asia/Shanghai`；hostname `cute-fiber-1.localdomain` → `tizi-cyp`；安装 `firewalld`/`sqlite`/`vim-enhanced`/`epel-release`（安装脚本顺带做了一次系统 dnf update，内核等有升级）。
  - **firewalld**：`enable --now`；public 放行 `ssh` + `443/tcp`，移除默认 `cockpit`；`tailscale0` → `trusted`。
  - **S-UI 最新版 `1.5.3`**（官方 install 脚本）：数据面 `*:443` VLESS+REALITY；面板仅 `100.88.178.78:2095` path `/app/`；订阅 `127.0.0.1:2096`（用户不用订阅，不暴露）。
  - **REALITY**：SNI/dest = `assets-xbxweb.xbox.com:443`，`domain_strategy=ipv4_only`；密钥本机新生成（不复制 tizi）；测试用户 `test-cyp`（`xtls-rprx-vision`）。
  - **S-UI 面板时区**：`timeLocation=Asia/Tehran`（与 tizi 一致）。
  - **vnstat 2.9**：监控 `eth0` + `tailscale0`，已 active。
  - **cron**：每月 7 日 23:59 清零 S-UI `clients` 上下行（对齐服务商每月 8 日流量重置；套餐 2000GB）。
  - 公网暴露面：`22` + `443`；公网 `2095` 不可达（监听仅 Tailscale + firewalld 未放行）。
- 备份：`/root/backup/tizi-cyp-20260710/`（`s-ui.db.*`、firewall 列表、ss 监听、crontab）。
- 回滚方式（按需）：
  - 停代理：`systemctl disable --now s-ui`
  - 恢复 DB：从备份目录拷回 `/usr/local/s-ui/db/s-ui.db` 后 `systemctl restart s-ui`
  - 防火墙紧急：`systemctl disable --now firewalld`（仅连通性急救）
  - cron：`crontab -r` 或恢复 `root-crontab` 备份
- 变更时序：A 基线 → B firewalld → C 装 S-UI → D 绑 Tailscale 面板 + REALITY inbound → E vnstat → F cron/备份/文档。
- 验证：
  - `systemctl is-active s-ui firewalld tailscaled vnstat` → 均为 active
  - `ss -lntp`：`*:443` sui；`100.88.178.78:2095` sui；`127.0.0.1:2096` sui
  - 本机经 Tailscale：`http://100.88.178.78:2095/app/` → HTTP 307（面板可达）
  - 公网 `89.208.242.203:2095` → 不通；`:443` / `:22` → 通
  - `firewall-cmd --get-zone-of-interface=tailscale0` → `trusted`
  - journal：`inbound/vless[vless-reality] tcp server started at [::]:443`
  - `vnstat -i eth0` 已有初始数据
- 备注：
  - 面板初始管理员账号由安装脚本随机生成，**不写入仓库**；见对话/本机密码管理器；可用 `sui admin` 重置。
  - 测试客户端分享链接与 REALITY 私钥**不入库**。
  - 计划文档：`docs/plans/2026-07-09-001-ops-tizi-cyp-proxy-deploy-plan.md`。


## 2026-07-10 00:51 CST - 复核基线：发现 Tailscale 已就绪，部署计划对齐 tizi

- 服务器：`tizi-cyp`
- 操作人：`Grok`
- 原因：制定/刷新代理节点部署计划前只读复核；对照 `tizi` 采集结果更新 `docs/plans/2026-07-09-001-ops-tizi-cyp-proxy-deploy-plan.md`。
- 影响：
  - **只读**，未改系统配置、服务、防火墙。
  - 发现 Tailscale 已安装并 online（包装于 2026-07-09 16:37 UTC）：节点名 `tizi-cyp`，IPv4 `100.88.178.78`，版本 `1.98.8`；MagicDNS `tizi-cyp.taila93443.ts.net`。
  - BBR + fq 已在 `/etc/sysctl.d/` 固化；运行时 `tcp_congestion_control=bbr`、`default_qdisc=fq`。
  - 仍未安装：firewalld、S-UI、vnstat、epel-release；时区仍为 UTC；hostname 仍为 `cute-fiber-1.localdomain`。
  - 监听面仅 `22/tcp`（sshd）与 tailscaled 本地端口；公网无 443/2095 代理服务。
- 备份：无（只读）。
- 回滚方式：无需回滚。
- 验证：
  - `ssh tizi-cyp` BatchMode 成功
  - `tailscale ip -4` → `100.88.178.78`
  - `systemctl is-active tailscaled` → active；`firewalld` / `s-ui` 未装
- 后续：按更新后的部署计划分阶段执行（A 基线 → B firewalld → C S-UI → D 面板绑 TS → E vnstat → F 文档/cron），危险步骤仍需先确认。



## 2026-07-09 13:56 CST - 禁用 SSH 密码登录

- 服务器：`tizi-cyp`
- 操作人：`Grok`
- 原因：公钥登录已可用，关闭密码认证以降低暴力破解与密码泄露后的登录风险。
- 影响：
  - `/etc/ssh/sshd_config` 中 `PasswordAuthentication yes` → `no`。
  - 生效配置（`sshd -T`）：`passwordauthentication no`，`kbdinteractiveauthentication no`，`pubkeyauthentication yes`，`permitrootlogin yes`。
  - 仅保留公钥登录；root 仍可通过密钥登录。
  - 未改端口、防火墙、`PermitRootLogin`、PAM 策略；`systemctl reload sshd`（未 restart）。
- 备份：`/etc/ssh/sshd_config.bak.20260709`（改前完整副本）。
- 回滚方式：
  ```bash
  cp -a /etc/ssh/sshd_config.bak.20260709 /etc/ssh/sshd_config
  sshd -t && systemctl reload sshd
  ```
- 变更时序：
  1. 备份 `sshd_config`
  2. 将 `PasswordAuthentication` 改为 `no`，`sshd -t` 校验
  3. `systemctl reload sshd`
  4. 分别验证密钥成功、密码失败
- 验证：
  - 密钥：`ssh -o BatchMode=yes tizi-cyp 'echo KEY_OK'` → 成功
  - 密码：仅密码方式连接 → `Permission denied (publickey,gssapi-keyex,gssapi-with-mic)`（协商结果中已无 `password`）
- 备注：服务器端 root 密码本身仍可存在于系统账户，但 SSH 不再接受密码认证。

## 2026-07-09 13:53 CST - 部署本机 ed25519 公钥，启用 `ssh tizi-cyp`

- 服务器：`tizi-cyp`
- 操作人：`Grok`
- 原因：新代理节点 `89.208.242.203` 纳入本机 SSH 别名管理，后续用 `ssh tizi-cyp` 密钥登录，不再依赖 root 密码。
- 影响：
  - 将本机 `~/.ssh/id_ed25519.pub`（`konghai@konghai.me`）写入远端 `/root/.ssh/authorized_keys`。
  - 本机 `~/.ssh/config` 中已有 `Host tizi-cyp`（`HostName 89.208.242.203`，`User root`，`IdentityFile ~/.ssh/id_ed25519`，`IdentitiesOnly yes`，`PreferredAuthentications publickey`）。
  - 未修改 `sshd_config`、防火墙、系统服务；未禁用密码登录。
- 备份：安装前公钥认证失败（`Permission denied (publickey,...,password)`）；安装后 `authorized_keys` 现含 1 条本机公钥（文件权限 `600`）。
- 回滚方式：
  - 远端删除对应公钥行：`sed -i '/konghai@konghai.me/d' /root/.ssh/authorized_keys`
  - 本机删除 `~/.ssh/config` 中 `Host tizi-cyp` 段（如不再使用）
- 变更时序：
  1. 确认本机公钥与 `Host tizi-cyp` 配置
  2. 用初始 root 密码经 `ssh-copy-id` 安装公钥
  3. `ssh tizi-cyp` 免密登录验证
- 验证：
  - `ssh -o BatchMode=yes tizi-cyp 'echo OK; whoami; hostname'` → `OK` / `root` / `cute-fiber-1.localdomain`
  - 系统：AlmaLinux 9.7，内核 `5.14.0-611.55.1.el9_7.x86_64`，公网 `eth0` = `89.208.242.203/22`
- 备注：初始 root 密码仅用于一次性装钥，未写入仓库；后续已在同日记录中禁用 SSH 密码登录。
