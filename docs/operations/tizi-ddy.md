# tizi-ddy 运维时间线

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
  - 公网暴露面：`22` +（预留）`443`；**尚无**代理 inbound 监听 `443`（需在 3x-ui 面板创建 VLESS/REALITY 等）。
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
  - 后续建议：在面板建首个 inbound（如 VLESS+REALITY `:443`）、确认订阅 listen、按需加流量重置 cron。

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
