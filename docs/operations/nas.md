# nas 运维时间线

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`nas`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN。ioc=0。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-07-26 22:09 CST - 修复 SMB：移除缺失的 VFS 模块 `trim`

- 服务器：`nas`（`konghai-nas` / `192.168.2.8`）
- 操作人：`Grok`
- 原因：密码正确仍无法连接；Finder 报检查 IP。实测认证成功后 tree connect 失败。
- 根因：`smb.custom.conf` 与共享 conf 的 `vfs objects` 含 **`trim`**，但系统无 `/usr/lib/x86_64-linux-gnu/samba/vfs/trim.so`（仅有 `trim_perms.so`）。smbd 日志：`vfs_init_custom failed for trim` → `vfs_init failed for service IPC$` / 各共享。
- 影响：修复前所有 SMB 共享（含 IPC$）不可用；修复后当前启用的共享可挂载。
- 备份：
  - `/etc/samba/smb.custom.conf.bak.20260726220847`
  - `/etc/samba/users/1000.share.conf.bak.20260726220847`
- 做了什么：
  1. 用账号 `konghai` 验证 passdb 存在、密码可过 NTLM。
  2. `smb.custom.conf`：`vfs objects = trim_perms full_audit trim` → `trim_perms full_audit`。
  3. `1000.share.conf`：去掉各共享里的 `trim`。
  4. `smbcontrol all reload-config`（smbd 保持 active）。
- 验证：
  - `smbclient -L` / 挂载 `影视-1` 列目录成功（电影、美剧等）。
  - 本机 Mac：`smbutil view` 列出 `影视-1`；`mount_smbfs` 挂载成功。
- 备注：
  - 今日约 22:05 面板将 share mode 设为 mode:3，**当前仅启用共享 `影视-1`**（原先 7 个共享被收成 1 个）。其余目录需在飞牛「文件共享 / SMB」里重新勾选。
  - 飞牛面板若再次「保存 SMB 设置」，可能把 `trim` 写回 conf；若复现，对照本条再删或补齐 `trim.so` 包。
  - **勿在文档中记录明文密码。**
- 回滚：恢复上述两个 `.bak.20260726220847` 后 `smbcontrol all reload-config`（回滚后会再次因缺 `trim.so` 而挂载失败）。

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
