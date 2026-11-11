# Agent 工作约定

这是一个运维笔记仓库，不是应用代码仓。绝大多数任务是：
- 通过 SSH 登录服务器排查问题
- 把解决方案沉淀进 `docs/solutions/`
- 维护命名约定与目录结构

## 语言

始终使用中文沟通。

## Git 分支约定

本仓库是个人运维笔记仓库，后续所有操作都只在 `main` 分支上进行。

- 不创建 feature/dev/topic 分支
- 不切换到非 `main` 分支工作
- 开始改文件前先确认当前分支是 `main`
- 如果当前不在 `main`，先切回 `main`，不要在其它分支继续提交
- 每次执行任务后，如果工作区有变更，必须用中文写清楚变更目的并提交 `git commit`，提交完成才算任务完成
- 提交信息应保持规范：优先沿用仓库已有风格；没有明确风格时使用 Conventional Commits，例如 `docs: 记录 dev-cypresso 容器停用时间线`

## 本机工具
- **Moo Ticket：** 凡提到 `https://t.moospark.com/` 的链接（如 `https://t.moospark.com/tickets/ICARE-15`），一律用 `moo-ticket-cli` skill（`moo` 命令）查询/评论/流转该工单，不要用 WebFetch 或浏览器抓页面。
- **SonarQube：** 服务器地址是 `http://mac-mini:9000`，API token 已注入环境变量 `SONAR_TOKEN`，可直接查询：

  ```bash
  curl -s -u "$SONAR_TOKEN:" "http://mac-mini:9000/api/issues/search?componentKeys=<projectKey>&pullRequest=<PR号>&resolved=false"
  curl -s -u "$SONAR_TOKEN:" "http://mac-mini:9000/api/qualitygates/project_status?projectKey=<projectKey>&pullRequest=<PR号>"
  ```

## 生产服务器操作守则

**`nyh-prod-2026` 是生产服务器**（2026-11-10 起接替已退役的 `nyh-prod`）。其它任何被纳入本仓库的服务器，默认都按生产对待，除非 README 明确标注是测试环境。

操作前：
1. 说清楚要做什么、预期影响、能否回滚
2. 改动配置/服务前先备份当前状态（`cp file file.bak.YYYYMMDD` 或读出当前值留在对话里）
3. 危险动作（重启、删除、改防火墙、改数据库）必须先征得用户确认，不要"顺手"做掉

不允许在没有用户确认的情况下：
- 重启进程、服务、面板
- 删除文件、目录、备份
- 修改 crontab、防火墙规则、SSH 配置
- 改动数据库 schema 或数据

可以自由做的事：
- 只读查询（`ls`、`cat`、`ps`、`openssl x509 -noout`、`systemctl status` 等）
- 在用户工作目录下创建/修改文档文件

## 故障文档约定（`docs/solutions/`）

详见 `docs/solutions/README.md`。要点：

- 路径：`docs/solutions/<server>/<category>/<slug>-<YYYY-MM-DD>.md`
- 文件名 slug 用小写、英文、连字符；末尾带日期方便排序
- frontmatter 字段遵循 ce-compound 的 schema，外加一个本仓库扩展字段 `server:`
- 类别枚举沿用 ce-compound 标准：`integration-issues`、`runtime-errors`、`performance-issues`、`security-issues`、`database-issues`、`workflow-issues`、`best-practices` 等

写文档时**优先用 `/ce:compound`**（lightweight 模式即可），它会自动按 schema 校验字段。

## 运维时间线约定（`docs/operations/`）

日常服务器操作记录写入 `docs/operations/<server>.md`，按时间倒序持续追加。

适合记录：
- 停止/启动容器、改 restart policy、迁移服务
- 调整配置、磁盘、备份、计划任务
- 一次性维护动作及其验证结果

每条记录至少写清：
- 时间（`YYYY-MM-DD HH:mm CST`）
- 原因
- 影响
- 回滚方式
- 做了什么
- 验证结果

如果一次操作暴露出可复用经验或故障复盘，再另写 `docs/solutions/`。

### 自动追加时间线并自动提交（无需询问）

对已经完成的服务器运维动作（含只读排查、装工具、改配置、启停容器等），**默认自动**把记录追加进 `docs/operations/<server>.md` 并 `git commit`，**不要**反过来问用户"要不要记录 / 要不要提交"：

- 新条目置于文件顶部（时间倒序），字段沿用本文件既有条目风格（时间 / 操作人 / 原因 / 选型或影响 / 备份 / 回滚方式 / 变更时序 / 验证）。
- 记录写完直接 `git commit`（在 `main` 分支，遵循上文「Git 分支约定」的提交信息规范）。
- 边界：本条只免除"记录与提交"这一步的询问，**不改变**上文「生产服务器操作守则」——服务器上的危险动作（重启、删除、改防火墙 / crontab / SSH、改库 schema/data）**仍须先征得用户确认**再执行，确认后再按本条自动记录+提交。

## 服务器连接

所有服务器走 `~/.ssh/config` 别名：

| 别名           | 用途                                                                                   | 是否按生产对待                    |
| -------------- | -------------------------------------------------------------------------------------- | --------------------------------- |
| `nyh-prod`     | **已退役**：ECS `i-j6chyzdlvn2vkqw0jbgv`（`47.239.167.8`）2026-11-11 00:00 到期不续费，业务 2026-11-10 已迁到 `nyh-prod-2026`；快照见 `docs/operations/nyh-prod.md` | 不再使用 |
| `nyh-prod-2026` | 南亚汇（NYH）、AcquiLang / Kanova、DDRicher、yunshu（bnsg）、guagua、new-api（`tovo.sh`）生产（阿里云香港轻量服务器 `8.217.145.133` / Tailscale `100.113.16.89`，Debian 13，4C/16G/80G，aliyun `--profile default`）；**不装宝塔**，PHP / Redis 用 Docker；`ssh nyh-prod-2026` 以 root 登录，档案 `nyh-prod-2026/README.md` | **是**                            |
| `qingfan-prod` | qingfan 项目生产（阿里云香港 ECS `8.210.153.241`，Debian 13，4C/7G）：`qingfan.app`（蓝绿 `qingfan@blue/green`）+ `flywheel.qingfan.app`（tk-flywheel），库在阿里云 RDS PG；`ssh qingfan-prod` 以 root 登录，档案 `qingfan-prod/README.md` | **是**                            |
| `do-1`         | sub2api 生产网关（DigitalOcean SFO3 旧金山 `137.184.127.196` / Tailscale `100.86.92.103`，Ubuntu 24.04，4C/8G），作为 `nyh-prod-2026` `new-api` 上游（主 `https://sub.tovo.sh` 白名单仅放行 `8.217.145.133` + Tailscale，备 `:8080` Tailscale）；大陆本机优先 `ssh -i ~/.ssh/id_ed25519 root@100.86.92.103` 登录，档案 `do-1/README.md` | **是**                            |
| `tizi-kh`      | 主代理服务器（`74.211.103.83`，2026-10-31 由 `tizi` 改名并整装为 Debian 13 + 3x-ui；Tailscale `100.90.28.83`）；ssh 别名兼容旧名 `tizi` | **是**（挂了影响日常翻墙）        |
| `tizi-rao`     | `tizi-kh` 的备用代理，兼 LLM API 反代 `litellm-us.konghai.me:8443`（`64.64.253.141`，2026-10-31 由 `rao-tizi` 改名并整装为 Debian 13 + 3x-ui；Tailscale `100.75.71.21`）；ssh 别名兼容旧名 `rao-tizi` | 是                                |
| `tizi-cyp`     | 新代理服务器（`89.208.242.203`，AlmaLinux 9.7）                                        | **是**（代理节点，按生产对待）    |
| `tizi-ddy`     | 代理节点（`80.251.215.131`，Debian 13，3x-ui）                                         | **是**（代理节点，按生产对待）    |
| `mac-mini`     | 家里的 Mac mini。**2026-10-22/23 起团队资产全部归 `hon`**（runner、colima `team` 里的 SonarQube / 共享开发库等、备份与维护任务、签名凭据），`konghai` 只做私人用途；`ssh mac-mini-hon` 以 `hon` 登录（2026-10-31 起 mac-mini 上不再常驻 colima VM：`team` / `moo` 已停，`multica` 已删，服务和需要 Docker 的 CI 都在 `team-svc`）。`konghai` 免密 sudo（用户要求长期保留，供性能排查）：`/etc/sudoers.d/konghai-diag`（`fs_usage`/`lsof`/`log`/`killall fseventsd`）、`konghai-fsetest`（仅测试卷 `FSETest`）；迁移临时规则 `konghai-hon-migrate`（`/usr/local/sbin/hon-migrate.sh`、`hon-team-services.sh`）与已过期的 `konghai-ciwork` 在 U6 收回 | 否                                |
| `lemon-imac`   | Tailscale 网内 iMac（8 核 / 8GB），朋友自用机（控制台账户 `zhangli`，FileVault 开启且不能关）；跑 org `cypressoai` self-hosted runner `lemon-imac-1/2` 和仓库 `IAmKongHai/Kanova` 级 runner `lemon-imac-kanova-ci-1`；`ssh lemon-imac` 以 `for-konghai` 登录 | 否（CI runner 机，改 runner / LaunchAgent 前仍需确认） |
| `umacbook-pro` | Tailscale 网内 MacBook Pro（`100.113.23.49`，主机名 `UdeMacBook-Pro.local`，M1 / 8GB），跑 org `cypressoai` self-hosted runner `umacbook-pro-1/2`；`ssh umacbook-pro` 以 `for-konghai` 登录 | 否（CI runner 机，改 runner / LaunchAgent 前仍需确认） |
| `nas`          | 家用 NAS，跑 `mas-old-sql2022-fts-nas`（SQL Server）、`mas-old-windows` 等 Docker 容器 | **是**                            |
| `pve`          | Proxmox VE 虚拟化宿主，计划承载开发测试 VM；当前可通过 `ssh pve` 以 root 密钥登录    | 否（测试环境，但仍需备份后再改）  |
| `mssql-ref`    | PVE 上的 Ubuntu VM，运行 MAS 老系统 MSSQL 参考数据库；当前可通过 `ssh ubuntu@192.168.2.20` 登录 | 否（参考/测试数据库，改库前仍需备份确认） |
| `mas-sit`      | PVE 上的 Debian 13 VM 160（`192.168.2.22` / Tailscale `100.109.223.53`，MagicDNS `mas-sit`；2026-10-31 由 AL2023 的 VM 130 迁来），iCare MAS Go 内网 SIT + 其它项目合部署的 SIT VM，跑后端容器、共享 PostgreSQL/Garage/Redis 与 6 个 self-hosted GitHub Actions runner（`mas-sit`、`mas-sit-ci-1/2`、`shared-sit` 及两个仓库级 runner）；`ssh mas-sit` 以 `ec2-user` 登录 | 否（开发测试环境，但改 Docker / runner 前仍需备份确认） |
| `fnos-nas`     | PVE 上的飞牛 fnOS VM（VMID 140，`192.168.2.9`），存放可重新下载的影视资源                | 否（不承诺数据可恢复；曾出现 SSH 超时不可达）  |
| `team-svc`     | PVE 上的 Ubuntu 24.04 VM（VMID 150，`192.168.2.23` / Tailscale `100.80.124.63`，6C/12G/200G），2026-10-31 起承接原 mac-mini colima `team` / `moo` 的全部服务（SonarQube、各项目开发库、shared-dev、sub2api、richer、moo-dev-infra + CDC、moo-ocr Kafka）、moo-app（moo-decision SIT 演示环境）和 runner `team-svc`（moo-decision / cmm-api / qingfan 的仓库级 runner，跑需要 Docker 的 job）；`ssh ubuntu@192.168.2.23`，档案 `team-svc/README.md` | 否（开发 / 团队服务，但 SonarQube、CDC 和 CI 团队在用，停机或改 Docker / runner 前仍需确认） |
| `km-landui`    | 内网设备，纳入例行安全扫描清单                                                          | 否                                |
| `home-router`  | 家里路由器，Web 管理端口经 `mac-mini` SSH 跳板访问（本机已卸载 Tailscale）              | **是**（改动影响家里所有联网设备） |
| `office-router`| 办公室路由器，原托管的 GitHub Actions runner 已于 2026-06-30 移除                        | **是**（改动影响办公室所有联网设备） |
| `cursor-box`   | Cursor Cloud Agent 沙箱（容器 hostname `cursor`，Tailscale 名 `3x-ui`，`100.102.171.1`）；`ssh box@100.102.171.1`。无独立公网 IP，入站只走 Tailscale。**不是** `tizi-ddy` 的 3x-ui 面板 | 否（云端临时沙箱，会话结束可能销毁） |
| `icare-uat-runner-1` | Azure UAT 原构建 VM（`Standard_B2s`，主机名 `icare-2-uat-ci-runner`，`10.30.6.4`），runner `icare-2-uat-runner` + wait slot `icare-2-uat-wait`；`ssh icare-uat-runner-1`（兼容 `icare-uat-runner`）以 `icareadmin` 登录 | **是**（挡住 Azure UAT 发版；改 runner / Docker / `/var/cache/buildx` 前仍需确认） |
| `icare-uat-runner-2` | CYP-2263 临时 D8s_v5 burst VM（主机名 `icare-2-uat-ci-runner-2`，`10.30.6.5`），runner `icare-2-uat-runner-2`，组 `icare-2-uat`；`ssh icare-uat-runner-2` 以 `icareadmin` 登录 | **是**（与原机同组抢 UAT 镜像构建；新机必须预建 `/var/cache/buildx` 属主 `icareadmin`；无 wait slot / 无 `gh`） |

注意：
- `nyh-prod-2026` 上同时跑着多个项目的生产站点、队列与定时任务（业务库在阿里云 RDS PG），任何重启 / 配置改动都要先想清楚波及哪些项目；配置源码在 `nyh-prod-2026/`，改仓库再推到服务器
- （旧机 `nyh-prod`，已退役）宝塔面板的 entrance 路径（URL 里 `/100c682f` 这一段）相当于第二道密码，不要写进 commit 信息或公开文档
- `nas` 上的 SQL Server 容器承载历史业务数据库（`medicalassistance` 等），关键容器统一用 `--restart=always` 而非 `unless-stopped`，避免 NAS 重启后不自动拉起
- `pve` 当前定位为开发测试虚拟化宿主；PVE 网络、存储、VM 等基础设施改动仍按“先备份、再改动、可回滚”执行
- `mssql-ref` 不是生产数据库，但承载 MAS 老系统完整参考数据；重启 SQL Server、改 schema/data、恢复备份前仍需先备份并确认
- `mas-sit` 是 MAS Go 内网 SIT，并作为其它项目的合部署 SIT VM（共享 PostgreSQL / Garage 在 `/opt/shared-sit/`）；过往文档常以 `192.168.2.22` 指代，现以 Tailscale `100.109.223.53` 为对外入口。档案目录 `mas-sit/`，运维时间线 `docs/operations/mas-sit.md`。旧 VM 130（`mas-sit-al2023`）关机保留作回滚，到期 2026-11-07，回滚步骤见 `docs/operations/mas-sit.md` 2026-10-31 条目。同时跑着 self-hosted GitHub Actions runner，停机或重启容器会影响 CI 与已部署的 SIT
- `icare-uat-runner-1` / `icare-uat-runner-2` 是 Azure UAT 发版机（组 `icare-2-uat`）。档案见 `icare-uat-runner-1/README.md`、`icare-uat-runner-2/README.md`。Buildx local cache 路径是 `/var/cache/buildx`，属主必须是 runner 用户 `icareadmin`；`/var/cache` 属 root，新 burst 机不预建就会在 `Prepare backend build cache` 上 Permission denied。`icare-uat-runner-2` 已于 2026-08-23 补齐。wait slot 只在 runner-1，不要装到 runner-2。
- `mac-mini` 目录约定（2026-10-22/23 迁到 hon，计划 `docs/plans/2026-10-22-1645-ops-mac-mini-team-assets-to-hon-plan.md`）：
  - `/Users/hon/actions-runner/<name>/` — 全部 15 个 runner（sonar-1..4、mobile-1、mac-mini-kanova-ci-1..5、qingfan-ci-1..3、caimiamiao-1、konghai-friends-lab-1；acquilang-native-1 已于 2026-10-30 移除，moo-decision 的 khmini 已于 2026-10-31 删除），LaunchDaemon `UserName=hon`、`HOME=/Users/hon`。plist 里残留的 `DOCKER_HOST=unix:///Users/hon/.colima/team/docker.sock` 已经失效：colima team 已停，mac-mini 上的 job **不能**再用 Docker，需要 Docker 的 job 写 `runs-on: [self-hosted, team-svc]`（见 `team-svc/README.md`）。`mac-mini-kanova-ci-4/5` 保持 disabled。启停见 `docs/runbooks/mac-mini-runner-start-stop.md`
  - workFolder 在 CIWork 卷：sonar `s{1..4}`、mobile `m1`、Kanova CI `alc{1..5}`、qingfan `qf{1..3}`、caimiamiao `cmm1`、friends-lab `kfl1`、khmini `khm1`
  - `/Users/hon/gha` 是独立 APFS 卷 `CIWork` 的挂载点（`/etc/fstab` 按 UUID 挂载，`.fseventsd/no_log`，Spotlight 关闭，quota 300G），不是普通目录。卷没挂上时挂载点是 root 所有的空目录，runner 会报权限错误。卸载时常驻 `spindump` / `mds` 会只读占用，需 `diskutil unmount force`
  - 缓存：per-slot `gha/cache/go-build-{s1..s4,cmm1,khm1,qf1..qf3}`，共享 `gha/cache/go-mod`、`gha/cache/pnpm-store`。runner 目录里的 `bin` / `externals` 必须是相对符号链接（runner 自更新会写绝对路径，挪目录后会断）
  - 团队服务（2026-10-31 起，计划 `docs/plans/2026-10-31-0010-ops-mac-mini-vms-to-pve-plan.md`）：stack 全部迁到 PVE `team-svc` 的 `/opt/stacks/<name>`。mac-mini 上的老地址靠 hon 的 `~/.local/bin/team-svc-forwarders`（源码 `scripts/mac-mini-team-svc-forwarders.sh`，hon crontab `@reboot` 拉起，日志 `~/Library/Logs/team-svc-forwarders.log`）用 `/usr/bin/ssh -N -L` 转发：`0.0.0.0` 上 9000、5432、5433、5437、3001、18080；`127.0.0.1` 上 5434、6379、3900（Tailscale serve 仍转这三个），以及 moo 的 15432、16379、19000、9092、8083、19094（给经 `ssh khmini` 建隧道的开发机用）；tailnet IP 上 18188（moo-app 旧地址）。**不要**换成 socat：mac-mini 开着应用防火墙，未签名程序收不到外部入站
  - colima：`team` 已于 2026-10-31 停止，它的 LaunchDaemon `system/com.cypressoai.colima-team` 已被 bootout 并 disable（plist 文件还在 `/Library/LaunchDaemons`）；`moo` 已停（`moo-colima-supervisor` 已从 crontab 去掉），`multica` 已删。两个磁盘留作回滚，计划 7 天后经确认再删。如果要临时恢复 team：先 `enable` 再 `bootstrap` 这个 LaunchDaemon。注意守护进程里的 `colima start --foreground` 在 `colima stop` 后会挂住不退出，要 `kill` 它，launchd 才会重新拉起
  - moo-app 已于 2026-10-31 迁到 team-svc（`/opt/moo-app`）。mac-mini 上的 `~/moo-app` 只剩旧的 darwin 回滚包、备份和日志，launchd plist 目录已改名为 `launchd.disabled-20261031`，**不要**再启动，否则会出现两个 worker。旧地址 `http://mac-mini.taila93443.ts.net:18188` 由转发器绑定 tailnet IP 转到 team-svc。khmini runner 已删除（LaunchDaemon 已 bootout 并 disable，GitHub 上已移除），目录 `~/actions-runner/khmini` 和 workFolder `khm1` 还没删
  - 定时任务（hon 的 LaunchDaemon，源码 `scripts/install-mac-mini-team-services-daemons.sh`）：`com.cypressoai.sonarqube-backup` 03:30、`com.cypressoai.acquilang-backup` 04:00、`com.cypressoai.gha-runner-maintenance{,-weekly}` 03:15 / 周日 04:30；`com.cypressoai.acquilang-prod-sync`（0/6/12/18 点）已装但 **disabled**（生产同步自 10-19 失败，nyh-prod 受限密钥未落地）。两个备份脚本内部 `export DOCKER_HOST=ssh://ubuntu@192.168.2.23`，经 ssh 远程调用 team-svc 上的 Docker；备份文件仍落在 `/Users/hon/backups/`
  - 签名与团队凭据只在 hon 下（600）：`~/.config/icare/{preview,production}`、`~/.config/acquilang/backend-ci.env`（AcquiLang CI 的 `ACQUILANG_BACKEND_ENV`）；Android SDK `~/Library/Android/sdk`。hon 下所有进程都能读到它们，这是用户接受的风险
  - Homebrew 仍归 `konghai`，hon 只读 / 执行 `/opt/homebrew`。`azure-cli` **必须**是 `/opt/homebrew/bin/az`（跟 brew 最新稳定即可），幂等安装 `brew list azure-cli || brew install azure-cli`，runner 的 launchd PATH 已含 `/opt/homebrew/bin`，装完不必改 plist、不必重启 runner；不要装到 `/usr/local/bin`
  - bash：2026-10-28 起装了 Homebrew bash 5（`/opt/homebrew/bin/bash`），runner `.path` 里它排在 `/bin` 前，所以 CI 的 `shell: bash` 是 5.x。plist 写死 `/bin/bash` 的 LaunchDaemon（`fseventsd-watchdog`、维护任务）和 `sudo` 跑的脚本仍是 3.2（不要改成 Homebrew bash：`/opt/homebrew` 归普通用户可写，root 执行它等于提权），这些脚本必须兼容 3.2
  - **不要**给 runner 写 Azure storage connection string / account key。GHA 上传走 OIDC（`azure/login` + `--auth-mode login`）。交互 `az login` 只给人手工验证；SSH 进来时用 `az login --use-device-code`（无图形会话时默认 `az login` 会 osascript `-10810`）。装 `az` **不会**让 `ota-publish-js.yml` 自动直传 Blob
  - fseventsd 看门狗：LaunchDaemon `system/com.konghai.fseventsd-watchdog`，每 5 分钟跑 `/usr/local/sbin/fseventsd-watchdog.sh`（源码 `scripts/mac-mini-fseventsd-watchdog.sh`）。内存 ≥1G 抓现场、≥4G 自动 `killall fseventsd`；日志和现场在 `/var/log/fseventsd-watchdog/`，`konghai` 可直接读（label 名保留 `com.konghai.*`，是系统级服务，与账户无关）
- `lemon-imac` 目录约定：
  - `/Users/for-konghai/actions-runner/lemon-imac-{1,2}/` — GitHub Actions runner 程序与配置，`.env` 内含 per-slot `GOCACHE`
  - `/Users/for-konghai/gha/li{1,2}` — 对应 slot 的短路径 workFolder（2026-08-08 由不对称的 `li`/`li2` 统一而来）；`lemon-imac-kanova-ci-1` 的 workFolder 是 `/Users/for-konghai/gha/alci1`
  - `lemon-imac-qingfan-ci-1`（2026-10-30）— `IAmKongHai/qingfan` 仓库级 runner，只带 `qingfan-frontend`，只跑前端分片；workFolder `~/gha/qf1`，npm 缓存 `~/gha/cache/qingfan-npm`，LaunchDaemon `system/actions.runner.IAmKongHai-qingfan.lemon-imac-qingfan-ci-1`。安装脚本 `scripts/install-lemon-imac-qingfan-ci-runner-daemon.sh` 同时把 `qf1` 加进两个维护 plist 的 `WORK_DIRS`
  - 改 workFolder 时必须同步改两个维护 LaunchDaemon plist 里硬编码的 `WORK_DIRS`，否则每日/每周清理会静默失效、磁盘涨回去
  - `/Users/for-konghai/gha` 是独立 APFS 卷 `CIWork` 的挂载点（2026-10-21 迁入；`disk3s7`，UUID `C5079133-03F5-4185-8107-E7514202F50E`，`.fseventsd/no_log`，Spotlight 关闭，quota 100G），不是普通目录。卷没挂上时挂载点是 root 所有的空目录
  - CIWork **不走 `/etc/fstab`**：写 fstab 需要 TCC 的 `SystemPolicySysAdminFiles`，SSH（`sshd-keygen-wrapper`）和 launchd 拉起的 bash 都被拒，root 也不行。改由 LaunchDaemon `system/com.konghai.ciwork-mount`（`RunAtLoad` + 每 5 分钟）跑 `/usr/local/sbin/ciwork-mount.sh`，卷不在 `~/gha` 就挪过去；日志 `/var/log/ciwork-mount.log`。源码 `scripts/install-lemon-imac-ciwork-automount.sh`
  - 4 个 runner plist 是 `RunAtLoad false` + `KeepAlive.PathState` 盯 `~/gha/.ciwork-mounted`（卷根目录的标记文件）：卷没挂好 runner 就不启动，GitHub 上显示 offline。runner 全部 offline 时先看卷挂没挂、`ciwork-mount.log`，再看是不是 FileVault 还没解锁
  - `/Users/for-konghai/gha/cache/go-build-li{1,2}` — per-slot Go 编译缓存（共享 `GOMODCACHE=~/go/pkg/mod`）。路径同时写在 `.env`、runner plist 的 `GOCACHE` 和维护 plist 的 `GOCACHE_DIRS` 里，改路径要改 `scripts/install-lemon-imac-runner-daemons.sh` 后重跑，`.env` 另改。**不要**用符号链接代替：维护脚本的 `find` / `du` 不跟进符号链接，清理会静默失效
  - `/Users/for-konghai/gha/cache/pnpm-store` — 本机 pnpm store（两 slot 共享）；kanova 用 `gha/cache/acquilang-pnpm-store` 和 `gha/cache/acquilang-npm`
  - `/Users/for-konghai/gha/scripts/` — 维护与启停脚本（`gha-runner-maintenance.sh`、`prune-gocache.sh`、`install-lemon-imac-runner-daemons.sh`、`install-lemon-imac-acquilang-ci-runner-daemon.sh`、`install-lemon-imac-qingfan-ci-runner-daemon.sh`、`install-lemon-imac-ciwork-automount.sh`、`install-lemon-imac-fseventsd-watchdog.sh`、`lemon-imac-runner-resume.sh`、`rename-lemon-imac-kanova-ci-runner.sh`）
  - LaunchDaemon（2026-08-19 起，注销图形用户后仍在线）：runner 为 `system/actions.runner.cypressoai.lemon-imac-{1,2}` 、`system/actions.runner.IAmKongHai-Kanova.lemon-imac-kanova-ci-1` 和 `system/actions.runner.IAmKongHai-qingfan.lemon-imac-qingfan-ci-1`；维护任务为 `system/com.cypressoai.gha-runner-maintenance{,-weekly}`（crontab 被 TCC 拒绝，不能再改回 LaunchAgent）。**不要** `./svc.sh install` / `start`，那会把 LaunchAgent 装回 `~/Library/LaunchAgents` 并和 Daemon 双开。启停见 `docs/runbooks/lemon-imac-runner-start-stop.md`。被 `launchctl disable` 过的 runner 要先 `enable` 再 `bootstrap`，否则报 `Bootstrap failed: 5: Input/output error`
  - 计划内重启用 `sudo fdesetup authrestart`（下次开机自动解锁一次）。意外关机后 Data 卷锁着，所有 LaunchDaemon（runner、挂载、看门狗）都要等朋友本人登录解锁才会起来，属正常
  - fseventsd 看门狗：LaunchDaemon `system/com.konghai.fseventsd-watchdog`，每 5 分钟跑 `/usr/local/sbin/fseventsd-watchdog.sh`（与 mac-mini 共用源码 `scripts/mac-mini-fseventsd-watchdog.sh`，安装用 `scripts/install-lemon-imac-fseventsd-watchdog.sh`）。8GB 机器阈值调低：内存 ≥512M 抓现场、≥2G 自动 `killall fseventsd`（plist 里的 `CAPTURE_MB` / `KILL_MB`）；日志和现场在 `/var/log/fseventsd-watchdog/`，`for-konghai` 可直接读
  - Tailscale：Homebrew `tailscaled` 1.102.2，LaunchDaemon `system/homebrew.mxcl.tailscale`，节点 `100.81.246.93` / MagicDNS `lemon-imac`。**不要**再装 GUI Standalone（会和 daemon 抢隧道）。CLI：`/opt/homebrew/bin/tailscale`
  - bash：2026-10-28 起装了 Homebrew bash 5。`lemon-imac-{1,2}` 的 `.path` 以 `/opt/homebrew/bin` 开头，`shell: bash` 是 5.x；`lemon-imac-kanova-ci-1` 的 `.path` 不含 `/opt/homebrew/bin`（有意不暴露其它 brew 工具），而是在最前面加了只含 `bash` 符号链接的 `~/actions-runner/lemon-imac-kanova-ci-1/shims`，同样是 5.x；改 `.path` 后要重启该 runner 才生效。plist 写死 `/bin/bash` 的 LaunchDaemon（`ciwork-mount`、`fseventsd-watchdog`、维护任务）保持不变，脚本必须兼容 3.2
  - 当前 labels 同 `umacbook-pro`（Tests + 质量 + 后端池；详见 `docs/runbooks/ci-runner-pools.md`）
  - 8GB 内存 + 双 slot 并发容易顶满内存/磁盘，重活优先派给 `mac-mini`
- `umacbook-pro` 目录约定：
  - `/Users/for-konghai/actions-runner/umacbook-pro-{1,2}/` — GitHub Actions runner 程序与配置，`.env` 内含 per-slot `GOCACHE`
  - `/Users/for-konghai/gha/u{1,2}/` — 对应 slot 的短路径 workFolder
  - `/Users/for-konghai/gha/scripts/` — 维护与启停脚本（`gha-runner-maintenance.sh`、`install-umacbook-pro-runner-daemons.sh`、`umacbook-pro-runner-pause.sh`、`umacbook-pro-runner-resume.sh`、`start-umacbook-pro-tailscaled.sh`）。带到学校用 pause（disable+bootout，保留 Tailscale）；回来用 resume。
  - LaunchDaemon（2026-08-19 起，注销图形用户后仍在线）：runner 为 `system/actions.runner.cypressoai.umacbook-pro-{1,2}`；维护任务为 `system/com.cypressoai.gha-runner-maintenance{,-weekly}`（原 crontab 已删，避免双跑）。**不要** `./svc.sh install` / `start`。启停见 `docs/runbooks/umacbook-pro-runner-start-stop.md`
  - Tailscale：Homebrew `tailscaled` 1.102.2，LaunchDaemon `system/homebrew.mxcl.tailscale`，节点 `100.113.23.49` / MagicDNS `umacbook-pro`。**不要**再装 GUI Standalone（会和 daemon 抢隧道）。CLI：`/opt/homebrew/bin/tailscale`
  - 当前 labels：`self-hosted,macos,arm64,macos-arm64,umacbook-pro,frontend-tests-ci,frontend-quality-ci,backend-ci`（Tests + 质量 + 后端池；详见 `docs/runbooks/ci-runner-pools.md`）
- `mas-sit` 上的目录约定：
  - `/opt/mas-sit/backend/` — iCare backend 部署目录，每次 PR 由 runner 同步 `backend.compose.yaml`、构建镜像并滚动 `api` + `worker` 容器；`.env.docker` 在此本地维护（600 权限），仓库内对应 `backend/.env.docker.example`
  - `/opt/mas-sit/frontend-mas/` — iCare frontend-mas 部署目录，同上由 runner 维护
  - `/opt/mas-sit/infra/` — iCare 集成测试基础设施目录，承载 `infra.compose.yaml`（`icare-backend-infra` compose project），跑 `azurite` + `redis` 两个常驻容器供 worker / api 经 `shared-services` 网络通过 DNS 名 `azurite` / `redis` 访问。**不由 runner 自动管理**，仅在仓库内 `backend/infra.compose.yaml` 变更或手动调整基础设施时执行 `sudo -u actions-runner docker compose -f infra.compose.yaml up -d`；容器使用 `restart: always`，VM 重启后自动拉起
  - `/opt/mas-sit/logs/` — 运维日志归档
  - `/opt/shared-sit/` — 全项目 SIT 共享基础设施（属主 `ec2-user`，**不要**放进 `/opt/mas-sit`，runner 不管）。`postgres/` 为 PostgreSQL 18，`s3/` 为 Garage，`redis/` 为 Redis 7（宿主 `6380`，容器名 `shared-sit-redis`，网络别名 `redis`；`6379` / 容器名 `redis` 是 iCare 的）。Docker 网络 `shared-sit`，端口只绑 Tailscale `100.109.223.53` 与回环。新项目单独建库/角色、bucket/密钥和 Redis DB 号，不要用管理员账号，也不要复用 iCare 的 `shared-services` / azurite / redis。凭据在服务器 600 文件；本仓库 `mas-sit/secrets.local.md`（gitignore）。档案见 `mas-sit/README.md`
  - `/opt/evp-sit/` — EVP SIT（`evp-sit` compose，属主 `actions-runner`）。医院端 `100.109.223.53:25173`，管理端 `:25174`。加入 `shared-sit` 网络。由 org runner `shared-sit`（组 `shared-sit`）部署，**不要**用 iCare 的 `mas-sit` runner。
  - `/opt/actions-runner/shared-sit/` — 非 iCare SIT 部署 runner（systemd `actions.runner.cypressoai.shared-sit`）。labels 含 `shared-sit`，不含 `mas-sit` / 质量池。工作目录 `_work`。

## 检索历史方案

下次接到类似问题前先看 `docs/solutions/`：

```bash
# 按服务器
grep -rl "server: nyh-prod" docs/solutions/

# 按关键词
grep -ri "宝塔\|baota\|bt-panel" docs/solutions/

# 按 tag
grep -r "tags:.*ssl-cert" docs/solutions/
```

`CONCEPTS.md` 记录项目内有特定含义的共享术语（实体、命名流程、状态概念），适合在梳理运维背景或讨论领域概念前快速对齐词义。

## 文档风格

- 中文为主，技术名词、命令、路径、配置项保留英文原文
- 命令块用 fenced code block 标注语言（```bash、```nginx 等）
- 给出"做了什么"和"为什么"，避免只贴命令不解释
- 不要在文档里写明文密码、token、私钥
