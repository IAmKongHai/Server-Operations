# mssql-ref 运维操作时间线

## 2026-05-20 11:19 CST - 修正本机 known_hosts 中的旧主机指纹

- 服务器：`mssql-ref`
- 操作人：`Codex`
- 原因：本机执行 `ssh ubuntu@192.168.2.20` 时提示 `REMOTE HOST IDENTIFICATION HAS CHANGED`，`/Users/konghai/.ssh/known_hosts` 中保存的旧 `192.168.2.20` 主机 key 与当前 VM 返回的 key 不一致。
- 影响：仅修改本机 `/Users/konghai/.ssh/known_hosts` 中 `192.168.2.20` 的主机 key 记录；未改动 VM、SQL Server、PVE 网络或 SSH 服务端配置。
- 回滚：恢复本机备份 `/Users/konghai/.ssh/known_hosts.bak.20260520-111913`，或使用 `ssh-keygen -R 192.168.2.20 -f /Users/konghai/.ssh/known_hosts` 后重新按可信指纹录入。
- 变更：
  - 从 PVE 宿主机确认 VM `110 / mssql-ref` 的网卡 MAC 为 `BC:24:11:CC:BE:98`。
  - 从 PVE 宿主机 `ip neigh show 192.168.2.20` 确认该 IP 对应 MAC 为 `bc:24:11:cc:be:98`。
  - 从 PVE 宿主机 `ssh-keyscan` 获取当前 `192.168.2.20` 的 ECDSA、RSA、ED25519 host keys。
  - 备份本机 `/Users/konghai/.ssh/known_hosts` 到 `/Users/konghai/.ssh/known_hosts.bak.20260520-111913`。
  - 删除本机旧的 `192.168.2.20` 三条 host key 记录，并写入 PVE 侧扫描到的新记录。
- 验证：
  - 新 ED25519 指纹为 `SHA256:FxesIaPzL0z1U3ZtG7HyUXTqbuhz7i04mw3QdLxxgHc`，与 SSH 报错中远端返回的指纹一致。
  - 新 ECDSA 指纹为 `SHA256:lt/NiNQ1Rct+A90rerWG1g90S9KmCgQiwu2fQ0yuumU`。
  - 新 RSA 指纹为 `SHA256:OrUZU7zsRfBovUnl7XwoBSv73M5+MRZtb/37xhJSmls`。
  - 使用 `StrictHostKeyChecking=yes` 重新执行 `ssh ubuntu@192.168.2.20` 成功，返回 `login-ok user=ubuntu host=mssql-ref`。
- 后续：
  - 如果其它机器也遇到同样报错，应先用 PVE 宿主机侧 MAC 和 host key 指纹交叉确认，再更新对应客户端的 `known_hosts`。

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
