# pve 运维操作时间线

## 2026-05-28 09:45 CST - 添加同事 SSH 公钥到 mas-go-dev

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Codex`
- 原因：允许同事通过 SSH 登录 `ec2-user@192.168.2.22`，便于协作处理 MAS Go + React 内网自动部署环境。
- 影响：`hon-2026` 对应私钥持有人可以登录 `ec2-user` 用户；未重启服务，未改动 Docker、GitHub Actions runner、数据库、网络或防火墙。
- 回滚：用备份 `/home/ec2-user/.ssh/authorized_keys.bak.20260528-0945-hon-2026` 覆盖 `/home/ec2-user/.ssh/authorized_keys`，或删除注释为 `hon-2026` 的公钥行。
- 变更：
  - 备份 `/home/ec2-user/.ssh/authorized_keys` 到 `/home/ec2-user/.ssh/authorized_keys.bak.20260528-0945-hon-2026`。
  - 向 `/home/ec2-user/.ssh/authorized_keys` 追加一条 `ssh-ed25519` 公钥，注释为 `hon-2026`。
  - 保持 `/home/ec2-user/.ssh` 权限为 `700`，`authorized_keys` 权限为 `600`。
- 验证：
  - `authorized_keys` 中已能精确匹配 `hon-2026` 公钥。
  - `/home/ec2-user/.ssh/authorized_keys` 权限为 `600`，共 2 行。

## 2026-05-20 16:03 CST - 修复 mas-go-dev 前端本地 Docker build OOM

- 服务器：`pve`
- 操作人：`Codex` + 用户手动重启 VM
- 原因：`iCare-frontend-mas` 的 `Deploy to mas-go-dev` job 在 `docker build` 阶段执行 `npm run build`，Node 报 `JavaScript heap out of memory`。排查发现 VM `130/mas-go-dev` 配置为 `memory=8192`，但 `balloon=2048`，guest 实际只看到约 `2.1GiB` 内存，导致 Vite/TypeScript 构建堆空间不足。
- 影响：将 `mas-go-dev` 的 balloon 下限提高到 8 GiB，并由用户重启 VM 使配置生效；重启期间 `mas-go-dev` 后端、前端和 GitHub Actions runner 短暂中断。未修改数据库、网络、防火墙或应用代码。
- 回滚：
  - 快速回滚：`qm set 130 --balloon 2048`，然后在维护窗口重启 VM 130。
  - 配置文件回滚：参考备份 `/etc/pve/qemu-server/130.conf.bak.20260520-oom`。
- 变更：
  - 备份 `/etc/pve/qemu-server/130.conf` 到 `/etc/pve/qemu-server/130.conf.bak.20260520-oom`。
  - 执行 `qm set 130 --balloon 8192`，使 VM 130 配置变为 `memory=8192`、`balloon=8192`。
  - 尝试 QMP 热调整运行态 balloon，未能让 guest 立即释放到 8 GiB；随后用户手动重启 VM 130。
- 验证：
  - PVE 运行态显示 `balloon=8589934592`、`balloon_min=8589934592`、`maxmem=8589934592`。
  - `mas-go-dev` guest 可见内存约 `7.7GiB`，无 swap。
  - `actions.runner.cypressoai.mas-go-dev.service` 为 `active running`，并已连接 GitHub。
  - Docker 服务为 `active`，`icare-backend-api-1` 为 `healthy`，`mas-icare-portal` 已启动。
  - `http://127.0.0.1:5174/healthz` 返回 `ok`。
  - `http://127.0.0.1:5174/api/v1/health` 返回 `code=200`、database `up`。
  - 重新运行 GitHub Actions failed job 后，`iCare-frontend-mas` run `26147661747` 变为 `success`，新的 `Deploy to mas-go-dev` job `76913376725` 成功完成。
- 后续：
  - 暂不启用 swap；8 GiB 固定内存已解决本次 Node build OOM。若后续仍出现偶发 OOM，再考虑在 guest 内添加 4 GiB swap 作为兜底。
  - 观察 PVE 宿主机 available memory，避免多台 VM 高峰期同时吃满物理内存。

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
