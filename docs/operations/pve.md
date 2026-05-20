# pve 运维操作时间线

## 2026-05-20 11:04 CST - 添加同事 SSH 公钥

- 服务器：`pve`
- 操作人：`Codex`
- 原因：允许同事通过 SSH 登录 PVE 宿主机，便于后续协作处理虚拟化与 MAS 参考环境相关工作。
- 影响：`hon-2026` 对应私钥持有人可以登录 PVE 宿主机的 `root` 用户；未重启服务，未改动 VM、网络、防火墙或数据库。
- 回滚：用备份 `/root/.ssh/authorized_keys.bak.20260520-110405` 覆盖 `/root/.ssh/authorized_keys` 当前目标文件，或删除注释为 `hon-2026` 的公钥行。
- 变更：
  - 确认 `ssh pve` 登录用户为 `root`，`/root/.ssh/authorized_keys` 指向 `/etc/pve/priv/authorized_keys`。
  - 备份当前 `authorized_keys` 内容到 `/root/.ssh/authorized_keys.bak.20260520-110405`。
  - 向 `/root/.ssh/authorized_keys` 追加一条 `ssh-ed25519` 公钥，注释为 `hon-2026`。
  - 保持 `/root/.ssh` 权限为 `700`，`authorized_keys` 实际目标权限为 `600`。
- 验证：
  - `authorized_keys` 中已能精确匹配 `hon-2026` 公钥。
  - `/root/.ssh/authorized_keys` 仍是指向 `/etc/pve/priv/authorized_keys` 的符号链接。
  - `/root/.ssh` owner 为 `root:root`，权限 `700`；`authorized_keys` 实际目标 owner 为 `root:www-data`，权限 `600`，共 2 行。
- 后续：
  - 如需撤销访问，删除 `hon-2026` 对应公钥行，或恢复本次备份。
