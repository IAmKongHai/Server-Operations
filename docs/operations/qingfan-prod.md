# qingfan-prod 运维操作时间线

## 2026-11-11 23:10 CST - 撤掉 DO-1 迁移用的 hk-migrate 受限入口

- 服务器：`qingfan-prod`
- 操作人：Claude（用户确认）
- 原因：DO-1 上的 qingfan / tk-flywheel 已经彻底删除（见 `docs/operations/do-1.md` 同日条目），迁移计划写明切换后要撤掉这个入口。
- 影响：去掉 root `authorized_keys` 里只允许 `137.184.127.196` 使用的 `hk-migrate` 强制命令密钥；其它密钥（`konghai@konghai.me`、`hon-2026`、`tk-flywheel-github-deploy`）不动，业务不受影响。
- 备份：`/root/.ssh/authorized_keys.bak.20261111`；本机 `_backups/do-1-qingfan-flywheel-removal-20261111/qingfan-prod-hk-migrate.tgz`（`authorized_keys` 和两个脚本）。
- 回滚方式：`cp -p /root/.ssh/authorized_keys.bak.20261111 /root/.ssh/authorized_keys`，再从 tgz 恢复脚本。
- 做了什么：删掉 `authorized_keys` 里的 `hk-migrate` 那一行；删除 `/usr/local/sbin/hk-migrate-{recv,db}` 和 `/var/lib/hk-migrate/`（75M，是 11-09 演练留下的旧 dump）；删除临时中转目录 `/root/relay-do1-20261111`。
- 验证：新开 SSH 连接正常；`qingfan.app`、`flywheel.qingfan.app` 的 `/healthz` 都返回 200。
- 另外发现：qingfan 现在由 Docker 容器里的 `qingfan-server` 监听 `127.0.0.1:8090`（11-11 08:29 UTC 起），systemd `qingfan@blue` 是 inactive。README 的服务表还是旧写法，已标为待核实。

## 2026-11-10 11:20 CST - 只读评估是否需要启用 swap

- 服务器：`qingfan-prod`
- 操作人：`Claude`（只读排查，未做任何改动）
- 原因：用户问是否有必要启用 swap。
- 结论：现在没有必要。可以加一个小 swap 当保险，等用户决定。
- 观察：
  - 总内存 7.2G，used 约 509M，available 约 6.9G。buff/cache 6.9G 是可回收的页缓存，不算内存压力。
  - 两个应用的常驻内存都很小：`flywheel` 约 28M，`qingfan-server` 约 25M。数据库在 RDS 上，不占本机内存。
  - 内核日志里没有 OOM 记录。`vm.swappiness=60`，两个服务的 `MemoryMax` / `MemoryHigh` 都没有设置。
  - `sar` 没有历史数据，开机到现在也才 18 小时左右，所以看不到峰值。

## 2026-11-10 11:05 CST - 纳入仓库：加 ssh 别名、建档案、加同事 hon 公钥

- 服务器：`qingfan-prod`（`root@8.210.153.241`，阿里云香港）
- 操作人：`Claude`（用户要求）
- 原因：新增 qingfan 项目生产服务器，需要快捷登录、档案，并给同事 hon 开登录权限。
- 影响：只追加了一行 `authorized_keys`，没有重启任何服务。
- 备份：
  - 本机 `~/.ssh/config.bak.20261110`
  - 服务器 `/root/.ssh/authorized_keys.bak.20261110`
- 回滚方式：
  - 去掉 hon 的权限：在服务器上删掉 `authorized_keys` 里注释为 `hon-2026` 的那一行（或用备份覆盖回去）。
  - 别名：删掉本机 `~/.ssh/config` 末尾的 `Host qingfan-prod` 段。
- 做了什么：
  1. 本机 `~/.ssh/config` 追加 `Host qingfan-prod`：`HostName 8.210.153.241`、`User root`、`IdentityFile ~/.ssh/id_ed25519`、`IdentitiesOnly yes`。
  2. 只读采集系统、服务、nginx、数据库连接等信息，写成档案 `qingfan-prod/README.md`。
  3. 往 `/root/.ssh/authorized_keys` 追加 `ssh-ed25519 …HzYPDW5HZfjPj hon-2026`（追加前先检查过，没有重复）。
- 验证：
  - `ssh qingfan-prod` 能登录，`hostname` 为 `iZj6cfbbt4l6yxdiqkoqnfZ`。
  - `authorized_keys` 现在有 4 行：`konghai@konghai.me`、`tk-flywheel-github-deploy`、`hk-migrate`、`hon-2026`，权限 `600 root:root`；`ssh-keygen -lf` 解析出 hon 公钥指纹 `SHA256:t5JxvwYZEe9z6KOnXyd08lYm/3rRTIrfzSM8J1k3e+0`。
  - hon 那边能不能登录还需要同事自己验证一次。
