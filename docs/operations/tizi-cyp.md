# tizi-cyp 运维时间线

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
- 备注：初始 root 密码仅用于一次性装钥，未写入仓库；建议后续在密码管理器中轮换，并视需要再收紧 `sshd`（例如禁用密码登录）。
