# tizi-cyp 运维时间线

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
