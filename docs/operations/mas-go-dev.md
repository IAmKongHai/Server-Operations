# mas-go-dev 运维操作时间线

## 2026-07-05 00:16 CST - 在线扩展根分区与 XFS 到 300G

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`）
- 操作人：`Codex`
- 原因：PVE 侧已按确认方案将 VM `130` 的 `scsi0` 从 120G 扩到 300G；需要在 guest 内扩展根分区与 XFS 文件系统，让新增容量可用。
- 影响：
  - `/dev/sda1` 从 `120G` 在线扩展到 `300G`。
  - 根文件系统 `/` 从 `120G` 扩到 `300G`，可用空间约 `189G`，使用率从扩容前约 `93%` 降到 `38%`。
  - 未重启 VM，未重启 runner，未重启 Docker 或业务容器。
- 变更：
  1. 扩容前 guest 已识别整盘 `/dev/sda` 为 `300G`，但 `/dev/sda1` 仍为 `120G`。
  2. 执行 SCSI rescan 与 `partprobe`；`fdisk` 显示 GPT backup table 不在磁盘末尾，这是磁盘刚扩容后的预期状态。
  3. 执行 `sudo growpart /dev/sda 1`，`/dev/sda1` 从 `251633631` sectors 扩到 `629120991` sectors。
  4. 执行 `sudo xfs_growfs /`，XFS data blocks 从 `31454203` 扩到 `78640123`。
- 验证：
  - `lsblk`：`sda` `300G`，`sda1` `300G`，`sda127` `1M`，`sda128` `10M`。
  - `df -hT /`：`/dev/sda1` `xfs`，`300G`，已用约 `112G`，可用约 `189G`，使用率 `38%`。
  - 再次 `fdisk -l /dev/sda` 不再出现 GPT PMBR / backup GPT mismatch 警告。
  - 3 个 runner service 均为 `active`：`mas-go-dev`、`mas-go-dev-ci-1`、`mas-go-dev-ci-2`。
  - `docker system df`：Build Cache 又有约 `953.8MB` 可回收，属 CI 后续重新生成缓存，当前空间充足无需处理。
- 回滚说明：XFS 与分区已在线扩展，不能直接无损缩回；如后续需要调整容量，应另行规划迁移或重建磁盘。

## 2026-07-05 00:08 CST - 只读确认 Go testcache 可复用，清 testcache 不适合做磁盘治理

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`）
- 操作人：`Codex`
- 原因：用户进一步确认 iCare backend coverage CI 产生的 Go testcache 下次是否真的用不上；若用不上才考虑每次 CI 结束自动清理测试结果缓存。
- 影响：本次仅读取 VM 上 Go 1.25.7 的帮助文本与源码，不执行测试、不清理缓存、不修改 VM 配置。
- 结论：
  - 当前 coverage 测试结果缓存**不是确定用不上**。Go 1.25.7 文档与源码明确把 `-coverprofile` 列为 cacheable test flag；`-coverpkg` / `-covermode` 影响 test binary / build action ID，若源码、测试输入、环境变量、文件输入和相关 flag 一致，后续运行可以命中 testcache，并恢复测试输出与 coverage profile。
  - 因此不应把“每次 CI 完自动 `go clean -testcache`”作为常规优化；这会牺牲可复用的测试结果缓存。
  - `go clean -testcache` 也不是释放磁盘空间的有效手段：Go 源码 `cmd/go/internal/clean/clean.go` 中它只是写 `testexpire.txt`，让旧测试结果过期，并不会遍历删除大块 cache 文件。真正占 `65G+` 的主要是 Go build cache 编译产物。
- 关键依据：
  - `cmd/go/internal/test/test.go`：package list mode 下 successful package test results 可缓存；cacheable test flags 包含 `-coverprofile`。
  - `cmd/go/internal/test/test.go`：`saveOutput` 会在 `testCoverProfile != ""` 时把 coverage profile 存入 cache key。
  - `cmd/go/internal/clean/clean.go`：`-testcache` “expire all test results”，实现是写 `testexpire.txt`，不是删除整个 build cache。
- 后续判断：
  - 如果目标是保留 CI 速度，正确方向不是每次清 testcache，而是扩容 VM 磁盘，并保留 Go module cache 与大部分 Go build cache。
  - 仍可做阈值兜底：当根分区接近打满时再执行有损性能的缓存清理，避免 runner 再次假活。

## 2026-07-04 23:56 CST - 回收 Docker build cache 并分析 Go build cache 膨胀原因

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`）
- 操作人：`Codex`
- 原因：上一条排查确认 Docker build cache 约 `8.792G` 可回收，用户确认先回收该部分；同时要求继续分析 `/home/actions-runner/.cache/go-build` 为什么涨到约 `65G`，以及后续如何避免无限膨胀。
- 影响：
  - 执行 `docker builder prune -af`，删除 BuildKit 本地构建缓存，不影响当前运行容器、镜像和 volume。
  - 后续 Docker build 首次重建会变慢；被删构建缓存无法原样回滚，但可由后续 build 自动再生成。
  - 未清理 Go build cache，未重启 runner，未修改 systemd / crontab / workflow。
- 变更：
  - 清理前 `docker system df`：`Build Cache 334` 项，`8.792GB`，全部可回收。
  - `docker builder prune -af` 实际回收 `8.843GB`。
  - 清理后 `docker system df`：`Build Cache 1` 项，`659B`，`0B` 可回收。
- 验证：
  - 根分区从 `120G 100%` 降到 `120G 90%`，可用空间约 `13G`。
  - inode 从 `95%` 降到 `4%` 使用。
  - 清出空间后，`mas-go-dev` 与 `mas-go-dev-ci-1` 重新出现 `Runner.Listener`；3 个 runner service 均为 `active (running)`。当时 `mas-go-dev` / `mas-go-dev-ci-1` 已开始承接 Go CI 任务。
- Go build cache 分析：
  - Go binary 来自 runner toolcache：`/opt/actions-runner/mas-go-dev-ci-1/_work/_tool/go/1.25.7/x64/bin/go`，版本 `go1.25.7`。
  - `GOCACHE=/home/actions-runner/.cache/go-build`，`GOMODCACHE=/home/actions-runner/go/pkg/mod`。
  - Go 源码 `cmd/go/internal/cache/cache.go` 里当前策略是：缓存文件每次使用后最多每小时更新一次 `mtime`，每天最多 trim 一次，只删除至少 `5 days + 1 hour` 未使用的 cache entry。
  - 本机根分区虽然是 `noatime`，但该 Go 版本使用的是 `mtime` 标记最近使用，不是文件系统 `atime`；`noatime` 不是主因。
  - `/home/actions-runner/.cache/go-build` 当时约 `65G`、约 `216k` 个文件。按 `mtime` 聚合：`2026-06-28` 约 `1.95G`、`06-29` 约 `14.24G`、`06-30` 约 `8.78G`、`07-01` 约 `9.15G`、`07-02` 约 `12.38G`、`07-03` 约 `1.02G`、`07-04` 约 `16.81G`；超过 7 天的只有 2 个小文件。
  - 当前 runner 正在跑 iCare backend 的覆盖率测试：`go test ./test/... ./internal/... -coverprofile=coverage.out -covermode=atomic -coverpkg=./cmd/...,./internal/...`。这种全量覆盖率插桩会生成大量编译产物；多个 runner 共享同一个 `actions-runner` 用户家目录下的 `GOCACHE`，高频 CI 又会持续刷新这些产物的 `mtime`，所以 Go 自带的“5 天未用再删”很难把缓存压下来。
  - iCare backend workflow 里 `actions/setup-go@v5` 已设置 `cache: false`；问题不是 GitHub Actions 远端 cache，而是 self-hosted runner 本机的 Go build cache。
- 后续建议（需用户确认后再执行）：
  1. 立即止血：等当前 Go CI 任务结束后，以 `actions-runner` 身份执行 Go cache 清理，例如用当前 toolcache 里的 Go binary 跑 `go clean -cache -testcache`，或直接清空 `/home/actions-runner/.cache/go-build`。这会让后续 Go 构建变慢，但缓存可再生成。
  2. 防止复发：在 iCare backend 的重型 CI job 里设置 job-local `GOCACHE`，例如 `GOCACHE=${{ runner.temp }}/go-build`，让覆盖率测试产物随 job temp 生命周期回收，代价是减少跨 job 编译缓存复用。
  3. 服务器兜底：增加一个 systemd timer（或经确认后再用 crontab）定期检查 `/home/actions-runner/.cache/go-build` 和根分区占用，超过阈值时跑 `go clean -cache -testcache`，并可顺手跑 `docker builder prune -af --filter until=168h`。

## 2026-07-04 23:50 CST - 只读排查 GitHub Actions runner 假活，根因为根盘 100%

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`）
- 操作人：`Codex`
- 原因：用户询问 VM 上的 self-hosted GitHub Actions runner 是否已经死掉。
- 影响：本次仅做只读排查，未重启 runner、未清理文件、未改 Docker / systemd / 应用配置。
- 结论：
  - 3 个 runner systemd service 均显示 `active (running)`，但并不代表健康。
  - `mas-go-dev` 与 `mas-go-dev-ci-1` 只剩 `runsvc.sh` + `RunnerService.js`，没有稳定的 `Runner.Listener`；`mas-go-dev-ci-2` 当时仍有一个 `Runner.Listener`，但日志同样出现过反复退出。
  - 直接根因是根分区 `/dev/sda1` 已满：`120G` 用满、只剩 `16K`，inode 使用率 `95%`。runner 写 `_diag/Runner_*.log` 时持续报 `System.IO.IOException: No space left on device`，导致 listener 退出后反复重拉，属于“systemd 假活 / runner 不可靠”。
- 只读排查结果：
  - `/home` 约 `67G`，其中 `/home/actions-runner/.cache` 约 `65G`，全部集中在 Go build cache：`/home/actions-runner/.cache/go-build`。
  - `/var` 约 `34G`，主要是 `/var/lib/docker`：`volumes` 约 `17G`、`overlay2` 约 `16G`、Docker build cache 约 `8.792G` 可回收。
  - `/opt/actions-runner` 约 `8.0G`，其中 3 个 runner 的 `_diag` 合计约 `523M`，不是主因。
  - `/var/log` 约 `319M`，journal 约 `287.8M`，容器 json 日志约 `7M`，不是主因。
- 回滚方式：本次无服务器变更，无需回滚。
- 后续建议（需用户确认后再执行）：
  1. 优先清理 `/home/actions-runner/.cache/go-build`，这是最大且最像可再生缓存的占用。
  2. 视情况执行 Docker build cache 清理（`docker builder prune` / `docker buildx prune`），预计可回收约 `8.8G`。
  3. 清出空间后重查 3 个 runner 是否都恢复 `Runner.Listener`；如未恢复，再确认是否重启 runner service。

## 2026-07-02 11:53 CST - 安装 go-sqlcmd v1.10.0（连 MSSQL 参考库排查用）

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`），Amazon Linux 2023，x86_64
- 操作人：`Claude`
- 原因：偶尔需要从 mas-go-dev 直连内网 MSSQL（如 `mssql-ref` `192.168.2.20`）做只读排查，此前机器上没有任何 SQL 客户端。
- 选型：装微软新版 **go-sqlcmd**（`microsoft/go-sqlcmd` 官方 release 单静态二进制），而非 `mssql-tools18`。理由：单文件、零依赖，不引入 unixODBC/msodbcsql18 仓库、不污染系统，对"偶尔排查用"最省事。代价是**不带 `bcp`**——若日后要批量导入导出再补装 `mssql-tools18`。
- 影响：
  - 新增 `/usr/local/bin/sqlcmd`（v1.10.0，0755，root 属主），无其它系统改动，未加 yum 仓库、未装依赖包。
  - 纯客户端工具安装，不影响任何容器 / runner / 生产服务。
- 备份 / 回滚方式：无需备份（新增文件而非改配置）。回滚即 `sudo rm /usr/local/bin/sqlcmd`。
- 变更（按时序）：
  1. 确认系统 AL2023 / x86_64，机器上无 sqlcmd/bcp、无 mssql 仓库。
  2. 从 GitHub API 取最新 tag `v1.10.0`，下载 `sqlcmd-linux-amd64.tar.bz2` 到 `/tmp` 并解压（得单个 `sqlcmd` 二进制 + `sqlcmd_debug`）。
  3. `sudo install -m 0755 /tmp/.../sqlcmd /usr/local/bin/sqlcmd`。
  4. 清理 `/tmp` 下载与解压临时文件。
- 验证：
  - `sqlcmd --version` → `v1.10.0` ✅。
  - 到 `mssql-ref`（`192.168.2.20:1433`）TCP 端口可达。
  - 用错误密码探测：sqlcmd 完成 TLS+TDS 握手，服务端返回明确的 `Login failed for user 'mas_ref_owner'`——证明工具、加密（`-C` 信任自签证书）、网络链路全通，换正确密码即可查询。
- 用法提示：go-sqlcmd 默认强制加密，连自签证书的 MSSQL **必须带 `-C`**（信任服务器证书），否则证书报错：
  ```bash
  sqlcmd -S 192.168.2.20 -U mas_ref_owner -P '<密码>' -C -d <库名> -Q "SELECT TOP 10 * FROM ..."
  ```

## 2026-07-02 02:45 CST - Redis 端口映射增绑 tailscale IP 并关闭 protected-mode，本机免隧道直连

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`）
- 操作人：`Claude`
- 原因：延续同日 Azurite 的做法（见下条），想在本机（tailnet 内）直连 mas-go-dev 的 Redis 做集成测试排查（查看 asynq 队列、worker 注册、失败统计等），免去每次开 SSH 隧道。原先 `redis` 容器端口只映射到 `127.0.0.1:6379`，VM 外部无法直连。
- 安全权衡（**经用户确认**）：此 Redis **无密码**（`requirepass` 为空）。用户判断 tailnet 内只有少数开发同事、可信，接受不加密码。**因此这是有意为之的暴露**：tailnet 内任何成员无需认证即可读写/清空（`FLUSHALL`）该 Redis 及其中的 asynq 队列数据。风险边界：仅限 tailnet（未绑 `0.0.0.0`），公网与 PVE 内网 `192.168.2.x` 均连不到；且是开发测试环境、非生产。若日后 tailnet 成员范围扩大或数据敏感度提高，应补 `requirepass`。
- 关键点 —— 必须关 protected-mode：Redis 7 在「绑定非回环地址 + 无密码」时，protected-mode 默认会**拒绝**非本地连接。故仅改端口映射不够，须在 `command` 显式加 `--protected-mode no`，否则 tailnet 直连会被拒。这是与 Azurite 那次的差异（Azurite 无此机制）。
- 影响：
  - `/opt/mas-go-dev/infra/infra.compose.yaml` 的 `redis` 服务：
    - `command` 由 `["redis-server","--appendonly","yes"]` 改为追加 `"--protected-mode","no"`。
    - `ports` 段在原 `127.0.0.1:6379:6379` 基础上**新增** `100.109.223.53:6379:6379`（保留回环）。
  - 以 `actions-runner` 身份 `docker compose up -d` 重建 **redis 一个容器**；`azurite` 保持 Running 未动。
  - 数据卷 `redis-data` 保留（AOF 持久化），队列数据未丢。
  - 不碰 api / worker（它们经 Docker DNS 名 `redis:6379` 走 `shared-services` 内网访问），不触发 runner / 部署流程。
- 备份：
  - `/opt/mas-go-dev/infra/infra.compose.yaml.bak.20260702-redis`（以 `actions-runner` 身份 `cp -a`，含上一条 azurite 改动，2384 字节）。
- 回滚方式：
  ```bash
  ssh mas-go-dev
  sudo cp /opt/mas-go-dev/infra/infra.compose.yaml.bak.20260702-redis /opt/mas-go-dev/infra/infra.compose.yaml
  sudo -u actions-runner docker compose -f /opt/mas-go-dev/infra/infra.compose.yaml up -d
  ```
- 变更（按时序）：
  1. `sudo cp -a infra.compose.yaml infra.compose.yaml.bak.20260702-redis`。
  2. 用 Python 精确替换整个 `redis` 服务段（按内容匹配，非按行号）：`command` 追加 `--protected-mode no`，`ports` 增绑 tailscale IP，各加一行注释。
  3. `sudo diff` → 仅 command 1 行改写 + ports 新增 1 行 + 注释 2 行。
  4. `sudo -u actions-runner docker compose config --quiet` 校验语法 OK。
  5. `sudo -u actions-runner docker compose up -d` → `redis Recreated/Started`，`azurite Running`（未动）。
- 验证：
  - `docker ps` → redis 端口 `100.109.223.53:6379->6379, 127.0.0.1:6379->6379`。
  - `ss -tlnp` → 宿主同时监听 `100.109.223.53:6379` 与 `127.0.0.1:6379`。
  - **从本机（无 SSH 隧道）** `redis-cli -h 100.109.223.53 -p 6379 PING` → `PONG` ✅；`INFO server` → Redis 7.4.9；`DBSIZE` → 20 keys；`--scan asynq*` 可见 asynq 队列数据（worker 注册、各队列 processed/failed 统计）。全程只读，未改数据。
- 遗留 / 待办：
  - 本机源文件 `~/Code_local/Project/iCare/backend/infra.compose.yaml`（`backend/` 是独立 git 子仓库）已同步 azurite + redis 两处改动，**未提交**；由用户自行开 PR（base 到活跃分支 `develop`）固化。

## 2026-07-02 02:30 CST - Azurite 端口映射增绑 tailscale IP，本机免隧道直连 Blob

- 服务器：`mas-go-dev`（`100.109.223.53` / 原 `192.168.2.22`）
- 操作人：`Claude`
- 原因：想在本机（tailnet 内）直连 `mas-go-dev` 的 Azurite Blob 模拟器做集成测试排查，方便用 Azure Storage Explorer / 脚本读写测试容器。原先 `azurite` 容器端口只映射到 `127.0.0.1:10000`，VM 外部（含本机）无法直连，每次都得先手动开 `ssh -L 10000:127.0.0.1:10000 mas-go-dev` 隧道，容易忘、忘了就连不上。容器内部本已 `--blobHost 0.0.0.0`，限制只在宿主端口绑定那一行，故只需在端口映射上增绑 tailscale IP 即可。
- 影响：
  - `/opt/mas-go-dev/infra/infra.compose.yaml` 的 `azurite` 服务 `ports` 段，在原 `127.0.0.1:10000:10000` 基础上**新增一行** `100.109.223.53:10000:10000`（保留回环绑定不动）。
  - 以 `actions-runner` 身份 `docker compose -f infra.compose.yaml up -d` 重建 **azurite 一个容器**；`redis` 保持 Running 未动。
  - 数据卷 `azurite-data` 保留，测试容器/blob 数据未丢。
  - **未绑 `0.0.0.0`**：只在 tailnet（`100.109.223.53`）+ 回环监听，PVE 内网 `192.168.2.x` 与公网均连不到。
  - 不碰 api / worker（它们经 Docker DNS 名 `azurite:10000` 走 `shared-services` 内网访问，与宿主端口映射无关），不触发 runner / 部署流程。
- 安全说明：Azurite 用的是**公开固定测试密钥**（`devstoreaccount1` / `Eby8vdM0...`，微软官方文档公开），tailnet 内任何成员即可读写 `mas`/`temp` 等**集成测试实际数据**，写删需谨慎。仅因限定在 tailnet 内网、且是开发测试环境，风险可接受。
- 备份：
  - `/opt/mas-go-dev/infra/infra.compose.yaml.bak.20260702`（以 `actions-runner` 身份 `cp -a` 保留权限/归属，与原文件同为 2313 字节）。
- 回滚方式：
  ```bash
  ssh mas-go-dev
  sudo cp /opt/mas-go-dev/infra/infra.compose.yaml.bak.20260702 /opt/mas-go-dev/infra/infra.compose.yaml
  sudo -u actions-runner docker compose -f /opt/mas-go-dev/infra/infra.compose.yaml up -d
  ```
- 变更（按时序）：
  1. `sudo cp -a infra.compose.yaml infra.compose.yaml.bak.20260702`。
  2. 用 Python 精确替换 `azurite` 的 `ports` 段（按整段内容匹配，非按行号），新增 `- "100.109.223.53:10000:10000"` 并更新上方注释。
  3. `sudo diff` 备份与新文件 → 仅注释 1 行改写 + 新增端口 1 行。
  4. `sudo -u actions-runner docker compose -f infra.compose.yaml config --quiet` 校验语法 OK。
  5. `sudo -u actions-runner docker compose -f infra.compose.yaml up -d` → `azurite Recreated/Started`，`redis Running`（未动）。
- 验证：
  - `docker ps` → azurite 端口为 `100.109.223.53:10000->10000, 127.0.0.1:10000->10000`。
  - `ss -tlnp` → 宿主同时监听 `100.109.223.53:10000` 与 `127.0.0.1:10000`。
  - **从本机（无任何 SSH 隧道）** 用共享密钥签名请求 `http://100.109.223.53:10000/devstoreaccount1?comp=list` → HTTP 200，列出全部 10 个容器（`group-account-contract-ledger`、`mas`、`temp`、`test-404`、`test-copy-move`、`test-ctype`、`test-presign`、`test-roundtrip`、`test-slash`、`test-traversal`）✅。
  - 本机连接串（tailnet 内直接可用）：`DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=Eby8vdM0...;BlobEndpoint=http://100.109.223.53:10000/devstoreaccount1;`。
- 遗留 / 待办：
  - 本次只改了 **VM 上**的 `infra.compose.yaml`。源文件受 git 管理，在 **`iCare/backend/` 这个独立子仓库**里（`~/Code_local/Project/iCare/backend/infra.compose.yaml`；注意它不属于外层 `iCare` 仓库——外层 `.gitignore` 忽略了 `backend/`，故在外层仓库看不到）。已在该子仓库同步改动、未提交，由用户自行开 PR（base 到 `develop`）固化。

## 2026-07-01 13:07 CST - 修复 worker 漏配 reports 队列（潜伏问题，尚未堆积）

- 服务器：`mas-go-dev`（`192.168.2.22`）
- 操作人：`Claude`
- 原因：同日在 `dev-cypresso` 定位到 worker `.env` 里 `WORKER_QUEUES=default:1` 覆盖了代码默认值、导致 Report Center 报表任务卡死（见 `docs/operations/dev-cypresso.md` 2026-07-01 12:25），排查 `mas-go-dev` 是否同病。结果 `mas-go-dev` **同样中招**：worker 只监听 `default`、不监听 `reports`。代码默认队列是 `internal/config/config.go:210` `{"default":1,"reports":1}`，只要不设 `WORKER_QUEUES` 就该监听两个。区别是 `mas-go-dev` 当前 `reports`/`default` 队列都是 0 堆积——不是没问题，而是**还没人在这台上触发过 Report Center 报表任务**，属潜伏雷；一旦有人用报表功能，任务会入 `reports` 队列但无人消费、永久卡 pending。趁修 dev-cypresso 一并根除。
  - 附带确认：`mas-go-dev` 的 Azurite **不缺 container**——`mas`（及历史 `group-account-contract-ledger`、若干 `test-*`）均已存在、已有 25 个 blob，上传存文件链路正常，无 dev-cypresso 那个 500 问题。故本次只需修 worker 队列一项。
- 影响：
  - `/opt/mas-go-dev/backend/.env.docker` 删除 `WORKER_QUEUES=default:1` 一行（文件归 `actions-runner`、保持 `600` 权限）。
  - 重建 `icare-backend-worker-1` 容器（`.env` 改动须 recreate 才重读 env_file）。
  - 只重建 worker 一个容器；不动 api / seed / gotenberg / azurite / redis / mas-icare-portal，**不碰 self-hosted GitHub Actions runner、不触发部署流程**。
- 备份：
  - `/opt/mas-go-dev/backend/.env.docker.bak.20260701-worker-queues`（以 `actions-runner` 身份 `cp -p` 保留权限/归属）。
- 回滚方式：
  ```bash
  sudo -u actions-runner cp /opt/mas-go-dev/backend/.env.docker.bak.20260701-worker-queues /opt/mas-go-dev/backend/.env.docker
  sudo -u actions-runner env BACKEND_IMAGE=icare/backend:mas-go-dev-eaeecd6055a799cc662344f419836e99b8878644 \
    sh -c 'cd /opt/mas-go-dev/backend && docker compose -f backend.compose.yaml up -d --no-deps --no-build worker'
  ```
- 变更（按时序）：
  1. `sudo -u actions-runner cp -p .env.docker .env.docker.bak.20260701-worker-queues`。
  2. `sudo -u actions-runner sed -i '/^WORKER_QUEUES=default:1$/d' .env.docker`（按整行内容精确删除，非按行号）。
  3. `diff` 备份与新文件 → 仅少 `WORKER_QUEUES=default:1` 一行。
  4. 重建 worker：`sudo -u actions-runner env BACKEND_IMAGE=icare/backend:mas-go-dev-eaeecd6055a799cc662344f419836e99b8878644 sh -c 'cd /opt/mas-go-dev/backend && docker compose -f backend.compose.yaml up -d --no-deps --no-build worker'`。
  - 与 dev-cypresso 的操作差异：配置目录 `/opt/mas-go-dev/backend/`（归 actions-runner，读写都需 `sudo -u actions-runner`）；用 `docker compose` **插件**（v2.24.5，非独立 `docker-compose`）；镜像是本地 tag `icare/backend:mas-go-dev-eaeecd60...`（非 dev-cypresso 的 ghcr tag）。`cd` 必须在 `sudo -u actions-runner sh -c` 上下文里做，否则外层 ec2-user 无权限进目录。
- 验证：
  - worker 新日志：`starting worker ... queues="map[default:1 reports:1]" concurrency=1` → `asynq: Starting processing`——已监听 reports ✅。
  - `docker exec icare-backend-worker-1 env | grep WORKER_QUEUES` → 空（已回退代码默认）。
  - 容器 `Up`，健康。
  - 注：`asynq:queues` 集合此刻仍只有 `default`——正常。该集合由**入队方**投递首个任务时才写入，`mas-go-dev` 从未有人投过 `reports` 任务故集合无 `reports`；worker 是否消费取决于其服务器注册（`asynq:servers`），已由启动日志的 `map[default:1 reports:1]` 证实。将来一旦有报表任务入队即会被消费。

## 2026-06-22 19:05 CST - 给 VM 增加 swap 并为 3 个 runner 加 OOM 后自动恢复

- 服务器：`mas-go-dev`（`192.168.2.22`）
- 操作人：`Codex`
- 原因：`actions.runner.cypressoai.mas-go-dev-ci-1.service` 在 `2026-06-22 16:42 CST` 跑 `SonarQube Scan` 时被 OOM killer 杀掉，systemd 停在 `failed (Result: oom-kill)`，导致该 runner 离线。根因是 8G VM 无 swap，且当时同机并发 Docker build / BuildKit / Java / Sonar 等进程，内存峰值无缓冲。为降低后续瞬时内存峰值直接杀 runner 的概率，并避免 runner 被 OOM 后长期停在 failed，给 VM 加 swap 并给 runner service 加失败自动恢复策略。
- 影响：
  - 新增 `/swapfile`，大小 `8G`，权限 `600`，并写入 `/etc/fstab` 持久化开机启用。
  - 为 3 个 runner service 增加 systemd drop-in：`Restart=on-failure`、`RestartSec=180`。覆盖范围：
    - `actions.runner.cypressoai.mas-go-dev.service`
    - `actions.runner.cypressoai.mas-go-dev-ci-1.service`
    - `actions.runner.cypressoai.mas-go-dev-ci-2.service`
  - 执行 `systemctl daemon-reload`，并确保 `mas-go-dev-ci-1` 处于 active。
  - 未重启 VM、Docker、应用容器、数据库、Tailscale 或其它业务服务。
- 备份：
  - `/etc/fstab.bak.20260622-110536`
  - `/root/runner-oom-fix-redo-20260622-110536/runner-units-before.txt`
  - `/root/runner-oom-fix-redo-20260622-110536/runner-status-before.txt`
  - `/root/runner-oom-fix-redo-20260622-110536/free-before.txt`
  - `/root/runner-oom-fix-redo-20260622-110536/swapon-before.txt`
- 回滚方式：
  1. 停用并移除 swap：
     ```bash
     sudo swapoff /swapfile
     sudo cp /etc/fstab.bak.20260622-110536 /etc/fstab
     sudo rm -f /swapfile
     ```
  2. 移除 runner restart drop-in 并重载 systemd：
     ```bash
     sudo rm -f /etc/systemd/system/actions.runner.cypressoai.mas-go-dev.service.d/restart.conf
     sudo rm -f /etc/systemd/system/actions.runner.cypressoai.mas-go-dev-ci-1.service.d/restart.conf
     sudo rm -f /etc/systemd/system/actions.runner.cypressoai.mas-go-dev-ci-2.service.d/restart.conf
     sudo systemctl daemon-reload
     ```
- 验证：
  - `free -h` 显示 `Swap: 8.0Gi`，`swapon --show` 显示 `/swapfile file 8G`。
  - `/etc/fstab` 包含 `/swapfile none swap sw 0 0`。
  - 3 个 runner service 均为 `active (running)`，`systemctl show` 显示 `Restart=on-failure`、`RestartUSec=3min`；`systemctl cat` 显示 drop-in 中的 `Restart=on-failure`、`RestartSec=180`。
  - `mas-go-dev-ci-1` 当前 active。此前恢复后已重新连接 GitHub 并继续承接 `SonarQube Scan`，最近日志中可见多条 scan 完成记录。

## 2026-06-19 10:42 CST - 后端 DB_NAME 切到 medicalassistance_preprod（配合 mssql-ref 库改名）

- 服务器：`mas-go-dev`（`192.168.2.22`）
- 操作人：`Claude`
- 原因：`mssql-ref` 上库 `medicalassistance` 改名为 `medicalassistance_preprod`（详见 `docs/operations/mssql-ref.md` 2026-06-19）。后端 `.env.docker` 的 `DB_NAME=medicalassistance` 需同步改名，否则连不上库。
- 影响：
  - 修改 `/opt/mas-go-dev/backend/.env.docker`：`DB_NAME` 由 `medicalassistance` 改为 `medicalassistance_preprod`（仅这一行）。`WEBKIT_DB_NAME=maswebkit` 未动；host/账号/密码不变。
  - 强制重建 `icare-backend-api-1` + `icare-backend-worker-1`（含一次性 `seed` 依赖），使新 env 生效。未碰 gotenberg / runner。
  - 改名过程中库一度不可用，停容器期间 API 短暂不可用（开发测试环境，影响可接受）。
- 回滚：用备份 `/opt/mas-go-dev/backend/.env.docker.bak.20260619` 覆盖后同样重建容器。
- 变更：
  1. 以 `actions-runner` 身份 `cp` 备份后 `sed -i 's/^DB_NAME=medicalassistance$/DB_NAME=medicalassistance_preprod/'` 精确改单行。
  2. 先 `stop api worker` 释放对旧库的连接（配合 mssql-ref 改名），改名后重建：
     ```bash
     cd /opt/mas-go-dev/backend
     export BACKEND_IMAGE=icare/backend:mas-go-dev-8346d1a908fe958b6c892e52a31de6dd42649bea
     docker compose -f backend.compose.yaml up --no-build --force-recreate -d api worker
     ```
     注意：`start`（而非 `up --force-recreate`）不会重读改过的 `.env.docker`，必须 recreate；且需带镜像 tag，否则默认 `${BACKEND_IMAGE:-icare/backend:local}` 会去拉不存在的 `:local`（同 6-14 那条经验）。`seed` 在旧库名仍存在时会因连不上失败 exit 1、阻断 api/worker；改名后重跑即通过。
- 验证：
  - api/worker 启动日志 `database connected ... database=medicalassistance_preprod` + `maswebkit`，无 login failed。
  - `icare-backend-api-1` 转 `healthy`，worker 正常。

## 2026-06-14 21:25 CST - 后端 DB 账号切到 mas_ref_owner，修复因 mssql-ref 停用旧账号导致的 500

- 服务器：`mas-go-dev`（`192.168.2.22`）
- 操作人：`Claude`
- 原因：本次在 `mssql-ref` 上把 SQL 账号 `mas_ref_reader` 停用（DISABLE），换成 `mas_ref_owner`。检查发现后端 `icare-backend-api` / `worker` 的 `.env.docker` 用 `mas_ref_reader` 连库（`medicalassistance` 与 `maswebkit` 两套连接，host `192.168.2.20`），账号被禁用后 API 持续报 500：`Login failed for user 'mas_ref_reader'. The account is disabled.`。这就是账号迁移时待确认的「遗留使用方」。
- 影响：
  - 修改 `/opt/mas-go-dev/backend/.env.docker`：`DB_USER` 与 `WEBKIT_DB_USER` 由 `mas_ref_reader` 改为 `mas_ref_owner`（密码不变，两账号同密码，`DB_PASSWORD`/`WEBKIT_DB_PASSWORD` 未动；两个 `*_DSN` 为空，无需改）。
  - 重建 `icare-backend-api-1` + `icare-backend-worker-1` 两个容器使新 env 生效。未动 gotenberg / azurite / redis / seed，未碰 runner。
- 回滚：用备份 `/opt/mas-go-dev/backend/.env.docker.bak.20260614-claude-switch-owner` 覆盖后同样方式重建容器；或在 mssql-ref 上 `ALTER LOGIN [mas_ref_reader] ENABLE` 临时恢复旧账号。
- 变更：
  1. 确认连库配置在 `.env.docker`（compose 经 `env_file: ${DOCKER_ENV_FILE:-.env.docker}` 注入），密码为明文、文件 600、属主 `actions-runner`。
  2. 以 `actions-runner` 身份 `cp` 备份后 `sed` 精确替换两处 `DB_USER`。
  3. 重建容器（需带 runner 部署时的镜像 tag，否则 compose 默认 `${BACKEND_IMAGE:-icare/backend:local}` 会去拉不存在的 `:local`）：
     ```bash
     cd /opt/mas-go-dev/backend
     export BACKEND_IMAGE=icare/backend:mas-go-dev-598f00214c4b1b828d5849b5c93409c5aee83d7a
     docker compose -f backend.compose.yaml up -d --force-recreate --no-build --no-deps --pull never api worker
     ```
- 验证：
  - api/worker 启动日志均 `database connected`（medicalassistance + maswebkit），无 login failed。
  - 近 1 分钟 `login failed` 次数为 0（修复前持续刷）。
  - 之前 500 的 `/api/v1/admin/permissions` 现返回 401（缺 token 的正常响应，DB 连接已通）。
  - `icare-backend-api-1` 转 `healthy`，worker 正常。
- 后续（重要，未完成）：
  - **更正（已核查 iCare backend 仓库）**：先前担心「CI 会覆盖回旧账号」不成立。`deploy.yml` 不生成/覆盖 `.env.docker`，只通过 `DOCKER_ENV_FILE: /opt/mas-go-dev/backend/.env.docker` 引用 VM 上已存在的文件；仓库内只有占位模板（`.env.docker.example` 为 `replace-with-db-user`，`.env.konghai`/`.env.example` 是本地用的 `sa`/`icare`），GitHub secrets 里也没有这个 DB 账号。`mas_ref_reader`/`mas_ref_owner` 的真实值**只存在于 VM 上手工维护的 `.env.docker`**。所以本次修改即持久生效，**仓库侧无需改动**。
  - 唯一残留风险：VM 上几个 `.env.docker.bak.*` 里含旧账号，若有人手工用旧备份覆盖会退回 `mas_ref_reader`（人工风险，非自动化）。
  - 无其它使用方确认前，`mssql-ref` 上的 `mas_ref_reader` 暂保持禁用而非删除。
- 经验复盘（手动重建后端后前端短暂 502，根因不是 nginx 缓存）：
  - 现象：手动 `docker compose up -d --force-recreate api worker` 重建后端后，立刻访问前端 `http://192.168.2.22:5174/login` 出现 502，前端 nginx 日志 `connect() failed (111: Connection refused) ... upstream http://api:8080`。几十秒后自愈。
  - 一开始误判为「api 容器 IP 变了、前端 nginx DNS 缓存还指向旧 IP」。用户质疑：CI 部署同样会重建容器，但他从来无感、不需要等几十秒——若真是 DNS 缓存窗口，日常应偶尔撞到。
  - 实测验证（触发一次 CI 后端部署，与手动重建前的基线对比）：
    - api 容器 ID 与 IP **都变了**（`172.18.0.6` → `172.18.0.5`，且与 worker 互换），证明 CI 部署也是 rm + 重建、IP 一样会变 —— “CI 部署 IP 不变” 的猜想被证伪。
    - 但部署后前端容器内 `getent hosts api` **立即解析到新 IP**，无任何缓存滞后 —— nginx DNS 缓存假说也被证伪。
  - 真正根因：前端 nginx 用 DNS 名 `http://api:8080` 反代（非硬编码 IP，`resolver 127.0.0.11`），解析本身没问题。差别在**有没有等后端 ready**：
    - CI 部署脚本（`deploy.yml`）用 `stop` + `rm -f` + `up -d`，且**带 30 次 `curl healthz` 重试（最多 ~60s），等 api 真正 ready 才算部署完成**；用户都是在部署完成后访问，自然无感。
    - 手动 `--force-recreate` 命令一返回我就让用户访问，api 容器虽 `Started` 但 Go 程序还在初始化（连两个 SQL Server 库的那几秒）、尚未监听 8080 → nginx 连过去 `Connection refused` → 502；初始化完成即自愈。
  - 教训 / 操作建议：手动重建后端容器后，应仿照 CI 先等健康检查通过再交付/通知访问，例如 `for i in {1..30}; do curl -fsS http://127.0.0.1:8080/healthz && break; sleep 2; done`。这与容器 IP、nginx 缓存均无关。

## 2026-06-12 15:57 CST - 在 VM 内启用 Tailscale，恢复访问 mac-mini SonarQube

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：用户安装并登录 Tailscale；`Codex` 做只读验证并记录。
- 原因：`mas-go-dev` 此前依赖 PVE subnet router 与本地静态解析访问 `mac-mini` SonarQube。VM 重启 / 网络重载后，VM 主动访问 tailnet 的路由与 MagicDNS 能力不可用，`http://mac-mini:9000/` 无法解析或连接。用户决定在 VM 内直接安装并登录 Tailscale，减少对 PVE 反向路由和手工 DNS/hosts 方案的依赖。
- 影响：
  - VM 自身成为 tailnet 节点，Tailscale IPv4 为 `100.109.223.53`。
  - `tailscaled` 已启用开机自启并处于运行状态。
  - `mac-mini` MagicDNS 恢复可用，`mac-mini` / `mac-mini.taila93443.ts.net` 均解析到 `100.108.64.126`。
  - 未改 Docker、runner、应用部署目录、PVE subnet router 或防火墙规则。
- 回滚方式：
  - 临时停用：`sudo systemctl disable --now tailscaled`。
  - 如需从 tailnet 退出：`sudo tailscale logout`。
  - 如需完全卸载：按 Amazon Linux 2023 包管理方式移除 `tailscale`，再清理本机不再需要的 tailscale 状态文件。
- 做了什么：
  - 用户已在 `mas-go-dev` 内完成 Tailscale 安装和登录。
  - 只读验证 `command -v tailscale`、`systemctl is-active tailscaled`、`systemctl is-enabled tailscaled`、`tailscale ip -4`、`tailscale status`。
  - 验证 MagicDNS 解析与 SonarQube HTTP 访问。
- 验证结果：
  - `tailscaled`：`active` / `enabled`。
  - `tailscale ip -4`：`100.109.223.53`。
  - `getent hosts mac-mini`：`100.108.64.126 mac-mini.taila93443.ts.net`。
  - `curl -I http://mac-mini:9000/` 返回 `HTTP/1.1 200`。
  - `curl -I http://mac-mini.taila93443.ts.net:9000/` 返回 `HTTP/1.1 200`。
- 注意事项：
  - `tailscale status` 提示 `Some peers are advertising routes but --accept-routes is false`。当前场景只需要访问 tailnet peer（`mac-mini`）和 MagicDNS，不依赖接受其它节点 advertised routes，因此不影响本次修复。
  - 用户已在 Tailscale Admin Console 中给 tailnet 内所有设备设置 `Disable key expiry`，降低 `mas-go-dev`、`pve` 等长期节点因 key 过期导致访问中断的风险。
  - 后续仍需留意 tag / ACL 策略变更，避免 CI VM 对 `mac-mini:9000` 的访问被权限规则误伤。

## 2026-06-12 14:42 CST - 确认 AL2023 无法从官方仓库安装 qemu-guest-agent

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Codex`
- 原因：PVE 侧 VM 配置已有 `agent: enabled=1`，但 guest 内未安装 `qemu-guest-agent`，导致 `qm agent 130 ping` 返回 `QEMU guest agent is not running`。用户确认尝试安装。
- 影响：未安装任何包，未启用任何新服务，未重启 VM，未改 Docker、runner、应用部署目录或业务配置。仅在 `/home/ec2-user/qemu-guest-agent-install-20260612-064212/` 保留安装尝试日志。
- 回滚：无功能性变更需要回滚；如需清理安装尝试日志，可删除 `/home/ec2-user/qemu-guest-agent-install-20260612-064212/`。
- 变更：
  - 安装前状态保存到 `/home/ec2-user/qemu-guest-agent-install-20260612-064212/precheck.txt`。
  - 执行 `sudo dnf install -y qemu-guest-agent`，返回 `No match for argument: qemu-guest-agent` / `Unable to find a match`。
  - 执行 `dnf provides '*/qemu-ga' '*/qemu-guest-agent'`，当前启用的 `amazonlinux` 与 `kernel-livepatch` 仓库无匹配结果。
  - 查阅 AWS 官方 AL2023 KVM 文档，确认 AL2023 当前不打包也不支持 KVM guest agent；因此未从第三方来源安装。
- 验证：
  - `rpm -q qemu-guest-agent` 仍显示 package not installed。
  - PVE 侧 `qm agent 130 ping` 仍返回 `QEMU guest agent is not running`，符合 AL2023 官方限制与当前仓库状态。
  - Docker 与 `actions.runner.cypressoai.mas-go-dev.service` 均为 `active`。
  - `icare-backend-api-1` 仍为 `healthy`，`http://127.0.0.1:5174/healthz` 返回 `ok`。
- 后续：
  - 不建议为 AL2023 引入非官方 QEMU RPM 来追求 PVE guest agent 能力；如确实强依赖该能力，应另行评估迁移到 Ubuntu/Debian 等官方仓库提供 qemu guest agent 的 guest OS。

## 2026-06-11 15:50 CST - 新增 `mas-go-dev-ci-2` 分流 frontend SonarQube job

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Codex`
- 原因：`mac-mini` 上的 frontend PR CI 排队严重。前端 `sonar.yml` 已把 `SonarQube Scan` 单 job 改为共享标签 `frontend-sonar-ci`，`mas-go-dev-ci-1` 已验证能承接该 job；为进一步分流多个 PR 同时触发的 SonarQube job，在同一 VM 上新增第二个 CI runner。
- 影响：
  - 新增一个 GitHub Actions runner service：`actions.runner.cypressoai.mas-go-dev-ci-2.service`，enabled，随 VM 自启。
  - 新 runner 标签为 `self-hosted, Linux, X64, al2023, mas-go-dev-ci, frontend-sonar-ci`。
  - **刻意不加 `backend-ci` / `docker` 标签**：当前只让它承接 frontend SonarQube；不参与 backend Go test / Sonar，也不抢部署 runner `mas-go-dev` 的 job。
  - 可能同时在 `mas-go-dev-ci-1` / `mas-go-dev-ci-2` 上并发跑两个 frontend SonarQube job。该 PR Sonar 不跑 coverage，单 job 通常约 1-2 分钟；当前 VM 4 核、可用内存约 4.1GiB，风险可控。
- 回滚方式：`cd /opt/actions-runner/mas-go-dev-ci-2 && sudo ./svc.sh stop && sudo ./svc.sh uninstall`，然后 `sudo -u actions-runner ./config.sh remove --token <removal-token>`（token 用 `gh api -X POST orgs/cypressoai/actions/runners/remove-token` 获取），最后删除 `/opt/actions-runner/mas-go-dev-ci-2`。
- 做了什么：
  - 预检确认 `mas-go-dev-ci-1` 在线空闲，且不存在 `/opt/actions-runner/mas-go-dev-ci-2`、同名 systemd service 或 GitHub runner 记录。
  - 创建 `/opt/actions-runner/mas-go-dev-ci-2`（owner `actions-runner`），下载并解压 actions/runner `v2.335.1` linux-x64。
  - 以 `actions-runner` 用户执行 `config.sh`，注册到组织 `cypressoai`，runner group `mas-go-dev`，名称 `mas-go-dev-ci-2`，自定义标签 `mas-go-dev-ci,al2023,frontend-sonar-ci`。
  - `sudo ./svc.sh install actions-runner && sudo ./svc.sh start` 安装并启动 systemd 服务。
- 验证结果：
  - `systemctl is-active actions.runner.cypressoai.mas-go-dev-ci-2.service` 返回 `active`，`systemctl is-enabled` 返回 `enabled`。
  - journal 显示 `Connected to GitHub`、runner version `2.335.1`、`Listening for Jobs`。
  - GitHub API 显示 `mas-go-dev-ci-2` `status: online, busy: false`，标签正确；`mas-go-dev-ci-1` 与部署 runner `mas-go-dev` 均保持在线空闲。

## 2026-06-10 19:50 CST - 给 mas-go-dev-ci-1 补装 dirmngr，修复 develop 版 Sonar 签名校验失败

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：PR #581（develop）的 `SonarQube Scan` step 在 mas-go-dev-ci-1 上失败：`gpg: keyserver receive failed: No dirmngr` → `Failed to import SonarSource public key from all keyservers`。根因是 develop 版 sonar.yml 的 `SonarSource/sonarqube-scan-action` **pin 到 SQSCANGHA-135 修复 commit，会校验 Scanner CLI 的 GPG 签名**，需从 keyserver 拉 SonarSource 公钥；而本 VM 装的是 `gnupg2-minimal`，只有 `gpg` 没有 `dirmngr`（gpg 的网络/keyserver 组件），导致拉公钥失败。main 版用 `@v6` 不做此校验，所以之前在本机实测 main workflow（#574/#580）从未暴露此问题。
- 影响：替换一个系统包（minimal→完整 gnupg2），`gpg` 同版本 2.3.7、路径不变，新增 dirmngr/gpg-agent 等完整组件。不影响容器与部署 runner。
- 回滚方式：`sudo dnf install -y --allowerasing gnupg2-minimal`（换回 minimal 包）。
- 做了什么：
  - 预检确认本 VM 到 `keyserver.ubuntu.com:443` / `keys.openpgp.org:443` 出网可达（均 200），方案可行
  - `sudo dnf install -y --allowerasing gnupg2`：AL2023 上 `gnupg2-minimal` 与完整 `gnupg2` 互斥（都提供 `/usr/bin/gpg`），dnf 默认拒绝替换，需 `--allowerasing` 用完整包替掉 minimal 包；无独立 dirmngr 包，这是装 dirmngr 的唯一途径
  - 实测同款命令拉 SonarSource 公钥（`gpg --recv-keys 679F...EC1A`）返回 `imported: 1`、exit 0
- 验证结果：补装 dirmngr 后重跑 PR #581 失败 job（run `27271362622`），`SonarQube Scan` step 成功（落在 mas-go-dev-ci-1，即修复的那台）。
- 经验：mac-mini 之前也踩过同源的 Sonar GPG 坑（`docs/solutions/mac-mini/.../sonarqube-scanner-cli-cache-never-hits-4part-version-2026-06-09.md`，那次是 PATH 缺 gpg + 路径过深）。本次是新 runner 缺 dirmngr。**任何要承接 backend Sonar 扫描的 self-hosted runner，都需具备完整 gpg + dirmngr + 能出网拉 keyserver 公钥**。已另写 `docs/solutions/mas-go-dev/`。

## 2026-06-10 19:35 CST - 把 backend CI 共享池改动同步到 `develop` 分支（修正只合 main 的疏漏）

- 仓库：`iCare-backend`（runner / VM 无变更）
- 操作人：`Claude`
- 原因：前面 PR #574、#580 都只合并到 `main`，但 iCare-backend **日常开发在 `develop`**。GitHub Actions 以「触发 run 的分支上的 workflow 版本」为准，所以 develop 上 backend 的测试/Sonar job 仍是最原始的 `[mac-mini-sonar, macos, arm64]` 独占调度，#574/#580 的改动对 develop **完全没生效**。这是「改 CI 没认准活跃分支」的疏漏。
- 影响：仅 develop 分支 workflow 文件改动，走 PR。runner 标签是 org 级（与分支无关），#580 已加好 `backend-ci`，本次无需再动。
- 关键判断：**没有用 merge main 的方式同步**。`develop` 与 `main` 已分叉（main ahead 4 / behind 335），develop 含 main 没有的内容——`ready_for_review` 触发、Sonar action pin 到 SQSCANGHA-135 修复 commit、gotenberg sidecar 部署步骤。merge main 会搅乱这些。改为基于最新 develop **只 cherry-pick 两处 `runs-on` + GOCACHE 注释**，逐行 diff 核对 develop 独有内容均原样保留。
- 做了什么：提交 PR [iCare-backend#581](https://github.com/cypressoai/iCare-backend/pull/581)（base=`develop`）：`sonar.yml` `SonarQube Scan`、`deploy.yml` `Build and Test` 两个 job `runs-on` 改为 `[self-hosted, backend-ci]`。
- 回滚方式：revert PR #581。
- 教训：**给某仓库改 CI / workflow 前，先确认它的活跃开发分支是哪个**（用 `gh api repos/<repo>/compare/<base>...<head>` 看 ahead/behind 判断主线）。iCare 系列仓库默认分支可能是 `main`，但实际开发在 `develop`，PR base 要对准 develop，否则改动对团队日常 CI 不生效。
- 验证结果：PR #581 首跑 `SonarQube Scan` step **失败**（落在 mas-go-dev-ci-1，测试全过、挂在 Sonar 上报），根因是该 VM 缺 `dirmngr`——详见下方 19:50 记录。补装 dirmngr 后重跑（run `27271362622`）`SonarQube Scan` step 成功。

## 2026-06-10 19:10 CST - backend CI 由硬绑定 mas-go-dev-ci-1 改为 `backend-ci` 共享 runner 池

- 服务器：`mas-go-dev`（PVE VM `130`）+ `mac-mini`（org runner 标签变更）
- 操作人：`Claude`
- 原因：PR #574 把 backend 的 Go 测试 + Sonar 扫描**硬绑定**到 `mas-go-dev-ci-1`（x86 Linux），但用户真实预期是「**优先用 mac-mini（arm64 更快），mac-mini 资源紧张时才溢出到 mas-go-dev-ci-1**」。硬绑定与预期相反——mac-mini 空闲时 backend CI 也永远走更慢的 x86。GitHub Actions 原生不支持优先级/溢出调度（`runs-on` 标签是硬匹配不排序），用「共享 runner 池」做最简近似。
- 影响：org 层面给 5 个 runner 加自定义标签（动态生效、无需重启 runner）；backend 两个 job 的 `runs-on` 改标签（走 PR）。前端 job 与各部署 job 不受影响。
- 回滚方式：
  - 标签：`gh api -X DELETE orgs/cypressoai/actions/runners/<id>/labels/backend-ci`（5 个 runner id：mac-mini-sonar-1..4 = 22/23/24/25，mas-go-dev-ci-1 = 28）
  - workflow：revert PR [iCare-backend#580](https://github.com/cypressoai/iCare-backend/pull/580)
- 做了什么：
  - 通过 org API 给 `mac-mini-sonar-1..4` 与 `mas-go-dev-ci-1` 各加自定义标签 `backend-ci`（5 个 runner 组成共享池）
  - 提交 PR #580：`sonar.yml` 的 `SonarQube Scan`、`deploy.yml` 的 `Build and Test` 两个 job `runs-on` 由 `[self-hosted, mas-go-dev-ci]` 改为 `[self-hosted, backend-ci]`
  - 更正 GOCACHE 注释，覆盖两类机器的缓存隔离方式
- 关键设计点：
  - **没有复用 `mac-mini-sonar` 标签**，而是新建中性标签 `backend-ci`。因为 `mac-mini-sonar` 现在语义 =「mac-mini arm64 macOS slot」，前端 job 用它搭配 `macos`/`arm64`；给 x86 机器贴该标签会让前端 macOS-only job 有误调度到 Linux 的风险。
  - **GOCACHE 并发安全已确认**：mac-mini 4 个并发 slot 在各自 `.env` 注入 per-slot `GOCACHE`/`GOMODCACHE`（`mac-mini-sonar-N/cache/...`），并发跑 backend job 不撞 cache（CYP-322 race 已在 runner 物理层解决）；mas-go-dev-ci-1 单实例走默认路径，已落盘持久化（go-build 2.0G、go-mod 878M）。
  - `mas-go-dev-ci` 标签保留在 mas-go-dev-ci-1 上但已无 job 引用，无害残留。
- 行为说明（诚实记录）：共享池是「谁空闲谁接」，**不是严格「闲时永远优先 arm」**——所有 runner 空闲时 GitHub 挑哪台不保证顺序，偶尔单个 job 落到 x86 慢一点。严格优先级需写显式溢出判断（复杂度高），本方案是性价比最高的近似，完整覆盖核心诉求「mac-mini 忙时溢出」。
- 验证结果：PR #580 触发的 `SonarQube Scan`（run `27270834531`）以标签 `[self-hosted, backend-ci]` 调度成功，1 分 53 秒跑完（热缓存，对比 PR #574 冷缓存 5 分 12 秒）。本次落点恰好是 `mas-go-dev-ci-1`（x86），正好实证「不保证闲时优先 arm」这一行为——功能正确，仅说明严格优先级共享池给不了。后续 merge #580 后 backend 测试/Sonar 即在 5 runner 池中按空闲调度。

## 2026-06-10 18:25 CST - 为 `mas-go-dev-ci-1` 承接 backend Go 测试 + Sonar 扫描做 VM 准备并提交 workflow PR

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：用户决定让 `mas-go-dev-ci-1` 只承接 `iCare-backend` 的 Go 测试与 SonarQube 扫描（即 `sonar.yml` 的 `sonarqube` job 和 `deploy.yml` 的 `test` job，原来都调度到 `mac-mini-sonar` 标签）。预检发现 VM 缺 gcc（CGO 需要）、`actions-runner` 无 sudo（workflow 的 `sudo dnf install gcc` 兜底走不通）、且解析不了 `mac-mini`（`SONAR_HOST_URL` 指向 `http://mac-mini:9000`，原靠 tailnet MagicDNS，本 VM 未装 Tailscale）。
- 影响：VM 上新增系统包与一条 hosts 记录，均为加法操作，不影响既有容器与部署 runner。workflow 改动走 PR，不直接动 main。
- 回滚方式：
  - gcc：`sudo dnf remove gcc glibc-devel`（一般无需回滚，留着无害）
  - hosts：`sudo cp /etc/hosts.bak.20260610 /etc/hosts`
  - workflow：revert PR [iCare-backend#574](https://github.com/cypressoai/iCare-backend/pull/574)
- 做了什么：
  - `sudo dnf install -y gcc glibc-devel`（gcc 11.5.0），workflow 的 `Ensure C Build Toolchain` 步骤会因 gcc 已存在直接短路通过
  - 备份 `/etc/hosts` 为 `/etc/hosts.bak.20260610` 后追加 `192.168.2.170 mac-mini`（mac-mini 与 PVE 同在 192.168.2.0/24 局域网，无需走 Tailscale）
  - 提交 PR iCare-backend#574：两个 job 的 `runs-on` 从 `[mac-mini-sonar, macos, arm64]` 改为 `[self-hosted, mas-go-dev-ci]`，并更新 GOCACHE 注释（单实例 runner 用默认缓存路径，无需 mac-mini 的 per-slot 隔离）
- 验证结果：`getent hosts mac-mini` 返回 `192.168.2.170`；从 VM `curl http://mac-mini:9000/api/system/status` 返回 `"status":"UP"`；PR 触发的 `SonarQube Analysis` run 已调度执行（PR 事件用分支上的新版 workflow，正好实测新 runner）。
- 注意事项：mac-mini 的 `192.168.2.170` 由用户手动静态配置、永不变化（2026-06-10 用户确认），`/etc/hosts` 映射无需担心 DHCP 漂移。

## 2026-06-10 18:06 CST - 新增第二个 GitHub Actions runner `mas-go-dev-ci-1`

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：mac-mini 上 4 个 `mac-mini-sonar-*` runner 承接 MAS CI 任务时 CPU 拥挤、队列积压（见 `docs/operations/mac-mini.md` 2026-06-10 17:05 审计）。评估 PVE 资源后决定在 `mas-go-dev` VM 内新增一个 Linux runner 为 MAS 项目分流 CI 任务。PVE 宿主 CPU 长期空闲（三台 VM 周均 CPU 1.2% / 0.6% / 2.6%）但宿主内存仅余 ~3.7GiB，故不另开 VM/LXC，复用本 VM（内存周均占用 45%，操作时 available 4.5GiB）。
- 影响：纯新增操作，未改动既有 `mas-go-dev` runner、部署目录、容器。新 runner 标签为 `self-hosted, Linux, X64, docker, al2023, mas-go-dev-ci`，**刻意不带 `mas-go-dev` 标签**，避免抢走部署 job 造成并发部署冲突；现有 workflow 不会调度到它，需要分流的 job 显式改 `runs-on: [self-hosted, mas-go-dev-ci]` 才会使用。
- 回滚方式：`cd /opt/actions-runner/mas-go-dev-ci-1 && sudo ./svc.sh stop && sudo ./svc.sh uninstall`，然后 `sudo -u actions-runner ./config.sh remove --token <removal-token>`（token 用 `gh api -X POST orgs/cypressoai/actions/runners/remove-token` 获取），最后删除目录。
- 做了什么：
  - 创建 `/opt/actions-runner/mas-go-dev-ci-1`（owner `actions-runner`），下载并解压 actions/runner `v2.335.1` linux-x64
  - 以 `actions-runner` 用户执行 `config.sh`，注册到组织 `cypressoai`，runner group `mas-go-dev`（visibility: selected，限 MAS 仓库），名称 `mas-go-dev-ci-1`，自定义标签 `mas-go-dev-ci,docker,al2023`
  - `sudo ./svc.sh install actions-runner && sudo ./svc.sh start` 安装并启动 systemd 服务 `actions.runner.cypressoai.mas-go-dev-ci-1.service`（enabled，随 VM 自启）
- 验证结果：systemd 服务 `active (running)`；GitHub API 显示 `mas-go-dev-ci-1` `status: online, busy: false`，标签正确，已在 runner group `mas-go-dev` 中（与既有 `mas-go-dev` runner 并列）。
- 附带发现：PVE 节点级 RRD 历史文件损坏（`rrd_fetch_r failed: mmaping file '/var/lib/rrdcached/db/pve-node-9.0/pve'`，PVE 9 已知问题），本次未处理；各 VM 级 RRD 正常。

## 2026-05-29 CST - 确认 azurite 运行状态 + 沉淀 iCare 项目使用方式

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：用户询问 azurite 是否启动、在 iCare 项目里应该怎么用。做一次只读核查，并把"怎么用"的接法沉淀下来（上线记录 `2026-05-28 12:47` 只写了部署过程，没写消费方如何接入）。
- 影响：纯只读查询（`docker ps` / `docker inspect` / 读 `.env.docker`），未改动任何容器、配置、网络。
- 当前状态（只读核查结果）：
  - `azurite`：`Up`，只启用 **blob** 服务，启动命令 `azurite-blob --blobHost 0.0.0.0 --blobPort 10000 --skipApiVersionCheck`；queue(10001)/table(10002) 未对外暴露。
  - `redis`：`Up`。
  - 两者端口均只 bind `127.0.0.1`（azurite `10000`、redis `6379`），**VM 外部无法直连**。
  - `azurite` 接在 `shared-services` 网络，DNS 名 / 别名为 `azurite`，容器内 IP `172.18.0.4`，`restart: always`（VM 重启自动拉起）。
  - 同网络消费方容器在跑：`icare-backend-api-1`(healthy)、`icare-backend-worker-1`、`mas-icare-portal`。
- iCare 项目使用方式（沉淀，供后续部署/排查参考）：
  - 服务器上 `icare-backend-api-1` / `icare-backend-worker-1` 已接好，连接配置在 `/opt/mas-go-dev/backend/.env.docker`：
    ```
    AZURE_STORAGE_CONNECTION_STRING=DefaultEndpointsProtocol=http;AccountName=devstoreaccount1;AccountKey=<azurite默认key>;BlobEndpoint=http://azurite:10000/devstoreaccount1;
    ```
  - `AccountName=devstoreaccount1` + 默认 AccountKey 是 Azurite 内置固定账户（官方公开默认值），非真实凭据。
  - **`BlobEndpoint` 的 host 必须写 `azurite`**（`shared-services` 网络 DNS 名），不能写 `localhost`/`127.0.0.1`——对运行在别的容器里的 api/worker 来说 `localhost` 指向它自己。
  - 消费方容器**必须也加入 `shared-services` 网络**才能解析到 `azurite`（`networks: [shared-services]` + `external: true`），这正是 backend compose 的接法。
  - 在 mas-go-dev VM 上跑新服务：直接复用上述连接串 + 加入 `shared-services` 网络即可。
  - 本机本地开发：**连不到 VM 上的 azurite**（端口只绑 127.0.0.1），标准做法是本地另起一个 azurite 容器（`docker run -p 10000:10000 mcr.microsoft.com/azure-storage/azurite azurite-blob --blobHost 0.0.0.0`），连接串里 `BlobEndpoint` 改为 `http://127.0.0.1:10000/devstoreaccount1`，AccountName/Key 沿用同一套默认值，代码无需改动。
- 回滚：无（只读操作，无变更）。

## 2026-05-28 14:55 CST - 部署 build cache 自动清理 timer + 全清历史 cache

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：本仓库 backend Dockerfile + workflow 修复（合并到 develop 后已跑过多个 PR）已验证 build cache 不再无限累积，但磁盘里仍残留 66.91GB 历史 cache 层（其中大量是被新 build 复用的老 591MB Go 编译层）。决定全清一次彻底回收空间，并安装 systemd timer 兜底，防止未来再出现孤儿层堆积。
- 影响：
  - 安装 `docker-builder-prune.service` + `.timer`（root），每天 UTC 20:00（CST 凌晨 4 点）自动清理 168 小时（7 天）未使用的 buildkit cache 层。RandomizedDelaySec=300 避免与其他 timer 同时启动。
  - `sudo docker builder prune -a -f` 全清 buildkit cache，下次 PR build 需要全量重新下载 Go modules + 编译，预计耗时从 3-5 分钟拉长到 8-15 分钟（一次性），多消耗 500MB-1GB 网络流量。
  - 未触碰镜像、容器、卷；正在运行的 `icare-backend-api-1`(healthy)、`icare-backend-worker-1`、`azurite`、`redis`、`mas-icare-portal` 全部未受影响。
- 回滚：
  - timer：`sudo systemctl disable --now docker-builder-prune.timer && sudo rm /etc/systemd/system/docker-builder-prune.{service,timer} && sudo systemctl daemon-reload && sudo rm /var/log/docker-prune.log`
  - cache：不可逆，但下次 build 会按需重建。
- 变更：
  - 新建 `/etc/systemd/system/docker-builder-prune.service`：`Type=oneshot`，执行 `/usr/bin/docker builder prune --filter until=168h --force`，stdout/stderr 追加到 `/var/log/docker-prune.log`。
  - 新建 `/etc/systemd/system/docker-builder-prune.timer`：`OnCalendar=*-*-* 20:00:00 UTC`，`Persistent=true`（断电期间错过的会补跑），`RandomizedDelaySec=300`。
  - `sudo touch /var/log/docker-prune.log && sudo chmod 644`。
  - `sudo systemctl daemon-reload && sudo systemctl enable --now docker-builder-prune.timer`。
  - `sudo docker builder prune -a -f`，回收 66.92GB。
- 验证：
  - `systemctl list-timers docker-builder-prune.timer` 显示 `NEXT=2026-05-28 20:03:48 UTC`（含随机延迟）。
  - 清理前：`Build Cache 993 条 / 66.91GB`，根分区 `74G/120G (62%)`。
  - 清理后：`Build Cache 0 条 / 0B`，根分区 `5.5G/120G (5%)`，可用 `115GB`。
  - `docker ps`：5 个容器全部 `Up`，`icare-backend-api-1` 保持 `healthy`。
- 后续：
  - 观察下次 PR 部署：build 时长（预期 8-15 分钟）、build 完成后 `docker system df` 的 Build Cache 应该回到 1-2GB 级别。
  - 每天 UTC 20:00 后查看 `/var/log/docker-prune.log` 几次，确认 timer 按预期执行。
  - 长期理想态：Build Cache 稳定在 1-2GB（一份完整复用 cache），timer 偶尔清掉过期残留。如果一周后看到 Build Cache 又涨到几十 GB，说明 cache 复用机制再次失效，需要重新排查。

## 2026-05-28 12:47 CST - 上线 iCare 集成测试基础设施容器（azurite + redis）

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：iCare backend 接入 Redis + Asynq 队列（CYP-699）后需要 worker 容器，worker 依赖 Redis 和 Azure Blob（开发态用 Azurite 模拟）。此前这两个依赖只在本地 `compose.dev.yaml` 中提供；mas-go-dev 集成测试环境缺失，导致 worker 无法部署。
- 影响：
  - 在 mas-go-dev 上新增独立 compose project `icare-backend-infra`，运行两个常驻容器 `azurite` + `redis`，接入既有 `shared-services` 网络（172.18.0.0/16）。
  - 同一网络上原有的 `icare-backend-api-1`、`mas-icare-portal` 容器**未重启、未受影响**；只是网络成员从 2 个增加到 4 个。
  - 服务器 `.env.docker` 追加 13 个 worker / queue / azurite 相关环境变量；现有 KEY 不变。
  - 容器端口仅绑 `127.0.0.1`（azurite 10000、redis 6379），不对外暴露。
- 回滚：
  - 容器：`sudo -u actions-runner docker compose -f /opt/mas-go-dev/infra/infra.compose.yaml down -v`（同时清掉持久化卷；如果只是停容器去掉 `-v`）。
  - `.env.docker`：用备份 `/opt/mas-go-dev/backend/.env.docker.bak.20260528-claude-infra-rollout`（818 字节）覆盖回去即可，保持 600 权限。
- 变更：
  - 新建目录 `/opt/mas-go-dev/infra/`，owner `actions-runner:actions-runner`，mode `750`（与 `backend/`、`frontend-mas/` 对齐）。
  - `scp` 仓库内 `iCare/backend/infra.compose.yaml` → `/opt/mas-go-dev/infra/infra.compose.yaml`（mode `644`）。SHA256 比对一致：`38b2e450bc13669f6276983080b15fc15314637ba71f0608b20b27e79347454d`。
  - `sudo -u actions-runner docker compose -f infra.compose.yaml up -d` 启动：
    - `azurite` (image `mcr.microsoft.com/azure-storage/azurite:latest`)，绑 `127.0.0.1:10000`，挂载卷 `icare-backend-infra_azurite-data`，`restart: always`。
    - `redis` (image `redis:7-alpine`)，绑 `127.0.0.1:6379`，挂载卷 `icare-backend-infra_redis-data`，`restart: always`。
  - `/opt/mas-go-dev/backend/.env.docker` 追加 `QUEUE_PROVIDER=redis_asynq` 等 13 个 KEY（先备份为 `.env.docker.bak.20260528-claude-infra-rollout`，文件从 816B → 1558B），保持 `600` 权限。
- 验证：
  - `docker ps` 显示两个容器 `Up`、`restart=always`。
  - `docker network inspect shared-services` 包含 4 个成员：`mas-icare-portal=172.18.0.2`、`icare-backend-api-1=172.18.0.3`、`azurite=172.18.0.4`、`redis=172.18.0.5`。
  - 从 `icare-backend-api-1` 容器内：
    - `getent hosts redis azurite` → 各自解析到 IP，DNS 名一致。
    - TCP：`</dev/tcp/redis/6379` 成功；`curl http://azurite:10000/` 返回 400（裸 GET 被拒，等价"端点活跃"），`curl 'http://azurite:10000/devstoreaccount1?comp=list'` 返回 403（未鉴权请求被正确拒绝，等价"服务真在跑"）。
  - `docker exec redis redis-cli ping` → `PONG`。
  - `docker compose -f /opt/mas-go-dev/backend/backend.compose.yaml config` 解析成功，三个 service `api / seed / worker` 的 environment 中均含新增的 `AZURE_STORAGE_CONNECTION_STRING` 等。
- 后续：
  - **未触发 PR 流水线**。仓库内待提交：`backend/infra.compose.yaml`（新增）、`backend/.env.docker.example`（分组标注三类环境）、`backend/.github/workflows/deploy.yml`（`Deploy local backend container` step 改为 `stop/rm/up api worker` + `--no-deps` + worker RestartCount 存活校验）。
  - PR 合并后由 runner 自动滚 api + worker 新版本，期间 azurite / redis 不会被动到（不同 compose project，部署链路只动 `icare-backend` 的 service）。
  - `infra.compose.yaml` **不进** runner 自动化；仓库内文件变更后，需手动 scp + `docker compose up -d` 同步到 `/opt/mas-go-dev/infra/`。该约定写入 `AGENTS.md`。

## 2026-05-28 12:41 CST - 清理 docker build cache 救磁盘并修复缓存累积根因

- 服务器：`mas-go-dev`（PVE VM `130`，`192.168.2.22`）
- 操作人：`Claude`
- 原因：另一个 session 排查时发现根分区 `/dev/sda1` 占用 98%（`117G/120G`，可用仅 `3.5G`），`/var/lib/docker` 占 113GB，其中 109.4GB 全是 buildkit 构建缓存。镜像本体只有 309MB，问题完全在 build cache。继续累积下去 runner 会因为磁盘满而 build/deploy 失败。
- 影响：
  - 执行 `docker builder prune --filter until=48h`，删除 947 条 48 小时以上未使用的 buildkit cache 层，释放约 35GB。
  - 未触碰镜像、容器、卷；未重启 docker、runner、容器；未改防火墙、SSH、数据库。
  - 同时在 `iCare/backend` 仓库改了 `Dockerfile` 和 `.github/workflows/deploy.yml`（未提交，由用户走 PR 流程），从根因上让后续 build 不再每次累积 ~591MB 新缓存层。
- 回滚：
  - 已清理的 buildkit cache 不可逆，但都是 48 小时以上未访问的孤儿层，下次 build 会按需重新拉取/编译（首次可能慢一些 + 多消耗一点出网流量，但不会破坏数据）。
  - backend 仓库改动可通过 revert PR 回退到 `docker build` 裸跑方式。
- 变更：
  - mas-go-dev 上：`sudo docker builder prune --filter "until=48h" -f`
    - 清理前：`Build Cache 2105 条 / 109.4GB`，根分区 `117G/120G (98%)`
    - 清理后：`Build Cache 1158 条 / 75.39GB`，根分区 `82G/120G (69%)`
  - `iCare/backend/Dockerfile`：4 个 `go build` 合并到一个 `RUN`，加 `--mount=type=cache,target=/root/.cache/go-build,sharing=locked` 和 `--mount=type=cache,target=/go/pkg/mod,sharing=locked`。BuildKit cache mount 的内容不进 image 层，同一 target 路径只保留一份，不会随每次 build 累积。
  - `iCare/backend/.github/workflows/deploy.yml` 中 `deploy-mas-go-dev` job：把裸 `docker build` 换成 `docker/setup-buildx-action@v3` + `docker/build-push-action@v5`，配合 `/tmp/.buildx-cache-mas-go-dev` 本地 cache + 旋转策略，与 `build-and-push` job (`dev-cypresso-ci` runner) 同一套模式。
- 验证：
  - `df -h /` 显示 `82G/120G (69%)`，可用 39GB。
  - `docker system df` 显示镜像、容器、卷均未受影响：`Images 3/2 309.3MB`、`Containers 3/2`、`Volumes 0`。
  - 正在运行的 `icare-backend-api-1` 仍为 `healthy`，`mas-icare-portal` 仍 `Up`。
- 后续：
  - backend PR 合到 `develop` 触发一次 mas-go-dev 部署后，观察 `sudo docker system df` 的 Build Cache 总量。预期稳定在 1-2GB 级别（一份完整 buildkit cache），而不是每个 PR 多 591MB。
  - 跑 2-3 个 PR 验证 cache 真正稳定后，再考虑在 mas-go-dev 加 cron 作为兜底（`0 4 * * * docker builder prune --filter "until=168h" -f`，每天清 7 天未用的）。现在不加 cron，因为如果根因没修好，cron 只会把"撑爆磁盘"变成"周期性丢缓存 + 重新拉网络流量"，和原本"少用网络"的目标冲突。
  - 当前剩余 75GB build cache 都是 48h 内的层；修复合并后会被新的复用结构逐步替换，不需要额外动作。
