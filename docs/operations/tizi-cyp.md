# tizi-cyp 运维时间线

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
