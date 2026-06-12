# mas-go-dev 运维操作时间线

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
