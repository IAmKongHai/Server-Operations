# nas 运维时间线

## 2026-07-26 21:56 CST - Finder 连不上且无密码框：认证失败 + 清钥匙串

- 服务器：`nas` / 本机 Mac
- 操作人：`Grok`
- 原因：用户用 `smb://konghai@192.168.2.8` 仍失败，Finder 弹「连接服务器 192.168.2.8 时出现问题 / 请检查服务器名称或 IP」，**不出现密码输入框**。
- 影响：本机删除了一条钥匙串 SMB 凭据；**NAS 侧无变更**。
- 做了什么：
  1. 读 macOS 统一日志（`NetAuthSysAgent` / `mount_smbfs`）。
  2. 核对 NAS `share_service.log`、VFS 模块、`smb.custom.conf` / `1000.share.conf`。
  3. 删除本机钥匙串中 `srvr=192.168.2.8` / `acct=konghai` / `ptcl=smb` 的旧条目（创建于 2024-02-28，修改于 2026-05-01）。
- 当时状态：
  - 协议可达：`GetServerInfo` 成功；Negotiate 正常（NTLM/SPNEGO）；`OpenSession failed **80 EAUTH**`（认证错误）。Finder 把 EAUTH 显示成「检查服务器名称或 IP」，**不是网络不可达**。
  - 旧钥匙串凭据被 Finder 静默使用 → 认证失败 → 直接报错，跳过密码框。
  - 今日 NAS：`20:19`→`20:44` 内核升级重启（`6.18.18-trim` → `6.18.18.c877-trim`）；`20:44` 重建 7 个共享；用户在面板约 `21:28`/`21:31` 开关过 SMB（`appcgi.share.smb.set`）。
  - **配置隐患**：全局与每个共享 `vfs objects` 含 **`trim`，但系统无 `trim.so`**（仅有 `trim_perms.so`）。认证通过后挂载共享仍可能失败，需后续处理（改 conf 或补模块；改 conf 须确认且可能被飞牛面板覆盖）。
- 结论：当前 Finder 报错主因是 **认证失败（EAUTH）+ 过期钥匙串**；已清本机 SMB 钥匙串。请用户再连一次，应出现密码框；若密码正确仍挂不上共享，再处理缺失的 `trim` VFS。
- 回滚：钥匙串条目已删，下次成功登录会重新写入。

## 2026-07-26 21:35 CST - 只读：SMB 服务与连通性排查

- 服务器：`nas`（`konghai-nas`，LAN `192.168.2.8`，Tailscale `100.67.194.17`）
- 操作人：`Grok`（只读）
- 原因：用户反馈 `smb://192.168.2.8` 连不上，需确认 SMB 是否启动。
- 影响：无变更。
- 做了什么：
  1. SSH 检查 `smbd` / `nmbd` / `winbind` / `wsdd2` 与 TCP `139`/`445` 监听。
  2. 读 `/etc/samba/smb.conf`、`smb.custom.conf`、`/etc/samba/users/1000.share.conf`。
  3. 本机（`192.168.2.109`）对 NAS 做 ping、`nc` 445/139、`smbutil status` / `smbutil view`、Bonjour `_smb._tcp`。
- 当时状态：
  - **SMB 已启动**：`smbd` active（enabled，约 21:31 CST 起跑）、`nmbd` / `winbind` / `wsdd2` 均 running。
  - **端口**：`0.0.0.0:139`、`0.0.0.0:445` 及 IPv6 同端口在听；本机与 NAS 本地探测均成功。
  - **身份**：飞牛 TRIM Samba（Debian 12）；`security = user`，`usershare allow guests = no`；`server min protocol = SMB2`（custom 侧 `min protocol = SMB2_10`）。
  - **共享**：按用户 UID include `/etc/samba/users/%Y.share.conf`；实际文件为 `1000.share.conf`（`Photos`、`konghai的文件`、`mas-old-sqlserver`、`mas-old-windows`、`影视-1` 等）。匿名枚举会报 `NT_STATUS_BAD_NETWORK_NAME` / 找不到 `0.share.conf`，属预期。
  - **Mac 侧**：`smbutil status 192.168.2.8` → Workgroup `WORKGROUP`、Server `KONGHAI-NAS`；Bonjour 可见 `KONGHAI-NAS`；`smbutil view //192.168.2.8` → **`Authentication error`**（未带账号密码）。
- 结论：**协议栈与网络正常；“连不上”更可能是未认证 / 账号密码问题，而不是 SMB 服务未开。** 应用 NAS 用户（如 `konghai`）连接：`smb://konghai@192.168.2.8`。
- 备注：`smbftpd.service` 为 failed（与标准 smbd 无关）；非 root 无法读 `passdb.tdb` / journal，未在本轮核对 Samba 用户是否仍在 passdb。
- 回滚方式：无。
