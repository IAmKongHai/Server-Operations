# pve 运维操作时间线

## 2026-05-20 12:00 CST - 验证 MAS 参考环境 VM 内存调整

- 服务器：`pve`
- 操作人：`Codex`
- 原因：用户已手动调整并重启 MAS 参考环境三台 VM，需要确认 PVE 配置、guest 可见内存和关键服务状态。
- 影响：本次仅检查和记录；实际资源调整由用户已完成。当前配置提高了 `mssql-ref` 的数据库缓存空间，并压缩 `mas-win`、`mas-go-dev` 的内存上限。
- 回滚：如调整后出现内存压力或应用异常，可在维护窗口内把 VM 内存恢复到调整前配置：`mssql-ref=8192 MiB`、`mas-win=8192 MiB`、`mas-go-dev=16384 MiB`，并按 `mssql-ref -> mas-win -> mas-go-dev` 顺序重启验证。
- 变更：
  - `mssql-ref`：`memory=20480`，6 vCPU，无 balloon 配置。
  - `mas-win`：`memory=4096`，`balloon=2048`，4 vCPU。
  - `mas-go-dev`：`memory=8192`，`balloon=2048`，4 vCPU。
  - 三台 VM 均处于 `running`，并保留原有 `onboot` 与 `startup` 顺序。
- 验证：
  - PVE 宿主机内存：总计约 `31GiB`，available 约 `12GiB`，swap 使用 `0B`。
  - `mssql-ref` guest 可见内存约 `19GiB`，`mssql-server` 为 `active`，本地 SQL Server 查询返回版本 `16.0.4252.3`。
  - `mas-win` QEMU guest agent ping 正常，`192.168.2.21:9020` 和 `192.168.2.21:9021` 端口开放。
  - `mas-go-dev` guest 当前可见内存约 `5.8GiB`，Docker 容器 `icare-backend-api-1` 为 `healthy`，`mas-icare-portal` 已启动；GitHub Actions runner 服务 `actions.runner.cypressoai.mas-go-dev.service` 为 `active running`。
- 后续：
  - 观察 SQL 查询高峰时 PVE 宿主机 available memory、swap、`mssql-ref` 内 `vmstat` 的 `wa/st` 是否下降。
  - 如 `mas-go-dev` 后续 Docker build 内存不足，再考虑把其上限从 8 GiB 调回 10-12 GiB，或清理构建缓存。

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
