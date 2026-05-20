# mssql-ref 运维操作时间线

## 2026-05-20 10:52 CST - 添加同事 SSH 公钥

- 服务器：`mssql-ref`
- 操作人：`Codex`
- 原因：允许两位同事通过 SSH 登录 `ubuntu@192.168.2.20`，便于访问 PVE 上的 MAS 老系统 MSSQL 参考数据库 VM。
- 影响：`hon-2026` 和 `m@cypresso.ai` 对应私钥持有人可以登录 `ubuntu` 用户；未改动 SQL Server、VM、网络或系统服务。
- 回滚：用备份 `/home/ubuntu/.ssh/authorized_keys.bak.20260520-025140` 覆盖 `/home/ubuntu/.ssh/authorized_keys`，并保持权限 `600`。
- 变更：
  - 备份 `/home/ubuntu/.ssh/authorized_keys` 到 `/home/ubuntu/.ssh/authorized_keys.bak.20260520-025140`。
  - 向 `/home/ubuntu/.ssh/authorized_keys` 追加两条 `ssh-ed25519` 公钥，注释分别为 `hon-2026` 和 `m@cypresso.ai`。
  - 保持 `/home/ubuntu/.ssh` 权限为 `700`，`authorized_keys` 权限为 `600`。
- 验证：
  - `authorized_keys` 中已能精确匹配 `hon-2026` 和 `m@cypresso.ai` 两条公钥。
  - `/home/ubuntu/.ssh` owner 为 `ubuntu:ubuntu`，权限 `700`。
  - `/home/ubuntu/.ssh/authorized_keys` owner 为 `ubuntu:ubuntu`，权限 `600`，共 3 行。
- 后续：
  - 如需撤销访问，删除对应注释的公钥行，或直接恢复本次备份。
