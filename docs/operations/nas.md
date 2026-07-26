# nas 运维时间线

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
