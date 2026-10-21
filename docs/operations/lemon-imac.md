# lemon-imac 运维操作时间线

## 2026-10-21 22:15 CST - --finish 拉起 runner（CIWork 迁移完成），退出 for-konghai 图形会话

- 服务器：`lemon-imac`
- 操作人：用户执行 `--finish`（两次）；`Claude` 修脚本、验证，并经用户要求通过 SSH 退出 for-konghai 图形会话。
- 原因：重启验证通过后恢复 CI；for-konghai 的图形会话是开机解锁后登录的，runner 不依赖它，占内存。
- 影响：CI 从 11:45:44 停到 22:12:17，约 10.5 小时（含用户要求的等待和 8 小时 FileVault 待解锁）。
- 变更时序：
  - 22:08 第一次 `--finish`：`.env` 的 GOCACHE 已改，安装器在 `lemon-imac-1` 上报 `Bootstrap failed: 5: Input/output error` 后退出。原因：重启前 runner 被 `launchctl disable`，而安装器是先 `bootstrap` 后 `enable`，disabled 的服务 bootstrap 会报 5。修复：安装器的 `install_daemon` 改为先 `enable`；`finish` 在调用安装器前先 enable 3 个 runner。plist 备份 `*.bak-ciwork-20261021` 是改前原版，重跑不会覆盖。
  - 22:12 第二次 `--finish`：4 个 plist 重写并加载，`Runner.Listener 数量：3（期望 3）`。末尾 `start_runners` 对已加载的 lemon-imac-1/2 再 bootstrap 报了两次 `5`，属预期（已加载）。
  - 22:14 `osascript -e 'tell application "loginwindow" to «event aevtrlgo»'` 退出 for-konghai 图形会话（只开着终端和 Siri AI），不弹确认框，返回 0。
- 验证：
  - 3 个 runner `state = running`、enabled，`KeepAlive.PathState` 为 `~/gha/.ciwork-mounted`。lemon-imac-1/2 的 GOCACHE 为 `~/gha/cache/go-build-li{1,2}`，维护任务 `GOCACHE_DIRS` 同步更新。
  - 日志 14:12:17Z / 14:12:18Z / 14:12:23Z 均为 `Listening for Jobs`。GitHub API：`lemon-imac-acquilang-ci-1` online。cypressoai org 的 runner 列表本机 token 无权限查询（403）。
  - 退出登录后 `who` 只剩 `zhangli console`，`/dev/console` 属主为 root（登录窗口）。
  - 22:17:00 zhangli 的图形会话也退出了（loginwindow PID 1256，`logout state: LogoutComplete`）。这一步不是 `Claude` 执行的：for-konghai 退出 15 秒后 zhangli 还在。22:18 起本机没有任何图形会话，只剩 SSH。3 个 `Runner.Listener` PID 不变（3439 / 3444 / 3464），CIWork 仍挂在 `~/gha`。
- 回滚方式：见本日 12:55 条目。
- 待办：
  1. 观察迁移后第一个 job 结果。
  2. CI 正常几天后删除备份：`~/gha.pre-ciwork-20261021`（约 9G）、`~/actions-runner/lemon-imac-{1,2}/cache/go-build`（约 10.5G）、`/Library/LaunchDaemons/*.bak-ciwork-20261021`、`*.bak-automount-20261021`。
  3. 由用户决定是否关闭 FileVault；计划内重启改用 `sudo fdesetup authrestart`。

## 2026-10-21 22:06 CST - 重启验证 CIWork 开机自动挂载（通过）；发现 FileVault 让重启后卡在解锁界面 8 小时

- 服务器：`lemon-imac`
- 操作人：用户执行 `install-lemon-imac-ciwork-automount.sh` 并 `sudo reboot`；`Claude` 只读验证。
- 影响：只读。runner 仍按用户要求 disabled，CI 继续停机。
- 备份：`install-lemon-imac-ciwork-automount.sh` 已生成 acquilang plist 备份 `*.bak-automount-20261021`。
- 回滚方式：见本日 12:55 条目。
- 验证：
  - 13:43 安装（标记 `~/gha/.ciwork-mounted` 时间 13:43），随即重启；`kern.boottime` 为 13:43:30。
  - `/var/log/ciwork-mount.log`：`21:59:42 CIWork 当前挂载点：/Volumes/CIWork，挂到 /Users/for-konghai/gha` → `21:59:52 已挂载；marker 存在`。开机后系统先自动挂到 `/Volumes/CIWork`，守护 10 秒内挪到目标位置。`com.konghai.ciwork-mount` `runs = 1`、`last exit code = 0`、`run interval = 300 seconds`，err 日志为空。
  - `diskutil info CIWork` 的 Mount Point 为 `/Users/for-konghai/gha`，用量 21G，与迁移时一致。
  - 3 个 runner 仍为 disabled，没有 `Runner.Listener`。acquilang plist 已是 `RunAtLoad false` + `KeepAlive.PathState`。
  - fseventsd 看门狗随开机运行，新 fseventsd PID 1184，footprint 3–6M，swap 归零。
  - `~/gha/scripts` 上的迁移脚本、两个安装器与仓库一致。
- 发现：**FileVault 已开启**（`fdesetup status`）。13:43 重启后 Data 卷一直锁着，`/Library/LaunchDaemons` 里的服务（看门狗、挂载守护、runner）都起不来。看门狗日志在 13:40 到 21:59 之间是空的，直到 21:59 有人在本机控制台登录（`who`：`zhangli console 21:59`）才解锁。也就是说，这台机器只要重启或断电，CI 就会一直掉线，直到有人到场输密码。
  - 计划内重启改用 `sudo fdesetup authrestart`：下次开机自动解锁一次，不用到场。
  - 要扛住断电、自动更新这类意外重启，只能关 FileVault，由用户决定。
- 现象：解锁登录后 load 冲到 108–163（iconservicesagent、Siri、BiomeAgent、mediaanalysisd 等登录后的初始化），两分钟后回落到 35，没有 swap。
- 待办：用户执行 `--finish` 拉起 runner；决定 FileVault 怎么处理。

## 2026-10-21 12:55 CST - CIWork 迁移：fstab 被 TCC 拒绝，改用挂载守护 + runner PathState（进行中，CI 停机）

- 服务器：`lemon-imac`
- 操作人：用户执行各 sudo 步骤；脚本由 `Claude` 编写。用户要求 CI 一直停着，全部弄好、验证重启后再拉起。
- 原因：11:45 起用户依次执行了看门狗安装、`--prepare`、`--migrate`。看门狗正常（`CAPTURE_MB=512`、`KILL_MB=2048`，每 5 分钟一行）。`--migrate` 在 11:49:52 写 `/etc/fstab` 时失败退出。
- 当前状态：
  - `CIWork`（`disk3s7`，UUID `C5079133-03F5-4185-8107-E7514202F50E`，quota 100G，`no_log`，Spotlight off）已挂在 `/Users/for-konghai/gha`，用量 21G。原目录在 `~/gha.pre-ciwork-20261021`。
  - 3 个 runner 11:45:44 停止至今，并已 `launchctl disable`，重启也不会拉起。`.env` / plist 的 GOCACHE 还是旧路径。
- 排查：
  - 统一日志：`Refusing TCCAccessRequest for service kTCCServiceSystemPolicySysAdminFiles from client ... sshd-keygen-wrapper`，`bash deny file-write-create /private/etc/fstab`。TCC 按责任进程（sshd）判定，euid 0 也不行。7 月 crontab 被拒是同一原因。
  - 12:49 改用一次性 LaunchDaemon 由 launchd 拉起 `/bin/bash` 写 fstab（`lemon-imac-ciwork-fstab-via-launchd.sh`），同样 `Operation not permitted`。
  - 屏幕共享登不进去，无法在图形界面给"终端"或 sshd 授完全磁盘访问权限。`screensharingd` 日志为 `client evidence does not match ... Probably a password error`（RSA-SRP）。12:36–12:39 for-konghai 失败 4 次、zhangli 失败 1 次，不像是单个账户的密码数据问题，原因未明。
  - 坑：zsh 有内置 `log` 命令，SSH 里查统一日志必须写 `/usr/bin/log`，否则什么都查不到。
- 方案（B）：放弃 fstab。
  - 新增 `install-lemon-imac-ciwork-automount.sh`：LaunchDaemon `system/com.konghai.ciwork-mount`（`RunAtLoad` + 每 5 分钟），跑 `/usr/local/sbin/ciwork-mount.sh`，卷不在 `~/gha` 就卸下再挂过去，日志 `/var/log/ciwork-mount.log`。卷根目录放标记 `.ciwork-mounted`。
  - 3 个 runner plist 改为 `RunAtLoad false` + `KeepAlive { PathState { ~/gha/.ciwork-mounted: true } }`：卷没挂好就不启动（GitHub 上 offline），不会接 job 后在 root 所有的空挂载点上报错。`install-lemon-imac-runner-daemons.sh` / `install-lemon-imac-acquilang-ci-runner-daemon.sh` 模板同步修改；acquilang 现有 plist 用 PlistBuddy 原地改，备份 `*.bak-automount-<日期>`。
  - `--finish` 有挂载守护时不再写 fstab，拉起前检查标记，`start_runners` 先 `launchctl enable`。
- 验证：本机 gui 域实测 `PathState`：无标记不启动；建标记立即启动；进程退出且标记仍在时自动重启。PlistBuddy 改 acquilang plist 副本 `plutil -lint` 通过。
- 回滚方式：`bootout` 并删除 `com.konghai.ciwork-mount` 的 plist 和脚本，用 `*.bak-automount-*` / `*.bak-ciwork-*` 还原 plist 和 `.env`；卸载 CIWork 后把 `~/gha.pre-ciwork-20261021` 改回 `~/gha`，再 enable + bootstrap 3 个 runner。
- 待办：用户执行 `install-lemon-imac-ciwork-automount.sh` → `sudo reboot` → 确认开机自动挂载、runner 未启动 → `--finish`。

## 2026-10-21 11:45 CST - 准备 fseventsd 看门狗与 CIWork 独立卷迁移脚本（尚未执行 sudo 步骤）

- 服务器：`lemon-imac`
- 操作人：`Claude`。用户要求参照 mac-mini 给这台机器加 fseventsd 看门狗，并建 runner 专用的独立卷（`no_log`）。
- 影响：只把脚本同步到 `~/gha/scripts/`，没有改 LaunchDaemon、没有建卷、没有停 runner。
  - 新增 `install-lemon-imac-fseventsd-watchdog.sh`：安装 `system/com.konghai.fseventsd-watchdog`，复用 `mac-mini-fseventsd-watchdog.sh`。8GB 机器阈值调低为 footprint ≥ 512MB 抓现场、≥ 2048MB 自动 `killall fseventsd`。
  - 新增 `migrate-lemon-imac-ci-to-nofsevents-volume.sh`：按 mac-mini 流程建 `CIWork` 卷（`disk3`，quota 100G，`no_log`，关 Spotlight），等 3 个 runner 空闲后停掉，把 `~/gha`（约 9G）和两份 GOCACHE（约 10.5G）复制进卷，卷直接挂到 `/Users/for-konghai/gha` 并写 `/etc/fstab`。
  - `install-lemon-imac-runner-daemons.sh` 的 GOCACHE 改为 `~/gha/cache/go-build-li{1,2}`（runner plist 与维护 plist 的 `GOCACHE_DIRS` 同步）。迁移脚本在挂载后重跑它重写 plist，`.env` 用 sed 改。没用符号链接：维护脚本的 `find` / `du` 不跟进符号链接，GOCACHE 清理会静默失效。
- 备份：迁移脚本会保留 `~/gha.pre-ciwork-<日期>`、旧 `cache/go-build`、`.env.bak-ciwork-<日期>`、`/Library/LaunchDaemons/*.plist.bak-ciwork-<日期>`。
- 回滚方式：本次只同步了脚本，旧版安装器可从 git 历史取回；目前不需要回滚。
- 验证：三个脚本 `bash -n` 通过，`shellcheck -S warning` 无告警；看门狗脚本以普通用户、临时日志目录空跑一次，输出 `pid=565 etime=12-11:19:33 mem_mb=8 rss_mb=6`。
- 待办（需用户 sudo）：
  1. `sudo ~/gha/scripts/install-lemon-imac-fseventsd-watchdog.sh`
  2. `sudo ~/gha/scripts/migrate-lemon-imac-ci-to-nofsevents-volume.sh --prepare`
  3. 选 CI 空闲时段：`sudo ~/gha/scripts/migrate-lemon-imac-ci-to-nofsevents-volume.sh --migrate`

## 2026-10-21 11:35 CST - 只读排查 fseventsd 是否像 mac-mini 一样内存泄漏（结论：没有）

- 服务器：`lemon-imac`
- 操作人：`Claude`。mac-mini 前一天 fseventsd 泄漏到 32G（见 `docs/operations/mac-mini.md` 2026-10-20 11:35 条目），用户怀疑这台 macOS runner 机也有同样问题。
- 影响：只读。没有杀进程、没有改配置。
- 备份：无。
- 回滚方式：无变更，无需回滚。
- 现场（11:32）：
  - macOS 27.0.1（26A434），uptime 12 天 11 小时，load `1.55 / 1.63 / 1.73`（8 核）。
  - `fseventsd`（PID 565）随开机启动、从未重启，etime 12 天：`top` MEM（footprint，含压缩/换出）**8.3M**，RSS 6.6M，CPU 0%，累计 CPU 时间 111 分钟。
  - 同期负载不低：`lemon-imac-1` / `lemon-imac-2` 近 12 天分别有 237 / 218 个 `Worker_*.log`（约 455 个 job），另有 `lemon-imac-acquilang-ci-1` 在跑。
  - `mds_stores` 26M、`mds` 89M，正常。内存大头是 `zhangli` 图形会话里的 Finder（883M）、WindowServer、Office、微信。
  - swap 已用 1.87G / 3G，`memory_pressure` 显示空闲 71%，没有被挤爆。
  - Data 卷 145G / 228G（73%），可用 56G。
- 判断：这台没有 fseventsd 泄漏迹象，暂不需要像 mac-mini 那样装看门狗。mac-mini 的泄漏更可能和它特有的负载有关（三台 colima VM 经 virtiofs 挂整个家目录、4 个 sonar slot 并发 Go 链接），不是 macOS runner 的通病。
- 待办：之后做 runner 巡检时顺带看一眼 `top -l 1 -pid $(pgrep -x fseventsd) -stats mem`；超过 1G 再考虑把 mac-mini 的看门狗移植过来。

## 2026-10-10 11:37 CST - AcquiLang runner 改为 LaunchDaemon

- 服务器：`lemon-imac`；runner `lemon-imac-acquilang-ci-1`（GitHub id `28`）。
- 操作人：`konghai`（`sudo` 执行安装脚本）、`Grok`（核对服务和 GitHub）。
- 原因：11:27 注册后先用用户域 LaunchAgent 拉起。控制台是 `zhangli`，这个 Agent 在重启或用户域卸掉后不会自动回来。
- 影响：只切换这一个 AcquiLang runner 的拉起方式。卸下用户域 Agent 后马上由系统 LaunchDaemon 拉起，中间离线约一次重连。`lemon-imac-1/2` 没动。labels 不变。
- 备份：沿用 `~/gha/backups/acquilang-ci-20261010-1123/pre-state.txt`。系统 plist 是新文件，用户域 plist 已被脚本删除。
- 回滚方式：确认没有 `Runner.Worker` 后，`sudo launchctl bootout system/actions.runner.IAmKongHai-AcquiLangAI.lemon-imac-acquilang-ci-1`。注册和目录先留着。不要动 `lemon-imac-1/2`。
- 做了什么：用户在 lemon-imac 上执行 `sudo /Users/for-konghai/gha/scripts/install-lemon-imac-acquilang-ci-runner-daemon.sh`。脚本卸下用户域 Agent，写入 `/Library/LaunchDaemons/actions.runner.IAmKongHai-AcquiLangAI.lemon-imac-acquilang-ci-1.plist`（root、644）并 bootstrap。没有执行 `./svc.sh install`。
- 验证：11:37 CST，系统服务 `state=running`，pid `8772`，`runs=1`。Listener pid `8778`，日志 `2026-10-10 03:37:10Z: Listening for Jobs`。用户域服务和 `~/Library/LaunchAgents/` 里的同名 plist 已不在。GitHub id `28` 为 `online`、`busy=false`，labels 仍是 `self-hosted,macOS,ARM64,acquilang-build`。`lemon-imac-1`（id `32`）和 `lemon-imac-2`（id `31`）仍为 `online`。

## 2026-10-10 11:27 CST - 注册 AcquiLangAI 仓库级 runner

- 服务器：`lemon-imac`（`for-konghai`）；仓库 `IAmKongHai/AcquiLangAI`。
- 操作人：`Grok`
- 原因：mac-mini 上同时跑的 AcquiLang job 已经限制到 3 个，mas-go-dev 只有一个 Linux slot。这台 8 核 / 8GB 机器恢复后，加一个 macOS slot，让 backend / admin / web / native 可以再分出去。
- 影响：新增仓库级 runner `lemon-imac-acquilang-ci-1`（GitHub id `28`），labels `self-hosted,macOS,ARM64,acquilang-build`。没有 `acquilang-ci`，Sonar 仍只落 mac-mini 上带 localhost 测试库的 slot。没有 `acquilang-native-ci`、`lemon-imac`、`frontend-*`、`backend-ci`，不接 org 池和原生打包。现有 `lemon-imac-1/2` 没改。
- 选型：只注册一个 slot。当时负载约 1.7，内存 8GB，compressor 已经在用，空闲页很少。再加 slot 会和 org runner 抢内存。macOS 没有 cgroup，一台 runner 就是上限。
- 备份：`~/gha/backups/acquilang-ci-20261010-1123/pre-state.txt`（600）。只记录安装前的目录和磁盘。注册 token 用完即删，没有写入备份或仓库。
- 回滚方式：确认没有 `Runner.Worker` 后，`launchctl bootout user/502/actions.runner.IAmKongHai-AcquiLangAI.lemon-imac-acquilang-ci-1`，再删用户域 plist。注册、程序目录 `~/actions-runner/lemon-imac-acquilang-ci-1` 和工作目录 `~/gha/alci1` 先留着。不要动 `lemon-imac-1/2`。
- 做了什么：
  1. 只读确认机器在线：8 核，内存 8GB，Data 卷剩约 65Gi。控制台用户是 `zhangli`。`sudo` 需要密码。org runner `lemon-imac-1/2` 为 `online`。
  2. 下载并校验 `actions-runner-osx-arm64-2.337.0.tar.gz`（SHA-256 `5a2cd92908a93d7276a194e1de6008099f3e7946f3f8e14aa7a1a7b4a31fdec2`），解压到 `~/actions-runner/lemon-imac-acquilang-ci-1`，目录 700。工作目录 `~/gha/alci1`。
  3. `config.sh --unattended` 注册到仓库，额外 label 只有 `acquilang-build`，并显式带上 `macOS,ARM64`。没有使用 `--no-default-labels`。没有执行 `./svc.sh install`。根目录 `runsvc.sh` 从 `bin/runsvc.sh` 复制。
  4. `.env` 只写语言和本机缓存路径：`~/gha/cache/acquilang-pnpm-store`、`~/gha/cache/acquilang-npm`。不共用 org runner 的 pnpm store，也不复制 mac-mini 的后端 `.env`。`.credentials` 收成 600。
  5. 因为写 `/Library/LaunchDaemons` 需要密码，先用用户域 LaunchAgent（`LimitLoadToSessionType=Background`）拉起。安装脚本已放到 `~/gha/scripts/install-lemon-imac-acquilang-ci-runner-daemon.sh`。
- 验证：11:27 CST，GitHub 上 id `28` 为 `online`、`busy=false`，labels 是 `self-hosted,macOS,ARM64,acquilang-build`。用户域服务 `state=running`，pid `8704`，日志 `Listening for Jobs`。`lemon-imac-1/2` 的 Listener 仍在。
- 边界：重启或 `for-konghai` 用户域被卸掉后，这个 Agent 不会自动回来。要改成注销后仍在线，在这台机器上执行 `sudo /Users/for-konghai/gha/scripts/install-lemon-imac-acquilang-ci-runner-daemon.sh`。当前 workflow 的 backend 用 `uv` 安装 Python，Node 由 `actions/setup-node` 装 24，所以没有再装 Homebrew `python@3.12`。

## 2026-09-03 10:25 CST - 只读检查 lemon-imac-1/2 runner 状态

- 服务器：`lemon-imac`（runner `lemon-imac-1` / `lemon-imac-2`）
- 操作人：`Grok`
- 原因：用户要求检查本机 GitHub Actions runner 状态。
- 影响：仅 SSH 只读查询 + `gh api` 读 org runners；未改 LaunchDaemon、runner、Tailscale 或业务代码。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：
  1. 查 LaunchDaemon `system/actions.runner.cypressoai.lemon-imac-{1,2}`、`Runner.Listener` / `Runner.Worker`、磁盘与内存、Tailscale、`_diag` 日志。
  2. `gh api orgs/cypressoai/actions/runners` 核对 GitHub 侧 `status` / `busy` / labels。
- 验证结果：
  - GitHub：两 slot 均 `online`、`busy=false`。id `32`=`lemon-imac-1`，id `31`=`lemon-imac-2`。labels：`self-hosted,macos,arm64,macos-arm64,lemon-imac,frontend-tests-ci,frontend-quality-ci,backend-ci`。runner 版本 `2.336.0`。
  - 本机：两份 LaunchDaemon `state=running`、`enabled`、`runs=1`、`last exit code=(never exited)`。`runsvc.sh` / `RunnerService.js` 自 2026-08-26 00:17 起未退。Listener 进程于 2026-09-02 19:49 CST 起来（slot2 pid `11430`，slot1 pid `11444`），无 `Runner.Worker`（当前空闲）。维护任务 `gha-runner-maintenance{,-weekly}` 已 enabled、此刻未在跑。
  - Tailscale：`100.81.246.93` / MagicDNS `lemon-imac` 在线。控制台用户是 `zhangli`（自 08-26 00:17），不是 `for-konghai`。
  - 资源：uptime 8 天，load `2.03 1.88 1.69`（8 核）。内存 8GB，系统报告 free 约 69%，但 free pages 很少、compressor ~56k pages、swapins/swapouts 已过百万，8GB + GUI 占用仍紧。磁盘 Data 卷 228Gi 用 138Gi / 剩 65Gi（68%）。workFolder `gha/li1` 4.2G、`li2` 3.7G；runner 目录 `lemon-imac-1` 11G、`lemon-imac-2` 9.5G。
  - 日志：slot1 于 10:21:49 CST、slot2 于 10:22:19 CST 各 `Runner reconnected` 一次后 `Listening for Jobs`。当前 Listener 日志里各有约 840 次 `TaskCanceledException`（心跳超时后自愈），不是 LaunchDaemon 崩溃。最近 Worker 日志停在 09-02 17:54 / 17:51 CST。
- 备注：`umacbook-pro` 当时 Tailscale `offline, last seen 1d ago`，同池另一半不在线；本次未排查那台。

## 2026-08-22 23:49 CST - 只读确认 iCare-Operations-frontend verify 失败为 Prettier，不是 runner

- 服务器：`lemon-imac`（runner `lemon-imac-2`）
- 操作人：`Grok`
- 原因：排查 [iCare-Operations-frontend Job 97053728949](https://github.com/cypressoai/iCare-Operations-frontend/actions/runs/32582436907/job/97053728949)（run `32582436907`，PR [#8](https://github.com/cypressoai/iCare-Operations-frontend/pull/8) `docs/CYP-2262-agents-md`）是 runner 侧还是代码侧失败。
- 影响：仅 `gh` 读 Actions / PR；未改 runner、PATH、workflow 或业务代码，未重跑 Job。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：
  1. 核对目标 Job 的 runner 标签、全部步骤结论，以及失败步骤完整日志。
  2. 对照 PR #8 的唯一 commit `92c939aa…`（`docs: CYP-2262 add AGENTS.md for operations-frontend`）。
- 验证结果：
  - 目标 Job 落在 `lemon-imac-2`，labels `frontend-quality-ci`。checkout、`pnpm/action-setup@v4`、`setup-node`、`pnpm install --frozen-lockfile` 全部成功。
  - 唯一失败是 `pnpm format:check`：`prettier --check "**/*.{ts,tsx,css,md,json,yml}"` 报 **`AGENTS.md` Code style issues**，exit 1。lint / typecheck / tests / build 因前置失败被 skip；同 run 的 `SonarQube Scan` 因 `needs: verify` 未跑。
  - 不是 runner PATH / pnpm 未装 / 磁盘 / Tailscale 故障。根因在业务仓新增的 `AGENTS.md` 没过 Prettier。本地 `pnpm format` 或 `prettier --write AGENTS.md` 后重推即可。
- 备注：与 2026-08-22 `umacbook-pro` 上把 PR #6 Sonar Quality Gate 误判成 `pnpm: command not found` 同类——不要把后续 step skip 当成 runner 坏了。

## 2026-08-21 21:28 CST - 只读确认 iCare-backend Sonar 失败为 Quality Gate，不是 runner

- 服务器：`lemon-imac`（runner `lemon-imac-1`）；对照 `mac-mini` SonarQube、`umacbook-pro-2`
- 操作人：`Grok`
- 原因：排查 [iCare-backend Job 96778459722](https://github.com/cypressoai/iCare-backend/actions/runs/32484688601/job/96778459722)（run `32484688601`，PR [#1580](https://github.com/cypressoai/iCare-backend/pull/1580) `feature/CYP-2252/login-db-target`）是 runner 侧还是代码侧失败。
- 影响：仅 `gh` 读 Actions / check-run 与后续 run，本机 `curl` 确认 `mac-mini:9000` 健康；未改 runner、Tailscale、SonarQube、workflow 或业务代码，未重跑 Job。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：
  1. 核对目标 Job 全部步骤及同一 PR 前后 `SonarQube Analysis` runs。
  2. 本机确认 `http://mac-mini:9000/api/system/status` 为 `"status":"UP"`（Community Build `26.3.0.120487`，server id 与 Job 日志一致）。
  3. 对照失败 SHA `da2be8be…` 的 GitHub check-run 摘要，以及修复 commit `311a8765…` 后的 run `32485795797`。
- 验证结果：
  - 目标 Job 的 checkout、Setup Go、C toolchain、依赖下载、全量测试与 coverage 合并全部成功。同 run 的 `Lint` 也成功。Scanner 使用缓存 CLI `8.1.0.6389`，成功连上 SonarQube、上传 1.3 MB 分析报告。
  - 唯一失败是 Quality Gate：`QUALITY GATE STATUS: FAILED`，scanner 退出码 3。GitHub check `SonarQube Code Analysis` 摘要为 **1 New Issues (is greater than 0)**。
  - 根因在业务代码：`internal/server/handler/meta.go` 的 `hideDatabaseTarget` 对 `APP_ENV` 做 `switch` 只有 `prod`/`production` 分支、没有 `default`，命中规则 **S131**。不是 runner PATH / GPG / Tailscale / Sonar 宿主故障。
  - 同一 PR 随后提交 `CYP-2252 fix Sonar S131: add default to hideDatabaseTarget switch`。下一轮 `SonarQube Scan`（run `32485795797`，落在 `umacbook-pro-2`）已通过；当前 PR checks 全绿。
- 备注：lemon-imac 8GB 机仍适合承接 backend PR Sonar；本次约 11 分钟，其中测试 8 分钟、扫描 38 秒。与 2026-08-20 Tailscale errno 49 导致的 `Failed to query server version` 不是同一类失败。

## 2026-08-20 11:44 CST - SSH 注销 for-konghai 图形会话，runner / Tailscale 仍在

- 服务器：`lemon-imac`
- 操作人：`konghai`（先关自动登录）、`Grok`（`launchctl bootout gui/502`）
- 原因：GUI 占资源；屏幕共享进不去。`sudo launchctl reboot logout` 从 SSH 报 **125 Domain does not support specified action**（只能在 Aqua 域用）。
- 影响：
  - 用户已 `defaults delete autoLoginUser` 并删 `/etc/kcpassword`，避免注销后自动再登
  - `launchctl bootout gui/$(id -u)`（**无需 sudo**，SSH 里以 `for-konghai` 即可）拆掉 Aqua
  - `/dev/console` 现为 **root**（登录窗）；Finder / Dock 已无；`WindowServer` 仍在
  - `homebrew.mxcl.tailscale` 与 `lemon-imac-1/2` Listener 未断；GitHub 仍 online（当时 slot 2 busy）
- 备份：无。
- 回滚：人在键盘前登录 `for-konghai`。不要再开自动登录。
- 以后从 SSH 注销 GUI：`launchctl bootout gui/$(id -u)`，不要用 `launchctl reboot logout`。

## 2026-08-20 11:25 CST - 已 sudo 重启 brew tailscaled LaunchDaemon，Sonar TCP 恢复

- 服务器：`lemon-imac`
- 操作人：`konghai`（`sudo` 跑脚本）、`Grok`（核对日志 / 复测）
- 原因：08-19 换成 brew LaunchDaemon 后出站 TCP 对 tailnet `100.x` 报 errno 49，iCare-backend Sonar 扫 `mac-mini:9000` 失败。
- 影响：只 `kickstart -k system/homebrew.mxcl.tailscale`，随后 `tailscale up --hostname=lemon-imac --operator=for-konghai --accept-dns=true --accept-routes=false`。未改 runner、未改节点 IPv4、未装 GUI。
- 备份：无配置改动。旧进程 pid `5016`（08-19 17:13 起）。
- 回滚：再跑同一脚本，或 `sudo launchctl kickstart -k system/homebrew.mxcl.tailscale`。不要重装 GUI Standalone。
- 变更时序：
  1. 用户 SSH 执行 `sudo /Users/for-konghai/gha/scripts/restart-lemon-imac-tailscaled.sh`
  2. 脚本 `kickstart -k`，新 pid **79923**，IPv4 仍是 `100.81.246.93`
  3. 日志：`/tmp/restart-lemon-imac-tailscaled.log`（11:25:17–11:25:26 CST）
- 验证：
  - `curl http://mac-mini:9000/api/system/status` HTTP **200**，`"status":"UP"`（~27ms）
  - 直连 IP `100.108.64.126:9000` HTTP 200；`python` TCP `OK 100.81.246.93 → 100.108.64.126:9000`
  - `/api/v2/analysis/version` 无 token 返回 **401**（通了，不是 connect 失败）
  - `tailscale debug dial-types`：BareDial / UserDial / PeerDial 均为 `connected=true`（重启前全是 errno 49）
  - runner `lemon-imac-1/2` 仍 `running`
- 备注：日志里 `Some peers are advertising routes but --accept-routes is false` 是预期（本机不当 subnet router 客户端）。失败 Job [96292948777](https://github.com/cypressoai/iCare-backend/actions/runs/32320380460/job/96292948777) 现可 re-run。

## 2026-08-20 11:22 CST - 放入重启 Tailscale LaunchDaemon 脚本，已于 11:25 sudo 执行


- 服务器：`lemon-imac`
- 操作人：`Grok`（写脚本 / scp）、`konghai`（待 sudo）
- 原因：iCare-backend Sonar 在 lemon 上因 Tailscale 出站 TCP errno 49 失败。`for-konghai` 无免密 sudo，无法远程 `kickstart` LaunchDaemon。
- 影响：
  - 仓库新增 `scripts/restart-lemon-imac-tailscaled.sh`，已拷到 `~/gha/scripts/restart-lemon-imac-tailscaled.sh`
  - 当时尚未执行。已于 11:25 由用户 `sudo` 跑完，见上一条。
  - 未改 runner、未改 hostname、期望节点 IPv4 仍是 `100.81.246.93`
- 备份：无（新脚本）。现网 daemon 仍是 08-19 起的 pid `5016`
- 回滚：删该脚本即可；已加载的 LaunchDaemon 不受「只拷脚本」影响
- 执行（用户 SSH 上 lemon-imac）：
  ```bash
  sudo /Users/for-konghai/gha/scripts/restart-lemon-imac-tailscaled.sh
  ```
  会话掉线后重连：`ssh lemon-imac`，再 `cat /tmp/restart-lemon-imac-tailscaled.log`
- 备注：11:18 已用 operator 做了一次 `tailscale down --accept-risk=lose-ssh` + `up`（**未**换 pid）。之后本机 `curl http://mac-mini:9000/api/system/status` 已是 HTTP 200，TCP errno 49 暂时消失。完整重启 daemon 仍建议跑本脚本，避免只是 userspace down/up 的临时恢复。

## 2026-08-20 11:11 CST - 放入 ToDesk 干净卸载脚本，待本机 sudo

- 服务器：`lemon-imac`
- 操作人：`Grok`（scp）、`konghai`（待 sudo）
- 原因：用户要在 lemon-imac / umacbook-pro 上彻底卸优趣 ToDesk，远程入口改走 SSH + Tailscale Daemon。
- 影响：只拷了 `~/gha/scripts/uninstall-todesk.sh`（仓库 `scripts/uninstall-todesk.sh`）。**尚未执行**。
- 备份：无。
- 回滚：删该脚本即可。
- 执行（用户本机）：`sudo /Users/for-konghai/gha/scripts/uninstall-todesk.sh --apply`。会卸 App、LaunchDaemon/Agent、HAL 虚拟声卡；不碰 ToDesktop。

## 2026-08-20 10:45 CST - 只读确认 iCare-backend Sonar 失败为 lemon-imac Tailscale 出站 TCP 不可用

- 服务器：`lemon-imac`（runner `lemon-imac-1`）；对照 `mac-mini` SonarQube、`umacbook-pro`、`mas-go-dev`
- 操作人：`Grok`
- 原因：排查 [iCare-backend Job 96292948777](https://github.com/cypressoai/iCare-backend/actions/runs/32320380460/job/96292948777)（run `32320380460`，PR `bugfix/CYP-2204/announcement-notification`）是代码侧还是 runner 网络侧失败。
- 影响：仅 `gh` 读 Actions 日志，并 SSH 只读检查 MagicDNS、Tailscale ping、TCP 连通性与 Sonar HTTP；未重启 `tailscaled`、未改 runner / LaunchDaemon / workflow / 业务代码，未重跑 Job。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：
  1. 核对目标 Job 全部步骤及同一时段前后 `SonarQube Analysis` runs。
  2. 在 `lemon-imac` 解析 `mac-mini`、`curl`/`nc`/`python socket` 连 `100.108.64.126:9000` 与 `:22`，并 `tailscale ping` / `debug dial-types`。
  3. 对照 `mac-mini` 本机 Sonar 健康、以及 `umacbook-pro` / `mas-go-dev` 访问 `http://mac-mini:9000/api/system/status`。
- 验证结果：
  - 目标 Job 的 checkout、Setup Go、C toolchain、依赖下载、全量测试与 coverage 合并全部成功。同 run 的 `Lint` 也成功。唯一失败是 `SonarSource/sonarqube-scan-action` 查询 `SONAR_HOST_URL` 的 `/api/v2/analysis/version`：
    ```
    ERROR Failed to query server version: Call to URL [***/api/v2/analysis/version] failed: Can't assign requested address
    ```
    Scanner CLI 8.1.0.6389，runner `lemon-imac-1`，约 10:34 CST。因此不是业务代码或测试失败。
  - `mac-mini` 上 Colima 容器 `sonarqube` `Up 19 hours (healthy)`；`curl http://127.0.0.1:9000/api/system/status` 与 `http://100.108.64.126:9000/...` 均为 `"status":"UP"`（26.3.0.120487）。
  - `umacbook-pro`：`curl http://mac-mini:9000/api/system/status` HTTP 200（~0.68s）；`nc 100.108.64.126:9000` 成功。
  - `mas-go-dev`：同上 HTTP 200（~19ms），MagicDNS `100.108.64.126 mac-mini.taila93443.ts.net`。排除 2026-08-02 / 08-13 那类「Sonar 挂了」或 mas-go-dev DNS 问题。
  - `lemon-imac`：MagicDNS 正常（`mac-mini` → `100.108.64.126`）；`tailscale ping mac-mini` 通；公网 `https://github.com` HTTP 200。但对任意 tailnet `100.x` TCP（`mac-mini:9000` / `:22`、`mas-go-dev:22`、`umacbook-pro:22`）一律 errno 49：
    ```
    Can't assign requested address
    ```
    `tailscale debug dial-types 100.108.64.126 9000`：BareDial / UserDial / PeerDial 同错，SystemDial i/o timeout。`tailscale ip -6` 为 `fd7a:115c:a1e0::33a:4d49`，挂在 `utun4` 上。
  - 同型失败：前夜 schedule run [`32288060872`](https://github.com/cypressoai/iCare-backend/actions/runs/32288060872) 也在 `lemon-imac-2` 报完全相同的 `Can't assign requested address`。成功样例 run `32322183019` 落在 `mac-mini-sonar-2`（本机回环，不走 lemon 出站）。
  - 结论：**基础设施 / lemon-imac Tailscale 出站 TCP 故障**（errno 49），不是 PR 代码、不是 Sonar 进程、也不是 `lemon-imac-1` 单 slot。时间上紧挨 2026-08-19 17:13 把 GUI Standalone 换成 brew `tailscaled` LaunchDaemon；当时只验了入站 `ssh lemon-imac` 与 ping，没验本机访问 `mac-mini:9000`。
- 未做（需确认后再做）：
  - 重启 `system/homebrew.mxcl.tailscale` 或 `tailscale debug restun` / `rebind`
  - 重跑该 Job（恢复连通后可 re-run；若落到 mac-mini / umac / mas-go-dev 也可先绿）
- 备注：附近 run `32324180890` / `32325359725` 的红叉是 workflow 步骤 `Block while draft` exit 1，与本连通性问题不同。

## 2026-08-19 17:13 CST - Tailscale 已换成 brew LaunchDaemon，IP 仍是 100.81.246.93

- 服务器：`lemon-imac`
- 操作人：`konghai`（卸 GUI、登录、把节点 IPv4 改回原地址）、`Grok`（预装 formula、写启动脚本、核对）
- 原因：GUI Standalone 绑登录会话；注销或不登 `for-konghai` 桌面时隧道会断。改成和 mac-mini 一样的开源 `tailscaled` LaunchDaemon。
- 影响：
  - `/Applications/Tailscale.app` 已卸，无 `io.tailscale.ipn.macsys` 残留
  - `system/homebrew.mxcl.tailscale` running（pid 5016，`tailscaled` 1.102.2），`WantRunning=true`，`--hostname=lemon-imac`，`--operator=for-konghai`，`CorpDNS=true`
  - 节点 IPv4 **仍是** `100.81.246.93`（用户在管理后台改回），MagicDNS `lemon-imac.taila93443.ts.net` 指向同一地址
  - 本机 `~/.ssh/config` 的 `Host lemon-imac` 不用改
- 备份：无（新登录，未搬 GUI 状态）。旧 GUI 已卸。
- 回滚：`sudo brew services stop tailscale` 后重装 GUI Standalone；不要两套同时跑。
- 验证：
  - `ssh lemon-imac` → `SSH_OK`；`ping 100.81.246.93` / `ping lemon-imac` 通
  - `tailscale status` 本机见 `lemon-imac` active，直连
  - 重启后 runner LaunchDaemon 已自起：`lemon-imac-1/2` Listener 16:49 起在听
- 备注：`brew services info` 非 root 会显示 Running false，以 `launchctl print system/homebrew.mxcl.tailscale` 为准。FileVault 冷启动仍要人在登录窗解锁。

## 2026-08-19 16:50 CST - 预装 Homebrew tailscale，未启动、未卸 GUI

- 服务器：`lemon-imac`
- 操作人：`Grok`
- 原因：用户已用 ToDesk 连上，准备把 Tailscale 从 GUI Standalone 换成 LaunchDaemon。GUI 一卸，本机 `ssh lemon-imac`（写死 `100.81.246.93`）会断；iMac LAN 是 `10.0.0.129`，操作机在 `192.168.2.109`，直连 ping 不通，没有 mac-mini 那种 `ProxyJump pve` 兜底。必须先把 formula 装好，再让用户在 ToDesk 里卸 GUI、启 daemon。
- 影响：只 `brew install tailscale` 1.102.2。**未** `brew services start`，**未**卸 `/Applications/Tailscale.app`，隧道仍是 macsys 1.98.9 / `100.81.246.93`。
- 备份：无（新装 formula，与 GUI 并存但没启动）。
- 回滚：`brew uninstall tailscale`。不要在 GUI 还在时 `brew services start`。
- 验证：`brew services info` = Running/Loaded false；无 `tailscaled` 进程；`/usr/local/bin/tailscale ip -4` 仍 `100.81.246.93`。
- 下一步（用户在 ToDesk 里做）：拖走 Tailscale.app → 确认卸系统扩展 → 清空废纸篓 → 按提示重启 → 再连 ToDesk → `sudo ~/gha/scripts/start-lemon-imac-tailscaled.sh` → 浏览器登录 → 把新 `100.x` 发回。

## 2026-08-19 16:36 CST - 重启 ToDesk，供本机连上后改 Tailscale Daemon

- 服务器：`lemon-imac`
- 操作人：`Grok`（写脚本 / 核对）、`konghai`（本机 `sudo`）
- 原因：用户要先用 ToDesk 连上 iMac 图形界面，再把 Tailscale 装成 LaunchDaemon。当时 `ToDesk_Service` 16:28 自己被 KeepAlive 拉过一次（`last exit code = 5`），但 `zhangli` 的 GUI 从 08-17 07:02 一直挂着。
- 影响：只重启 ToDesk。未改 Tailscale、未动 runner、未 reboot。
- 备份：无配置改动。脚本落在 `~/gha/scripts/restart-todesk.sh`。
- 回滚：不必；ToDesk 本就常驻。若要再拉：`sudo ~/gha/scripts/restart-todesk.sh`
- 变更时序：
  1. `killall` / `killall -9` ToDesk 相关进程
  2. `launchctl kickstart -k system/com.youqu.todesk.service`
  3. `launchctl asuser $(id -u zhangli)` 以 `zhangli` 再 `open -a ToDesk --args -AutoRun YES`
- 验证：
  - `ToDesk_Service` pid 56340、`zhangli` GUI pid 56346，均 16:36:40 新起
  - 本机监听 `127.0.0.1:35600`（Service）/ `37600`（zhangli GUI）
  - 16:38 已见 `ToDesk_Session --myid=126978008 --isVideoSession=true`（设备码与 2026-07-21 记录一致）
  - runner 未受影响：`lemon-imac-1/2` Listener 仍为 37317 / 37320
- 未做：Tailscale 仍是 GUI Standalone 系统扩展，等用户连上后再改 Daemon

## 2026-08-19 16:09 CST - runner 从 LaunchAgent 改为 LaunchDaemon（注销后仍在线）

- 服务器：`lemon-imac`
- 操作人：`Grok`（写脚本 / 挪走 Agent / 核对）、`konghai`（本机 `sudo` 安装脚本）
- 原因：`for-konghai` 没有图形会话时 LaunchAgent 不起；控制台长期是 `zhangli`，两个 slot 自 2026-08-09 起 offline。需要和 mac-mini 一样，注销桌面后 runner 仍接 job。
- 影响：
  - `lemon-imac-1/2` 现为 `system/actions.runner.cypressoai.lemon-imac-N`，以 `for-konghai` 跑 `runsvc.sh`（`KeepAlive` + `SessionCreate` + `HOME` / `GOCACHE` 等写进 plist）
  - 日/周维护一并改成 Daemon：`system/com.cypressoai.gha-runner-maintenance{,-weekly}`（03:25 / 周日 04:45）。Agent 时代 `for-konghai` 未登录就不会跑，盘会再涨
  - 旧 Agent plist 停在 `~/Library/LaunchAgents.disabled-20260819/`
- 选型：官方 `./svc.sh install` 只会装 LaunchAgent，装完登录后会和 Daemon 双开。安装脚本：`~/gha/scripts/install-lemon-imac-runner-daemons.sh`（仓库副本 `scripts/install-lemon-imac-runner-daemons.sh`）
- 备份：上述 disabled 目录里的原 plist
- 回滚方式：`sudo launchctl bootout system/actions.runner.cypressoai.lemon-imac-{1,2}` 并删对应 `/Library/LaunchDaemons` plist；需要时把 disabled 目录里的 Agent 移回 `~/Library/LaunchAgents`。不要再 `./svc.sh install`
- 变更时序：
  1. 确认两 slot 已 Stopped、无 `Runner.Worker`（GitHub offline 自 08-09）
  2. 把四个 LaunchAgent plist 挪到 `~/Library/LaunchAgents.disabled-20260819/`
  3. 用户 `sudo` 跑安装脚本：写 `/Library/LaunchDaemons`、`bootstrap system`、`kickstart` 两个 runner
  4. 核对 Listener + GitHub online
- 验证：
  - 控制台用户仍是 `zhangli`；`for-konghai` 只有 SSH，无 Aqua 会话
  - `launchctl print system/actions.runner.cypressoai.lemon-imac-{1,2}`：`type = LaunchDaemon`、`state = running`、`username = for-konghai`
  - 两 slot 日志 `Connected to GitHub` → **`Listening for Jobs`**（runner 2.336.0）
  - GitHub：`lemon-imac-1` / `lemon-imac-2` 均为 **online / busy=false**
  - 维护两个 job `state = not running`、`runs = 0`（日历调度，到点才跑），`plutil -lint` 四个 plist OK
- 备注：FileVault 冷启动仍要有人在登录窗解锁磁盘；这和 Daemon 无关。**不要**再跑 `./svc.sh install` / `start`
- 关联：`docs/runbooks/lemon-imac-runner-start-stop.md`；mac-mini 同做法见 `docs/runbooks/mac-mini-runner-start-stop.md` 与 2026-08-15 时间线

## 2026-08-08 22:25 CST - 统一 slot 1 workFolder 为 `~/gha/li1`（含维护 plist 同步）

- 服务器：`lemon-imac`
- 操作人：`Claude`
- 原因：slot 1 的 workFolder 为 `~/gha/li`、slot 2 为 `~/gha/li2`，命名不对称，易让后续脚本与文档按规律推测出错路径。用户确认 runner 空闲后要求统一。
- 影响：
  - `~/gha/li` → `~/gha/li1`（用 `mv` 迁移，保留 4.0G 既有 checkout / `_tool` 缓存，未删除重建）
  - `~/actions-runner/lemon-imac-1/.runner` 的 `workFolder` 改为 `/Users/for-konghai/gha/li1`
  - **两个维护 LaunchAgent plist 的 `WORK_DIRS` 同步改为 `li1 li2`**（`com.cypressoai.gha-runner-maintenance{,-weekly}` 第 15 行硬编码了 work 路径；只改 runner 不改 plist，每日/每周清理会静默失效并导致磁盘涨回，此机历史上已因盘满出过 CYP-1547）
  - slot 2 全程在线，CI 未断供；仅 slot 1 停机约 1 分钟
- 备份：
  - `~/actions-runner/lemon-imac-1/.runner.bak.20260808`
  - `~/Library/LaunchAgents/com.cypressoai.gha-runner-maintenance.plist.bak.20260808`
  - `~/Library/LaunchAgents/com.cypressoai.gha-runner-maintenance-weekly.plist.bak.20260808`
- 回滚：`mv ~/gha/li1 ~/gha/li` → 还原上述三个 `.bak.20260808` → `launchctl bootout` + `bootstrap` 重载 slot 1 与两个维护 agent（约 1 分钟，全程可逆）
- 变更时序：
  1. 确认无 `Runner.Worker`（仅两个 Listener 在线）→ 空闲
  2. `launchctl bootout` 停 slot 1（slot 2 保持在线）
  3. 备份 `.runner` + 两个 plist
  4. `mv ~/gha/li ~/gha/li1`
  5. `sed` 改 `.runner`（匹配 `gha/li"` 带尾引号，避免误伤 `li2`）
  6. `sed` 改两个 plist（匹配 `gha/li ` 带尾空格）
  7. `launchctl bootstrap` 重载 slot 1 + 两个维护 agent
- 验证：
  - slot 1 日志 `Session created` → **`Listening for Jobs`**（runner 2.336.0），非仅进程存活
  - `launchctl list` 四个服务退出码均 0；slot 2 PID 未变（97536），未受影响
  - `~/gha` 下只剩 `li1`/`li2`/`cache`/`scripts`，旧 `~/gha/li` 确认不存在；体积 4.0G / 4.1G 完整保留
  - `plutil -lint` 两个 plist OK
  - 以 plist 实际参数跑 `DRY_RUN=1` 维护脚本：正确识别 `li1` 与 `li2` 并列出待清理项，确认清理链路未断
- 备注：`_PipelineMapping` 仍记旧路径，首个 job 可能重新 checkout 一次，属正常自愈。`docs/runbooks/ci-runner-pools.md` 只记缓存路径、不含 workFolder，无需改动。
- 关联：`AGENTS.md` 目录约定已更新并补充「改 workFolder 必须同步改维护 plist」的告警

## 2026-08-08 CST - 只读核实 runner workFolder 与缓存路径（补全仓库清单）

- 服务器：`lemon-imac`
- 操作人：`Claude`
- 原因：对齐 `README.md` 与 `AGENTS.md` 服务器清单时发现 `lemon-imac` 缺目录约定；`umacbook-pro` 的 workFolder 为 `~/gha/u{1,2}`，需上机确认 `lemon-imac` 是否同构，避免凭推测写进约定文档。
- 影响：只读（`cat .runner` / `cat .env` / `ls`）；未改配置、未重启 runner、未删文件。
- 核实结果：
  - workFolder **命名不对称**：slot 1 为 `~/gha/li`、slot 2 为 `~/gha/li2`（不是 `li1`/`li2`，也不同于 `umacbook-pro` 的 `u1`/`u2`）
  - agentName `lemon-imac-1`（agentId 32）/ `lemon-imac-2`（agentId 31）；org `cypressoai`，均为 useV2Flow
  - `.env` 与 runbook 记载一致：per-slot `GOCACHE=~/actions-runner/lemon-imac-{1,2}/cache/go-build`，共享 `GOMODCACHE=~/go/pkg/mod`、`PNPM_STORE_PATH=~/gha/cache/pnpm-store`
  - LaunchAgent 四个齐全：`actions.runner.cypressoai.lemon-imac-{1,2}` + `com.cypressoai.gha-runner-maintenance{,-weekly}`
  - 维护脚本在 `~/gha/scripts/`（`gha-runner-maintenance.sh`、`prune-gocache.sh`）
- 备份：无（只读）。
- 回滚：无变更。
- 关联：`AGENTS.md` 已补 `lemon-imac` 目录约定；`docs/runbooks/ci-runner-pools.md`

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`lemon-imac`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN（误报名碰撞）。gha work 下 motion-dom 的 setup.mjs 与 regenerate-unicode-properties 的 Math_Symbol.js；哈希非恶意（c2f397ef… / b66c1e0b…）；preinstall=0。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-08-03 15:45 CST - CI 池加固：PNPM store + launchd 维护 + 清盘 + 双 slot 重启

- 服务器：`lemon-imac`（8 核 / 8GB，Data **228G**）
- 操作人：`Grok`（iCare 自托管 runner 运维加固任务）
- 原因：盘曾 **86% / Avail ~26–28G**；`_temp` 峰值约 8G+2G；缺定时清理与本机 pnpm store。
- 影响：
  - 双 slot `.env`：`PNPM_STORE_PATH=~/gha/cache/pnpm-store` + 既有 GOCACHE/GOMODCACHE
  - 脚本：`~/gha/scripts/{gha-runner-maintenance.sh,prune-gocache.sh}`
  - **crontab 被 TCC 拒绝**（`Operation not permitted`）→ 改用 LaunchAgent：
    - `com.cypressoai.gha-runner-maintenance` 每日 03:25
    - `com.cypressoai.gha-runner-maintenance-weekly` 周日 04:45
  - 即时清理：work `li` 4.1G→1.9G、`li2` 3.7G→1.3G；go-build 5.3G→2.4G / 6.9G→3.6G（MAX_GB=12）
  - 双 slot `svc.sh` 重启加载 `.env`
- 备份：`~/actions-runner/lemon-imac-N/.env.bak.*`
- 回滚：恢复 `.env.bak` + 重启；`launchctl bootout gui/$(id -u)/com.cypressoai.gha-runner-maintenance{,-weekly}`
- 验证：Data **79%→74% / Avail 40G→50G**；两 Listener Started；pnpm-store 目录已建（待 job 回填）
- 风险：8GB 机双 slot 并发仍可能顶满内存/磁盘；建议高峰只信 mac-mini 重活
- 关联：`docs/runbooks/ci-runner-pools.md`

## 2026-07-23 19:02 CST - A+B：清空 go-build + 恢复 runner（CYP-1547）

- 服务器：`lemon-imac`
- 操作人：`Grok`
- 原因：coverage 持久 GOCACHE 盘满（slot 42G+31G + orphan 14G）；A+B 全池治理，修剪策略改为 **2 天**。
- 影响：
  - 删除 orphan `~/Library/Caches/go-build`（~14G）
  - 清空 per-slot `~/actions-runner/lemon-imac-{1,2}/cache/go-build`（~73G；文件 mtime 均 ≤2 天，无法仅靠 2 天年龄修剪，按 >20GB 门槛整目录清空）
  - `df` Avail **6.2Gi → 93Gi**
  - `./svc.sh start` 两 slot → **Started**
- 备份：无（cache 可再生）
- 回滚：无需；cache 会由后续 lint/非 coverage job 回填
- 关联：Jira **CYP-1547**；iCare-backend PR coverage job-local `GOCACHE=${{ runner.temp }}/go-build-cover`；runbook `docs/runbooks/ci-runner-pools.md`；`scripts/prune-gocache.sh`
- 验证：两 slot `./svc.sh status` = Started；go-build 目录 0B

## 2026-07-23 18:24 CST - 清空 gha workFolder + go-build 膨胀根因

- 服务器：`lemon-imac`
- 操作人：`Grok`
- 原因：用户要求先清 `~/gha/li` + `~/gha/li2` 腾约 7G，并研究 GOCACHE 为何涨到数十 GB。
- 影响：
  - 已清空 workFolder 内容（保留空目录 `~/gha/li`、`~/gha/li2`）；下次 job 会重新 checkout / 装 `_tool`。
  - **未**动 go-build / runner service（runner 仍 Stopped）。
- 备份：无（workspace 可再生）。
- 回滚：无需；job 会重建 workFolder。
- 变更时序：
  1. 清理前：`li` 4.0G + `li2` 3.0G（checkout/`node_modules` + 各 ~731M `_tool`）。
  2. `find ... -mindepth 1 -maxdepth 1 | rm -rf` 清空两目录。
  3. 清理后：两目录 **0B**；`df` Avail **113Mi → 6.3Gi**（约 **+6.2G**，APFS 与原先 du 量级一致）。
- go-build 膨胀结论（只读）：
  | 路径 | 体积 | 文件数 | 创建时间 | 备注 |
  | --- | --- | --- | --- | --- |
  | `~/actions-runner/lemon-imac-1/cache/go-build` | **42G** | ~156k | 2026-07-20 19:32（空目录起热） | per-slot `GOCACHE` |
  | `~/actions-runner/lemon-imac-2/cache/go-build` | **31G** | ~137k | 同上 | per-slot |
  | `~/Library/Caches/go-build` | **14G** | ~85k | 2026-07-20 13:50 | 迁 per-slot 前默认路径，**已 orphan**（采样 mtime 全是 7/20） |
  1. **增速极快**：per-slot 落地仅约 **71 小时**，slot1 ≈ **14 GB/天**、slot2 ≈ **10.5 GB/天**；两 slot 合计 ~73G，已远超 runbook 单 slot **>20GB** 修剪门槛，且 **无人执行过** `go clean -cache`。
  2. **Go 自带淘汰几乎不起作用**：两 slot 缓存 mtime 全在 **0–3 天** 内（`>3d` / `>7d` = 0）；Go 默认约 **5 天未用才 trim**，高频 backend-ci 持续写入/触摸条目，短窗口内不会自动瘦身。
  3. **覆盖率编译是放大器**：Worker 日志反复出现  
     `go test ./test/... ./internal/... -coverprofile=coverage.out -covermode=atomic -coverpkg=./cmd/...,./internal/...`  
     全包 `atomic` 插桩会为覆盖率变体单独建 cache key；`*-d` 对象平均约 **1.1MB**、峰值 **6–12MB**，一次全量 Sonar/coverage job 即可写入大量大对象。
  4. **双 slot 隔离是设计成本**：为防 CYP-322 竞态，两 slot `GOCACHE` 互不共享 → 同样 workload **磁盘近似 ×2**（共享的是 `GOMODCACHE=~/go/pkg/mod` ~1.4G，不是 go-build）。
  5. **14G orphan 未清**：2026-07-20 切 per-slot 时故意未删 `~/Library/Caches/go-build`，至今仍占盘。
- 验证：`du -sh ~/gha/li ~/gha/li2` = 0B；`df` Avail 6.3Gi；runner 仍 Stopped。
- 后续可选（需确认后再做）：
  1. 删 orphan：`rm -rf ~/Library/Caches/go-build`（+14G，无副作用）。
  2. 修剪 slot GOCACHE：`GOCACHE=... go clean -cache` 或 `rm -rf .../cache/go-build/*`（+73G；冷启动后首几次 backend job 变慢）。
  3. 运维：按 runbook 定期检查单 slot >20GB；或 job-local `GOCACHE=${{ runner.temp }}/go-build` 让覆盖率产物随 temp 回收（mas-go-dev 已讨论过同类方案）。

## 2026-07-23 18:19 CST - 停止双 slot runner + 磁盘满排查

- 服务器：`lemon-imac`
- 操作人：`Grok`
- 原因：磁盘满；用户要求停止本机 runner 并排查占用。
- 影响：`lemon-imac-1` / `lemon-imac-2` **Stopped**，org `cypressoai` 上这两台 self-hosted 不再接 job；其它 runner 池不受影响。
- 备份：无配置改动；仅 `./svc.sh stop`。
- 回滚方式：在 `for-konghai` 会话下分别执行：
  - `cd ~/actions-runner/lemon-imac-1 && ./svc.sh start`
  - `cd ~/actions-runner/lemon-imac-2 && ./svc.sh start`
  （启动前建议先腾出磁盘，否则 job 易写盘失败。）
- 变更时序：
  1. `df`：整盘 **228Gi，Avail ≈116Mi，Capacity 100%**；Data 卷 `diskutil` Capacity Consumed **≈218.7GB**。
  2. `./svc.sh stop` 两 slot → 状态均为 **Stopped**；无 `Runner.Listener` 残留。
  3. 可见占用（`for-konghai` 可读部分，Users 合计约 **105G**，其中 for-konghai **≈100G**）：
     | 路径 | 约占用 | 说明 |
     | --- | --- | --- |
     | `~/actions-runner/lemon-imac-1/cache/go-build` | **42G** | `.env` 中 `GOCACHE=.../cache/go-build` |
     | `~/actions-runner/lemon-imac-2/cache/go-build` | **31G** | 同上，slot2 |
     | `~/Library/Caches/go-build` | **14G** | 默认/非 slot GOCACHE 残留 |
     | `~/gha/li` + `~/gha/li2` | **4G + 3G** | workFolder（checkout / node_modules 等） |
     | `~/go/pkg`、`setup-pnpm`、`.sonar`、`.npm` | 合计约 **3G** | mod / 工具链 |
     | `/Applications` | **23G** | 本机 GUI 软件（非 runner） |
     | `/Library` + `/private/var` + Data/System | 约 **18G** | 系统与开发组件 |
  4. **Go build cache 合计约 87G**，是 runner 账号下最主要可回收空间。
  5. `zhangli` 的 Desktop/Documents/Downloads/Library 等对 `for-konghai` 为 **Operation not permitted**（TCC），`du` 只见 **≈4.9G** 可读部分；Data 卷仍有约数十 GB 无法从当前账号归因（可能含 `zhangli` 隐私目录或系统元数据 `.Spotlight-V100` / `.fseventsd` 等）。
- 验证：两 slot `./svc.sh status` = Stopped；`df` 仍 100%（本次未清缓存）。
- 建议清理（**未执行**，需用户确认后再做）：
  1. 删 slot GOCACHE：`rm -rf ~/actions-runner/lemon-imac-{1,2}/cache/go-build/*`（可回收 **~73G**）
  2. 删默认 go-build：`rm -rf ~/Library/Caches/go-build`（**~14G**）
  3. 可选：清空 workFolder `~/gha/li` / `~/gha/li2` 下残留 workspace（**~7G**）
  4. 若仍不足：用 `zhangli` 登录或授予 Full Disk Access 后再扫个人库

## 2026-07-21 12:08 CST - 只读：隐私排除后 Frontend Tests 运行中（mds≈0）

- 服务器：`lemon-imac`
- 操作人：`Grok`（只读）
- 原因：用户重发 job 后对照 Spotlight 排除 `/Users/for-konghai/` 的效果。
- 影响：无变更。
- 当时状态：
  - 双 slot busy：`Frontend Tests 4/4`（li）+ `2/4`（li2）；`vitest run --maxWorkers=2`。
  - load ~3.6（8 核）；**CPU 前列全是 node/vitest**。
  - **sums：node≈445%，mds 族≈0，fseventsd≈0**（对比排除前 mds_stores 可占数十～百 %）。
  - npm ci 热路径约 **10s** 量级（Install→Run Tests 间隔）。
- 验证结果：隐私排除后 CI 阶段 **Spotlight 不再与 Vitest 争核**，与 mac-mini 修好后表现一致。

## 2026-07-21 12:06 CST - 重启后验证：runner 正常 + Spotlight 已排除 for-konghai

- 服务器：`lemon-imac`
- 操作人：`Grok`（只读验证）；重启与 Spotlight GUI 由用户完成
- 原因：用户本机 `sudo reboot` 后 ToDesk 恢复，已将 `/Users/for-konghai/` 加入 Spotlight 搜索隐私并退出 ToDesk GUI；发 job 前确认 runner。
- 影响：无代理侧变更。
- 验证结果：
  - uptime ~**7 min**（重启成功）；console 用户 `for-konghai`。
  - runner：`lemon-imac-1/2` 本机 `./svc.sh status` = **Started**，Listener 在跑；GitHub API 均为 **online / busy=false**。
  - labels 仍含 `frontend-tests-ci` / `frontend-quality-ci` / `backend-ci` / `lemon-imac` 等。
  - Spotlight：整卷仍 **Indexing enabled**（符合「不整卷关闭」）；`mdfind -onlyin ~/gha` / `~/actions-runner` 对关键名 **无结果**（隐私排除生效迹象）。
  - 重启后短暂见 `fseventsd`/`mds_stores` 偏高，属其它路径/系统重建索引常见现象；CI 路径应已不进 for-konghai 家目录索引。
  - ToDesk_Service 仍可能在后台（系统服务）；用户已退 GUI 省资源。
- 备注：`mac-mini-sonar-1..4` 仍为用户先前要求的 **offline**；本轮 job 预期落 lemon + umac。

## 2026-07-21 11:58 CST - 用户确认重启，但无 sudo 未能执行 reboot

- 服务器：`lemon-imac`
- 操作人：`Grok`（用户明确要求「直接重启」）
- 原因：屏幕共享提示密码错误（用户确认密码正确）；ToDesk 不可用；需重启恢复远程。
- 影响：尝试 `sudo -n /sbin/reboot` 与 `/sbin/reboot` 均失败（password required / Operation not permitted）。**机器未重启**。
- 回滚：无。
- 后续：需用户在可交互 SSH 下执行 `sudo reboot`，或配置临时 NOPASSWD 后再由代理执行。

## 2026-07-21 11:48 CST - 无 sudo 下 kickstart 屏幕共享；ToDesk 仍不可用

- 服务器：`lemon-imac`
- 操作人：`Grok`
- 原因：用户 ToDesk / 屏幕共享均进不去，考虑重启；先找其它办法。
- 影响：
  - 确认 `com.apple.screensharing` 本就 running；曾有来自 `100.92.181.15` 的 5900 ESTABLISHED。
  - `launchctl kickstart -k system/com.apple.screensharing` **成功**（screensharingd 新 pid，runs=3）。
  - `launchctl kickstart -k system/com.youqu.todesk.service` **仍 Operation not permitted**；无 `myid` Session。
  - 无 passwordless sudo；`asuser` + System Events restart 失败；**未能执行 reboot**。
  - 本机信息：LAN `10.0.0.129`，ComputerName「张李的iMac」，LocalHostName `zhanglideiMac`；人类账号 `zhangli` / `for-konghai`。
- 回滚：无。
- 验证：screensharingd 运行中；ToDesk 仍无可用设备码。

## 2026-07-21 11:31 CST - 尝试重启 ToDesk（无 sudo，未完整成功）

- 服务器：`lemon-imac`
- 操作人：`Grok`
- 原因：用户本机 `ssh lemon-imac` 连不上，需 ToDesk 远程进 GUI；要求重启 ToDesk。
- 影响：
  - 代理侧 SSH（Tailscale `100.81.246.93` / `for-konghai`）**可连通**。
  - `for-konghai` **无 passwordless sudo**，无法 `kill` `zhangli`/`root` 的 ToDesk 进程，也无法 `launchctl kickstart system/com.youqu.todesk.service`。
  - 已 `open -a ToDesk` 以 `for-konghai` 拉起 GUI（pid 曾见 70863），**未出现**带 `myid=` 的 Session。
  - 仍在跑：`zhangli` 的 `ToDesk -AutoRun YES`、root 的 `ToDesk_Service`（launchd `com.youqu.todesk.service`，state=running，曾见 `immediate reason=inefficient`）。
- 回滚：无破坏性变更；多一个 `for-konghai` 的 ToDesk GUI 进程可忽略或 GUI 里退出。
- 验证：进程与本机 127.0.0.1:35600/37600/37601 LISTEN 存在；**无可用设备码 Session**。
- 后续可选（需用户确认其一）：本机 GUI 以 admin 重启 ToDesk；提供 sudo；或 **reboot** lemon-imac（会影响 zhangli 会话与 lemon runner）。

## 2026-07-21 11:24 CST - 拉起 ToDesk 供 GUI 配置 Spotlight 隐私

- 服务器：`lemon-imac`
- 操作人：`Grok`
- 原因：共享机不能整卷关 Spotlight；用户将在 GUI 把 `/Users/for-konghai/` 加入搜索隐私（仅 runner 账号家目录）。需 ToDesk 远程操作。
- 影响：`open -a ToDesk`；控制台用户为 `zhangli`，ToDesk GUI 以 `zhangli` 运行为主。采样时 Session `myid=126978008`。
- 回滚：无必要；ToDesk 本就常驻服务。
- 验证：ToDesk_Service + ToDesk GUI/Session 进程存在。

## 2026-07-21 11:01 CST - 只读：双 slot Frontend Tests 运行中 Spotlight 争用

- 服务器：`lemon-imac`
- 操作人：`Grok`（只读；mac-mini runner 仍 offline）
- 原因：用户重跑 job 后确认 lemon 上 mds/`fseventsd` 与 CI 争用情况。
- 影响：无变更。
- 当时状态：
  - **双 slot busy**：`lemon-imac-1` → Frontend Tests **3/4**（`~/gha/li`）；`lemon-imac-2` → **4/4**（`~/gha/li2`）。
  - 均为 `vitest run --maxWorkers=2`；load **~22**（8 核 / 8GB）。
  - **npm ci** 各约 **15.3–15.5s**（热 prefer-offline）。
  - **Spotlight 仍 Indexing enabled**；采样：`mds_stores` **~72–86%**、`mds` **~11–13%**、多个 mdworker；**fseventsd ~0.1%**。
  - CPU 合计约 node **~390%** vs mds 族 **~60%+**（mds_stores 瞬时更高时进 top）。
- 验证结果：与 mac-mini 改前同类——**瓶颈是 mds 索引，不是 fseventsd**；8GB 双 shard 时索引与 Vitest 明显抢核。
- 回滚方式：无。

## 2026-07-21 10:55 CST - 只读：Spotlight 仍开启 + mds 占 CPU（对照 mac-mini）

- 服务器：`lemon-imac`
- 操作人：`Grok`（只读基线；mac-mini runner 已临时停止以便分流 CI）
- 原因：mac-mini 上已确认关 Spotlight 后 mds/`fseventsd` 不再成问题；核对 lemon 是否同样有索引开销。
- 影响：无变更。
- 做了什么：`mdutil -s`、进程采样、load / 内存 / 磁盘、runner 状态。
- 当时状态：
  - **Spotlight：`/` 与 Data 均为 Indexing enabled**（与 mac-mini 已 disabled 相反）。
  - load ~**18–22**（8 核 / 8GB）；top 见 `mds_stores` **~108%**、`mds` 数 %、多个 `mdworker_shared` 曾合计数十 %。
  - `fseventsd` 当时不高（~1% 级），主矛盾更像 **mds 索引**。
  - runner：`lemon-imac-1/2` Listener 在线、采样时无 Worker；workdir `~/gha/li` `~/gha/li2`；`~/.npm` ~140M。
  - Data 卷约 164/228G 已用（81%）。
- 验证结果：**存在与 mac-mini 改前同类的 Spotlight 问题**；若用户确认，可按 mac-mini 做法关索引/加隐私排除（**未擅自改**）。
- 回滚方式：无。

## 2026-07-20 20:01 CST - U5 npm 预热：frontend-mas lock 可 offline 装齐

- 服务器：`lemon-imac`
- 操作人：`Grok`
- 原因：缓存基线 R6 / G4；此前 `prefer-offline` 预热后体积仍 ~188M，需证明 cache **完整**。
- 做了什么：
  - `npm cache clean --force` 后对 develop 版 `package-lock` 全量 `npm ci --prefer-online`（899 packages）。
  - 实测 `~/.npm` ≈ **143M**、`_cacache` content files ≈ **866**（npm 11 对该 lock 的完整体积，非 GB 级）。
  - 验证：`npm ci --prefer-offline --offline` **PASS**（9s，无 registry）。
- 说明：mac-mini `~/.npm` 9.5G 为历史多项目堆积；单 lock 达标以 **offline 可装齐** 为准（计划 R6 已修订）。
- 参考：`docs/plans/2026-07-20-001-ops-ci-runner-cache-baseline-plan.md`

## 2026-07-20 19:48 CST - CI 缓存基线：per-slot GOCACHE + 共享 GOMODCACHE

- 服务器：`lemon-imac`
- 操作人：`Grok`（ce-work U2）
- 原因：双 slot 原共享默认 `~/Library/Caches/go-build`，接 `backend-ci` 并发有 race 风险。
- 影响：
  - `.env` 增加 `GOCACHE=~/actions-runner/lemon-imac-N/cache/go-build`（空目录起热）、`GOMODCACHE=~/go/pkg/mod`。
  - idle 后重启 `lemon-imac-1/2` service。
  - 旧 `~/Library/Caches/go-build` 未强制删除（orphan，可后清）。
- 备份：`~/actions-runner/lemon-imac-*/.env.bak.*`
- 回滚：还原 `.env.bak` 后 `./svc.sh stop && start`。
- 验证：两 slot GOCACHE 路径不同、GOMODCACHE 相同。
- 参考：`docs/plans/2026-07-20-001-ops-ci-runner-cache-baseline-plan.md`

## 2026-07-20 18:55 CST - backend-ci 基线：安装 gnupg + 暴露 Homebrew 到 runner PATH

- 服务器：`lemon-imac`
- 操作人：`Grok`
- 原因：贴 `backend-ci` 后 Sonar Scanner 默认 GPG 校验失败（`GPG is not available`）。业务仓一度用 `skipSignatureVerification: true` 绕过，应在 runner 侧根治。
- 影响：本机安装完整 `gnupg`（Homebrew 2.5.21，含 `dirmngr`）；`lemon-imac-1/2` 的 `.path` 前置 `/opt/homebrew/bin` 并重启 service。
- 备份：
  - `~/actions-runner/lemon-imac-1/.path.bak.<timestamp>`
  - `~/actions-runner/lemon-imac-2/.path.bak.<timestamp>`
- 回滚方式：还原对应 `.path.bak.*` 后 `./svc.sh stop && ./svc.sh start`；可选 `brew uninstall gnupg`（一般无需）。
- 变更时序：
  1. `NONINTERACTIVE=1 brew install gnupg`
  2. 两 slot `.path` 改为 `/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`
  3. `lemon-imac-1/2` 均 `./svc.sh stop && ./svc.sh start`（当时 idle）
- 验证：
  - `PATH=$(cat .path) command -v gpg` → `/opt/homebrew/bin/gpg`
  - `gpg --version` → `gpg (GnuPG) 2.5.21`；`dirmngr` 同目录可用
  - LaunchAgent 两 slot Started
- 参考：`docs/runbooks/ci-runner-pools.md` 上线 checklist

## 2026-07-20 13:45 CST - CI 池：frontend-quality-ci + backend-ci

- 服务器：`lemon-imac`
- 操作人：`Grok`
- 原因：分担 PR 质量与后端 Lint/Sonar；8GB 机不进 Coverage / 完整 branch Sonar。
- 影响：`lemon-imac-1/2`（id 32/31）追加 `frontend-quality-ci`、`backend-ci`；保留 `frontend-tests-ci`。
- 备注：本机 login 可能无 go/node；job 内 setup-go / setup-node 安装。
- 回滚：DELETE 对应 labels。
- 参考：`docs/runbooks/ci-runner-pools.md`



## 2026-07-20 00:08 CST - 验证：for-konghai 自动登录已开启

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Grok`（用户已在 GUI 完成设置，本侧只读复核）
- 原因：用户希望重启后 runner 自动上线，已在系统设置里为 `for-konghai` 打开自动登录，要求检查是否生效。
- 影响：本次**仅只读验证**，未重启机器、未改 runner / LaunchAgent。
- 验证结果（均通过）：
  - `sysadminctl -autologin status` → **`Automatic login user: for-konghai`**
  - `defaults read ... autoLoginUser` → **`for-konghai`**
  - `/etc/kcpassword` 存在（`root:wheel` `600`，mtime `2026-07-20 00:07`）—— macOS 自动登录凭据文件已落盘
  - **FileVault is Off**（与自动登录兼容；若以后打开 FileVault，自动登录会被系统关掉）
  - 当前 console 会话：`for-konghai` 自 `2026-07-19 23:45` 起仍在线
  - LaunchAgent：`lemon-imac-1` / `lemon-imac-2` 均在 `launchctl list`；两个 `Runner.Listener` 在跑
- 预期行为（下次 reboot / 系统更新后）：
  1. 开机后自动以 `for-konghai` 进入桌面（无需人工点登录窗）
  2. 用户级 LaunchAgent `RunAtLoad` 拉起两个 runner
  3. GitHub 侧应变为 `status=online`，可接 `frontend-tests-ci` job
- 未做：故意重启验证（会影响正在跑的 CI / 会话）；若需端到端确认，可约窗口 `sudo reboot` 后 SSH 看 `launchctl list | grep runner` 与进程启动时间是否贴近 `kern.boottime`。
- 回滚：系统设置关闭自动登录，或 `sysadminctl -autologin off`。
- 备注：自动登录开启后，物理接触机器即可进入该账户桌面；适合专用 runner 机。

## 2026-07-20 00:03 CST - 结论：重启后 runner 需 GUI 登录才拉起；自动登录当前关闭

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Grok`
- 原因：用户询问「自动重启后、人工登录账户前，runner 能否正常工作」，并希望重启后 runner 自动上线。
- 影响：本次**仅只读排查**，未改自动登录 / LaunchAgent / runner。
- 结论（当前行为）：
  - **不能。** 两个 runner 以 **用户级 LaunchAgent** 安装，不是 LaunchDaemon；未登录 `for-konghai` 的 GUI 会话时不会启动。
  - 安装路径：`~/Library/LaunchAgents/actions.runner.cypressoai.lemon-imac-{1,2}.plist`（`svc.sh install` 标准方式）
  - plist 关键项：`RunAtLoad=true`、`SessionCreate=true`、`ProcessType=Interactive`、`UserName=for-konghai`
  - **Automatic login is OFF**（`sysadminctl -autologin status`）
  - **FileVault is Off**（因此后续可开自动登录；若以后打开 FileVault，macOS 会强制关掉自动登录）
  - `/Library/LaunchDaemons/` 下无 actions.runner 条目
- 实证（2026-07-19 系统更新重启）：
  - `kern.boottime`：`01:27`
  - 上一轮 Listener 日志在 `01:21` 随关机结束（`_diag/Runner_20260718-*.log`）
  - 新 Listener 进程与 `stdout.log` 均从 **`23:45`** 才重新 `Listening for Jobs`（UTC `15:45`）
  - 空窗约 **22 小时**：机器已 boot，但 runner 离线，直到人工 GUI 登录后 LaunchAgent 才拉起
- 对照：
  - `mac-mini`：同样是用户 LaunchAgent；因 FileVault On 无法自动登录，靠长期保持 console 已登录（少 reboot）
  - `umacbook-pro`：同样 LaunchAgent + 自动登录 OFF
- 若要实现「重启后自动接 CI」的推荐方案（待用户确认后再改）：
  1. **首选**：为 `for-konghai` 开启 **自动登录**（本机 FileVault 已关，技术上可行）
  2. 保持「登录后不注销」；可选关闭睡眠 / 启用防止 App Nap（CI 机常见）
  3. 不优先改 LaunchDaemon：官方 `svc.sh` 装的是 LaunchAgent；Daemon 在无 GUI 会话时可能踩 keychain / 权限 / 交互会话问题，且 frontend vitest 对用户环境更友好
- 开启自动登录的代价：开机后 console 直接进入桌面，物理接触机器即可用该账户；适合放在相对可信环境的专用 runner 机
- 回滚：关自动登录 → `sysadminctl -autologin off`（或系统设置）
- 验证口径（改完后）：模拟重启或等下次更新重启 → 登录前用 SSH 看 `launchctl list | grep runner` 与 GitHub runner `status=online`，无需人工点登录窗

## 2026-07-19 23:59 CST - 排查最近一次重启原因：macOS Tahoe 26.5.2 自动更新

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`，硬件 `iMac21,2`）
- 操作人：`Grok`
- 原因：用户要求检查这台机器最后一次重启的原因。
- 影响：本次**仅只读排查**，未改系统设置 / runner / LaunchAgent。
- 结论（重启原因）：
  - **macOS 系统软件更新自动安装**，不是 panic / 断电 / 人为 `reboot`。
  - 产品：`macOS Tahoe 26.5.2`（build `25F84`，product key `MSU_UPDATE_25F84_patch_26.5.2_minor`）
  - 升级路径：`26.5.1 (25F80)` → `26.5.2 (25F84)`
  - 自动更新已开：`willAutoInstall:1`、`autoUpdatesEnabled:1`，并已 `queuedForInstallTonight:1`（Install Tonight 夜间安装）
- 时间线（均 CST / +08）：
  1. `2026-07-18 19:08`：`softwareupdated` 选中后台下载产品 `MSU_UPDATE_25F84_patch_26.5.2_minor`
  2. `2026-07-18 22:07`：`SUOSUInstallTonightManager` 将 `macOS Tahoe 26.5.2 25F84` 排入今晚安装队列
  3. `2026-07-19 01:18`：Tonight observer 触发；`SUOSUScheduler: DISARMED`
  4. `2026-07-19 01:19`：登出进入 post-logout apply（`logoutNoReturn`）
  5. `2026-07-19 01:19:56`：`Software Update` 进入 post-logout 模式，`Applying MSU update`；`UpdateBrainService` 执行 `handle_MSUApplyUpdate`
  6. `2026-07-19 01:20:59`：`Rebooting (success = 1)`；`softwareupdate --history` 记录安装时间同为 `2026/07/19 01:20:59`
  7. `last`：`shutdown 01:20` → `reboot 01:27`；`kern.boottime` = `Sun Jul 19 01:27:52 2026`
  8. `2026-07-19 01:29`：新系统上 `softwareupdated` 启动日志：`Previous System Version : 26.5.1 (25F80), Current System Version : 26.5.2 (25F84)`；`InstallHistory` 写入 `macOS 26.5.2`
- 辅助证据：
  - DiagnosticReports：`com.apple.MobileSoftwareUpdate.UpdateBrainService_2026-07-19-012038_*.diag`（preboot personalization / stage boot objects，约写盘 2.1GB）
  - DiagnosticReports：`shutdown_stall_2026-07-19-012110_*.shutdownStall`（关机阶段卡顿，系统更新安装时常见，**不是 kernel panic**）
  - `/Library/Logs/DiagnosticReports/` 无 panic 报告
  - `last` 中 7/16 的 session 标记为 `crash`（另一次事件）；本次 7/19 为正常 `shutdown` + `reboot`
- 当前状态（排查时）：
  - `sw_vers`：`macOS 26.5.2` / build `25F84`
  - uptime 约 22.5h（自 01:27 boot）
  - LaunchAgent：`actions.runner.cypressoai.lemon-imac-1` / `lemon-imac-2` 均在；两个 `Runner.Listener`（service）在跑（约 23:45 随用户会话拉起）
  - 磁盘：`/` 约 12G 已用 / 62G 可用；load 约 2–5，较 7/17 重启后 Spotlight 高峰已回落
- 回滚：无（只读）。若希望避免 CI runner 机在夜间自动重启，可在「系统设置 → 通用 → 软件更新」关闭自动安装 macOS 更新（或改计划窗口）；改设置前需用户确认。

## 2026-07-17 21:37 CST - 重启后恢复检查：runner 已 online

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Grok`
- 原因：用户反馈机器曾不明原因重启，现已恢复，要求做最终检查。
- 影响：本次**仅只读排查**，未改 runner / LaunchAgent / labels / workflow。
- 观察结果：
  - 最近一次 boot：`2026-07-17 07:46 CST`（此前还有 `2026-07-16 22:49` 一次 reboot 记录）。
  - 当前 uptime 约 13h51m；登录用户 `for-konghai`。
  - LaunchAgent：`actions.runner.cypressoai.lemon-imac-1`、`lemon-imac-2` 均在 `launchctl list` 中。
  - 进程：两个 `Runner.Listener`（service 模式）+ 对应 `RunnerService.js`（node20）在跑；**无** active `Runner.Worker` / vitest。
  - GitHub API：`lemon-imac-1` / `lemon-imac-2` 均为 `status=online`、`busy=false`。
  - labels 完整：`self-hosted,macos,arm64,lemon-imac,macos-arm64,frontend-tests-ci`。
  - 磁盘：`/` 约 13G 已用 / 44G 可用（23%）；内存 8G。
  - load average 偏高（约 16–22），**主因是 Spotlight 索引**（`mds` / 多个 `mdworker_shared` 占 CPU 前列），不是 CI job。重启后 Spotlight 重建索引属常见现象，预计会随索引完成回落。
  - 备注：`ps` 显示 Listener 启动时间约当日 21:16；若 boot 在 07:46 而 GUI/用户会话更晚才可用，LaunchAgent 可能延迟到会话就绪后才拉起（macOS 用户级 LaunchAgent 依赖登录会话）。
- 结论：runner 服务与 org 注册状态正常，可继续参与 `frontend-tests-ci` 共享池；无需人为干预。若 load 长时间不降且影响 job，可再查 Spotlight 是否卡在某路径。
- 回滚：无（只读）。

## 2026-07-09 02:18 +08 - 决策：保持 4 片共享 runner 池观察数日

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：用户确认不再拆分 mac / lemon 两组 job，先保持当前方案运行几天，以真实 PR 队列吞吐量判断是否值得进一步调整。
- 当前方案（已选择）：
  - `Frontend Tests` 保持 4 个 shard：`1/4..4/4`。
  - `runs-on: [frontend-tests-ci, macos, arm64]`，由 `mac-mini` 与 `lemon-imac-1` / `lemon-imac-2` 组成共享池，6 个 runner 中随机 4 个领取当前 PR 的测试 shard。
  - 每个 shard 统一使用 `VITEST_MAX_WORKERS=2`；因此 `lemon-imac-1` / `lemon-imac-2` 当前接到 shard 时也是 `maxWorkers=2`。
  - 优点：保持调度弹性，空闲 runner 可无缝接后续 PR，更贴近“60 分钟完成多少个 SonarQube Analysis”的整体吞吐目标。
  - 代价：不能按最终落到的机器动态调整 worker；`lemon-imac` 上单 shard 可能比 `mac-mini` 慢，单 PR wall time 可能受慢 shard 影响。
- 备选方案（暂不采用）：
  - 拆成 mac / lemon 两组 `Frontend Tests` job。
  - mac job 使用 `[mac-mini-sonar, frontend-tests-ci, macos, arm64]` 和 `VITEST_MAX_WORKERS=2`。
  - lemon job 使用 `[lemon-imac, frontend-tests-ci, macos, arm64]` 和 `VITEST_MAX_WORKERS=1`。
  - 优点：可以单独把 `lemon-imac` 每 shard `maxWorkers` 降到 1，降低 8GB 机器上的内存压力。
  - 代价：需要固定拆分 shard / job，无法继续保持 6 个 runner 随机抢 4 个 shard 的单一共享池；也会增加分片和调度复杂度。
- 观察口径：
  - 以 60 分钟内完成的 `SonarQube Analysis` PR run 数量作为主要量化指标，数量越大说明整体队列吞吐越好。
  - 同时记录失败类型：真实测试失败、flaky timeout、runner 排队、SonarQube gate 失败要分开看，不混为“CI 慢”。
  - 若 `lemon-imac` 相关 shard 持续成为长尾或 flaky 来源，再重新评估备选方案。

## 2026-07-09 02:12 +08 - frontend-mas CI 收敛为 4 片共享 runner 池并处理今晚 PR

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：6 片方案会增加重复启动/安装开销并拉长关键路径；用户明确要求回到 4 片，让 `mac-mini` 与 `lemon-imac` 共 6 个 runner 中随机 4 个领取当前 PR 的 `Frontend Tests`，其余空闲 runner 接后续 PR。
- 影响：
  - `frontend-mas` PR `#1042` 将 `.github/workflows/sonar.yml` 收敛为单个 `frontend-tests-shards` matrix：`Frontend Tests 1/4..4/4`。
  - `runs-on` 改为 `[frontend-tests-ci, macos, arm64]`，让 `mac-mini` 与 `lemon-imac-1` / `lemon-imac-2` 都能参与抢占 shard。
  - 每个 shard 通过 workflow 环境变量设置 `VITEST_MAX_WORKERS=2`；`package.json` 的 `test:ci` 支持 `${VITEST_MAX_WORKERS:-4}`，本地默认仍可用 4。
  - 取消过时的 6 片 run，避免继续占用 runner。
- 观察结果：
  - `#1043` 备用吞吐测试 PR 在 4 片共享池下完成成功，run `28962561762` 耗时 `9m37s`。
  - `#1042` 转 ready 后最新 required run `28963719147` 完成成功，耗时 `14m15s`；四个 shard 分别约 `8m33s`、`10m11s`、`6m44s`、`5m31s`。
  - `#1044` 先在旧 mac-only / `maxWorkers=4` 配置下出现多处无关 flaky；更新到合并后的 `develop` 后，run `28964670159` 在 4 片共享池 + `VITEST_MAX_WORKERS=2` 下完成成功。
- PR 处理：
  - `#1042` 已 squash merge，merge commit `5db5de315479d4170773117340ee39b372750ef0`。
  - `#1043` 已关闭，远端备用分支 `optimize/CYP-1246-frontend-ci-queue-b` 已删除。
  - `#1044` 已 squash merge，merge commit `594dccd6cb75911f5d128d818d02e98998f4a21c`。
  - 处理完成时 `iCare-frontend-mas` 无 open PR。
- 回滚方式：
  - 如需回退共享池策略，可在 `frontend-mas` 恢复为 `runs-on: [mac-mini-sonar, frontend-tests-ci, macos, arm64]` 或固定 mac-only label。
  - 如需回退 worker 策略，可把 workflow 的 `VITEST_MAX_WORKERS` 改回 1/4，或把 `package.json` 的 `test:ci` 恢复固定 `--maxWorkers=4`。
- 验证：
  - `npm run check:ci-workflows` 在 CI 配置分支通过。
  - `#1042`、`#1044` 的 GitHub required checks 均通过，包括 `Frontend Tests`、`Typecheck`、`SonarQube Scan` 与 `SonarQube Code Analysis`。

## 2026-07-09 01:12 +08 - 重命名第一 GitHub Actions runner 并让两个 lemon slot 参与 Frontend Tests

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：用户希望统一 runner 命名，将第一 slot 从 `lemon-imac` 改为 `lemon-imac-1`，并让 `lemon-imac-1` / `lemon-imac-2` 都参与 `frontend-mas` 的 `Frontend Tests`；同时要求 lemon 机器上的每个 shard 单独使用 `maxWorkers=1`。
- 影响：
  - GitHub 组织 `cypressoai` 中旧 runner `lemon-imac` 已移除并重新注册为 `lemon-imac-1`。
  - 远端 runner 目录从 `/Users/for-konghai/actions-runner/lemon-imac` 改为 `/Users/for-konghai/actions-runner/lemon-imac-1`；`lemon-imac-2` 保持不变。
  - 当前两个 LaunchAgent 为 `actions.runner.cypressoai.lemon-imac-1` 与 `actions.runner.cypressoai.lemon-imac-2`。
  - 两个 runner 均保留标签 `self-hosted`、`macos`、`arm64`、`lemon-imac`、`macos-arm64`、`frontend-tests-ci`。
  - `frontend-mas/.github/workflows/sonar.yml` 改为两组 `Frontend Tests` job：`mac-mini` 跑 `1-4/6`，每 shard `VITEST_MAX_WORKERS=2`；`lemon-imac` 跑 `5-6/6`，每 shard `VITEST_MAX_WORKERS=1`。
- 备份：
  - 远端旧 runner 配置备份到 `/Users/for-konghai/actions-runner/backups/lemon-imac-rename-20260709-010840`，包含 `.runner`、`.credentials`、`.credentials_rsaparams`、`.service` 和旧 LaunchAgent plist。
- 回滚方式：
  - runner 回滚：停止并卸载 `actions.runner.cypressoai.lemon-imac-1`，用 GitHub removal token 移除注册记录，再用备份目录中的配置或重新注册为 `lemon-imac`。
  - workflow 回滚：把 `frontend-mas/.github/workflows/sonar.yml` 恢复到 mac-only 4 shard 配置，或回退到 `frontend-mas` 提交 `122e7088`。
- 变更时序：
  1. 生成 GitHub Actions removal token 与 registration token，未写入文档或磁盘。
  2. 备份旧 `lemon-imac` runner 的本地配置和 LaunchAgent plist。
  3. 停止并卸载旧 `actions.runner.cypressoai.lemon-imac`，执行 runner removal；卸载阶段 `launchctl` 曾返回 `Unload failed: 5: Input/output error`，后续验证旧服务与旧 plist 均已不再存在。
  4. 移动目录为 `/Users/for-konghai/actions-runner/lemon-imac-1`，重新注册 runner 名称 `lemon-imac-1`，work folder 仍为 `/Users/for-konghai/gha/li`。
  5. 安装并启动新 LaunchAgent `actions.runner.cypressoai.lemon-imac-1`。
  6. 修改 `frontend-mas` workflow，通过拆分 mac / lemon 两组 job 实现按机器设置不同的 `VITEST_MAX_WORKERS`。
- 验证：
  - `launchctl list` 显示 `actions.runner.cypressoai.lemon-imac-1` 与 `actions.runner.cypressoai.lemon-imac-2` 均已运行。
  - GitHub API 显示 `lemon-imac-1` 与 `lemon-imac-2` 均为 `status=online`、`busy=false`，且均包含 `lemon-imac` 与 `frontend-tests-ci` 标签。
  - `frontend-mas` 执行 `npm run check:ci-workflows` 通过。
  - 已推送 `frontend-mas` 提交 `3c2ee55d`，触发 SonarQube Analysis runs `28961475050` 与 `28961475025`；新 job 名称已出现 `Frontend Tests 1-4/6 (mac)` 和 `Frontend Tests 5-6/6 (lemon)`，备用分支的两个 lemon shard 已开始执行。

## 2026-07-08 02:23 CST - 只读盘点 frontend-mas runner 本地缓存现状

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：用户询问 frontend test runner 的缓存方案是在 workflow 侧还是 runner 侧配置，以及 `lemon-imac` 与 `mac-mini` 当前缓存现状。
- 影响：仅读取 workflow 配置和本机 runner 目录大小；未修改 runner、workflow、缓存目录或服务。
- 观察结果：
  - `frontend-mas/.github/workflows/sonar.yml` 未使用 `actions/cache`，`actions/setup-node` 未配置 `cache: npm`；依赖安装通过 `npm ci --prefer-offline --no-audit --fund=false` 使用本机 npm cache。
  - `lemon-imac` 两个 runner slot 分别使用 `/Users/for-konghai/gha/li` 与 `/Users/for-konghai/gha/li2`，工作目录互相隔离。
  - 用户级 npm cache `/Users/for-konghai/.npm` 约 `184M`，由同一 macOS 用户下的两个 runner slot 共享。
  - 两个 slot 各自有独立 Node tool cache：`_tool/node/24.18.0/arm64`，各自约 `195M`。
  - 两个 slot 的 `iCare-frontend-mas` workspace 各自保留 `.git` 约 `29M`、`node_modules` 约 `752-754M`。
- 结论：当前缓存主要是 self-hosted runner 的本机持久缓存，不是 GitHub 远端 cache；同机共享的是用户级 npm tarball cache，workspace / Node tool cache 仍按 runner slot 独立。

## 2026-07-08 01:54 CST - 观察 frontend-tests-ci 共享池首次 4 分片调度效果

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：用户提供 `frontend-mas` workflow run `28886024783`，需要确认 4 个 `Frontend Tests` shard 被 `mac-mini` 与 `lemon-imac` 两台设备共同领取是否符合预期，并评估速度与缓存 / 网络流量影响。
- 影响：仅读取 GitHub Actions run 元数据和 job 日志；未修改 runner、workflow 或服务。
- 观察结果：
  - `Frontend Tests 4/4` 落到 `lemon-imac-2`，job 约 375 秒，其中 `npm ci` 约 14 秒、Vitest 约 327 秒。
  - `Frontend Tests 1/4`、`2/4`、`3/4` 分别落到 `mac-mini-sonar-4`、`mac-mini-sonar-1`、`mac-mini-sonar-2`。
  - 本轮从最早 job start 到 workflow failure 约 562 秒；失败点在 `Frontend Tests 2/4` 的 `CreateLoaModal.test.tsx` 偶发超时，发生于 `mac-mini-sonar-1`，不是 `lemon-imac` 环境错误。
  - `npm ci` 在各 shard 上约 11-15 秒，说明持久化 self-hosted runner 的本机 npm tarball cache 已经有效命中，依赖安装网络消耗不是当前最大信号。
- 结论：
  - 4 个 shard 被两台设备领取是共享 `frontend-tests-ci` label 后的预期行为；GitHub Actions 会把 matrix job 独立派发到任意满足 `[frontend-tests-ci, macos, arm64]` 的空闲 runner slot。
  - 共享池更适合降低多 PR 并发时的排队时间，不保证单个 PR 的 wall time 一定变短；单次耗时仍受最慢 shard 和 flaky test 影响。
  - 跨机器会降低缓存局部性：`mac-mini` 与 `lemon-imac` 不共享 git object cache、Node tool cache、npm cache 或工作目录。当前更值得优化的网络流量点是 `Frontend Tests` 的 `actions/checkout`，可考虑只让测试 job 使用 shallow fetch，并保留 Sonar job 的 `fetch-depth: 0`。

## 2026-07-08 01:22 CST - 为 lemon-imac runner 加入 frontend-tests-ci 共享测试池

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：用户明确目标是降低 3 个同事频繁开 PR 时的整体 CI 排队时间，而不是只优化单个 PR 的执行时间。精确表达“mac-mini 接任务则 4 片、lemon-imac 接任务则 2 片”不是 GitHub Actions 原生调度能力；改用共享 runner label 让两台机器都能接 `Frontend Tests` shard。
- 影响：
  - GitHub 组织 `cypressoai` 中 `lemon-imac` 与 `lemon-imac-2` 新增自定义标签 `frontend-tests-ci`。
  - `frontend-mas` PR 分支保留 4 片 `Frontend Tests`，但 `runs-on` 改为 `[frontend-tests-ci, macos, arm64]`，因此 4 个 shard 可被 `mac-mini-sonar-1..4` 或 `lemon-imac` / `lemon-imac-2` 任意空闲 slot 领取。
  - 未修改远端 runner 文件，未重启 iMac 或 runner 服务。
- 回滚方式：
  - 从 `lemon-imac` 与 `lemon-imac-2` 的 GitHub runner labels 中移除 `frontend-tests-ci`。
  - `frontend-mas/.github/workflows/sonar.yml` 恢复为 `[mac-mini-sonar, macos, arm64]`。
- 验证：
  - GitHub API 显示 `lemon-imac` 与 `lemon-imac-2` 均包含 `frontend-tests-ci`、`macos`、`arm64`。
  - `frontend-mas` workflow 校验通过：`npm run check:ci-workflows`、`actionlint -ignore 'label ".*" is unknown' .github/workflows/sonar.yml`、YAML parse。

## 2026-07-08 01:13 CST - 确认混合分片收益不足，frontend-mas 回退到 mac-mini 4 片

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：`frontend-mas` workflow run `28883967948` 合并 `VITEST_MAX_WORKERS=1` 后再次验证，用户反馈整体仍无明显改善，希望拆开 `lemon-imac` 与 `mac-mini` 的工作，不再混合切同一套测试分片。
- 影响：
  - 仅读取 GitHub Actions run 元数据并修改 `frontend-mas` PR 分支 workflow；未修改远端 runner、未重启服务。
  - `lemon-imac` 两个 runner slot 仍保留在线，可供后续单独 workflow / 独立 job 使用。
- 观察结果：
  - 本轮 run `completed/success`，按本轮最早 job start 到汇总 job complete 约 571 秒。
  - `Frontend Tests 5/6 (lemon-imac)`：job 约 555 秒，测试约 502 秒。
  - `Frontend Tests 6/6 (lemon-imac)`：job 约 315 秒，测试约 263 秒。
  - `Frontend Tests 3/6 (mac-mini)`：job 约 456 秒，测试约 387 秒。
  - `maxWorkers=1` 降低了 lemon 单 job 内并发，但显著拉长 lemon shard 耗时；收益不如保留默认 `maxWorkers=2`。
- 结论：
  - `lemon-imac` 与 `mac-mini` 混合分担同一个 Vitest shard 池收益不稳定，主要受异构机器性能、Vitest 文件级分片不均衡和每片重复安装/启动成本影响。
  - 已在 `frontend-mas` PR 分支把 `sonar.yml` 回退为 4 片：`Frontend Tests 1/4..4/4`，随后在 01:22 进一步改为通过 `[frontend-tests-ci, macos, arm64]` 共享 runner 池调度。
  - 已把 `package.json` 的 `test:ci` 恢复为固定 `--maxWorkers=2`，移除 `VITEST_MAX_WORKERS` 实验入口。
- 验证：
  - `npm run check:ci-workflows` 通过。
  - `actionlint -ignore 'label ".*" is unknown' .github/workflows/sonar.yml` 通过。
  - YAML 解析通过。

## 2026-07-08 00:47 CST - 只读排查 lemon shard 因重复 maxWorkers 参数失败

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：用户反馈 `frontend-mas` workflow run `28882843047` 中 `lemon-imac` 上的 `Frontend Tests 5/6` 和 `6/6` 直接失败。
- 影响：仅读取 GitHub Actions run 元数据、远端 runner `_diag` 日志和本地复现命令；未修改远端 runner、未重启服务。
- 结论：
  - 失败不是 runner 环境问题，而是 workflow 命令问题。
  - `package.json` 的 `test:ci` 已固定 `--maxWorkers=2`，workflow 额外追加 `--maxWorkers=1` 后，Vitest 收到两个值并立即报错：`Expected a single value for option "--maxWorkers <workers>", received [2, 1]`。
  - 在 `frontend-mas` PR 分支中已改为由 `VITEST_MAX_WORKERS` 环境变量控制，默认仍为 2，lemon shard 设置为 1，避免重复 CLI 参数。
- 验证：
  - `npm run check:ci-workflows` 通过。
  - `actionlint -ignore 'label ".*" is unknown' .github/workflows/sonar.yml` 通过。
  - 本地用 `VITEST_MAX_WORKERS=1 npm run test:ci -- --shard=6/6` 进入正常测试执行阶段，不再出现重复 `--maxWorkers` 解析错误；验证进程随后手动中断，未等待完整测试跑完。

## 2026-07-08 00:18 CST - 复测第二个 runner slot 对 frontend-mas 分片耗时的影响

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：新增 `lemon-imac-2` 后，用户重新允许 `frontend-mas` workflow run `28877788298`，需要观察两个 lemon shard 是否并发以及总耗时是否改善。
- 影响：仅读取 GitHub Actions run 元数据和远端系统状态；未修改 runner、workflow 或服务。
- 观察结果：
  - 重新跑的 workflow 最终 `completed/success`，按本轮最早 job start 到汇总 job complete 计算约 7 分 27 秒；上一轮单 lemon slot 约 9 分 36 秒。
  - `Frontend Tests 6/6 (lemon-imac)`：job 约 216 秒，测试约 163 秒。
  - `Frontend Tests 5/6 (lemon-imac)`：job 约 344 秒，测试约 291 秒。
  - `Frontend Tests 3/6 (mac-mini)` 仍是最慢 mac-mini shard：job 约 431 秒，测试约 365 秒。
  - 两个 lemon shard 这轮没有像上一轮那样串行排队；`lemon-imac-2` 在 `6/6` 完成后空闲，`lemon-imac` 继续跑较慢的 `5/6`。
- 远端状态：
  - 并发期间 `lemon-imac` load average 曾超过 20；测试后仍约 15。
  - 未见 swap in/out，但内存 compressor 使用明显，说明 8GB 内存下并发两个 Vitest job 有资源压力。
- 结论：
  - 第二个 runner slot 解决了 lemon 两片排队，但整体收益有限，主要瓶颈转为分片不均衡和机器资源竞争。
  - 继续增加 runner slot 不建议；下一步更应该优化分片策略或降低每个 job 的重复安装/启动成本。

## 2026-07-07 23:51 CST - 新增第二个 GitHub Actions runner slot

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：`frontend-mas` PR workflow 已把测试切成 6 片，其中 2 片调度到 `lemon-imac`；单 runner slot 会导致这 2 片串行排队，需要增加第二个 runner slot 做并发验证。
- 影响：
  - 新增 runner 目录：`/Users/for-konghai/actions-runner/lemon-imac-2`。
  - 新增短 work 目录：`/Users/for-konghai/gha/li2`。
  - 新增并启动 macOS LaunchAgent：`actions.runner.cypressoai.lemon-imac-2`，配置文件位于 `/Users/for-konghai/Library/LaunchAgents/actions.runner.cypressoai.lemon-imac-2.plist`。
  - GitHub 组织 `cypressoai` 新增 runner `lemon-imac-2`，runner group 为 `Default`。
  - `lemon-imac` 与 `lemon-imac-2` 共享标签：`self-hosted`、`macos`、`arm64`、`lemon-imac`、`macos-arm64`；现有 `runs-on: [self-hosted, lemon-imac]` 可同时匹配两个 slot。
  - 未安装 Docker，未修改既有 `lemon-imac` runner，未重启 iMac。
- 备份：
  - 新增安装，无既有文件需要备份。
  - 注册 token 仅在命令进程中临时使用，未写入文档或磁盘。
- 回滚方式：
  1. `cd /Users/for-konghai/actions-runner/lemon-imac-2 && ./svc.sh stop && ./svc.sh uninstall`
  2. 用 GitHub removal token 执行 `./config.sh remove --token <removal-token>`（token 可由 `gh api -X POST orgs/cypressoai/actions/runners/remove-token --jq .token` 获取）。
  3. 删除 `/Users/for-konghai/actions-runner/lemon-imac-2` 与 `/Users/for-konghai/gha/li2`。
- 变更时序：
  1. 预检确认远端不存在 `lemon-imac-2` 目录、work 目录、LaunchAgent 或 GitHub runner 记录。
  2. 复用现有 `lemon-imac` runner 目录内已下载的 `actions-runner-osx-arm64-2.335.1.tar.gz`，复制到新目录。
  3. 用 SHA-256 `e1a9bc7a3661e06fa0b129d15c2064fe65dc81a431001d8958a9db1409b73769` 校验通过后解压。
  4. 执行 `config.sh --unattended` 注册 runner，名称 `lemon-imac-2`、work folder `/Users/for-konghai/gha/li2`、标签与第一 slot 对齐。
  5. 执行 `svc.sh install` 与 `svc.sh start` 安装并启动 LaunchAgent。
- 验证：
  - GitHub API 显示 `lemon-imac` 与 `lemon-imac-2` 均为 `status=online`、`busy=false`、`os=macos`。
  - 两个 runner 的标签完全一致，均包含 `lemon-imac`。
  - 远端存在两个 `Runner.Listener run --startuptype service` 进程，分别来自 `lemon-imac` 与 `lemon-imac-2` 目录。
  - `lemon-imac-2` 日志显示 `Connected to GitHub`、`Current runner version: '2.335.1'`、`Listening for Jobs`。
- 后续：
  - 用下一轮 PR run 验证 `Frontend Tests 5/6` 与 `6/6` 是否同时落到两个 slot，以及 8GB 内存下并发是否实际缩短总时长。

## 2026-07-07 23:35 CST - 只读分析 frontend-mas PR 测试分片在 lemon-imac 上串行排队

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：用户反馈 `frontend-mas` SonarQube workflow 改成 6 片后，`lemon-imac` 只有 1 个 runner，两个 lemon shard 串行排队，整体可能更慢；需要只读确认瓶颈。
- 影响：仅读取 GitHub Actions run 元数据与远端系统状态；未新增 runner，未修改 workflow，未重启服务。
- 观察结果：
  - workflow run `28877788298` 最终 `completed/success`，总耗时约 9 分 36 秒。
  - `Frontend Tests 6/6 (lemon-imac)` 从 run 创建后约 6 秒开始，job 总耗时约 246 秒，其中测试约 130 秒。
  - `Frontend Tests 5/6 (lemon-imac)` 等待约 257 秒才开始，job 总耗时约 302 秒，其中测试约 259 秒。
  - mac-mini 四个 shard 并发开始，最慢的是 `Frontend Tests 3/6 (mac-mini)`，job 总耗时约 430 秒，其中测试约 356 秒。
  - 结论：当前新增的第 6 片没有真正并发，因为 `lemon-imac` 只有 1 个 runner slot；关键路径变成 lemon 两片串行，总体被拉到约 9.5 分钟。
- 远端状态：
  - `lemon-imac` 为 8 logical CPUs，内存 8GB。
  - 测试后系统无 swap in/out，但 compressor 使用明显；执行期间 load average 曾接近 19。
  - runner 仍为单实例 `actions.runner.cypressoai.lemon-imac`，状态正常。
- 后续建议：
  - 最稳妥的短期优化是改成 5 片：mac-mini 跑 1-4/5，lemon-imac 跑 5/5，避免 lemon 单 runner 上排队。
  - 若坚持 6 片，则需要给 `lemon-imac` 增加第二个 runner slot，但 8GB 内存下应先用一轮 PR 验证并发两个 Vitest job 是否真的变快，避免 CPU / 内存争用抵消收益。

## 2026-07-07 22:51 CST - 配置裸跑 macOS ARM GitHub Actions runner

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：将新增 iMac 接入 `cypressoai` GitHub Actions 组织级 self-hosted runner，用于后续按标签调度 macOS ARM 任务。
- 影响：
  - 新增 runner 目录：`/Users/for-konghai/actions-runner/lemon-imac`。
  - 新增短 work 目录：`/Users/for-konghai/gha/li`，避免 macOS 上部分工具因 runner 临时目录路径过长出问题。
  - 新增并启动 macOS LaunchAgent：`actions.runner.cypressoai.lemon-imac`，配置文件位于 `/Users/for-konghai/Library/LaunchAgents/actions.runner.cypressoai.lemon-imac.plist`。
  - runner 注册到 GitHub 组织 `cypressoai` 的 `Default` runner group，名称 `lemon-imac`，标签为 `self-hosted`、`macos`、`arm64`、`lemon-imac`、`macos-arm64`。
  - 未安装 Docker；该 runner 当前为裸跑模式。没有 `docker`、`backend-ci`、`frontend-sonar-ci` 标签，不会承接依赖这些标签的现有 job。
- 备份：
  - 新增安装，无既有 runner 文件需要备份。
  - GitHub 注册 token 仅在本次命令中临时使用，未写入文档或磁盘。
- 回滚方式：
  1. `cd /Users/for-konghai/actions-runner/lemon-imac && ./svc.sh stop && ./svc.sh uninstall`
  2. 用 GitHub removal token 执行 `./config.sh remove --token <removal-token>`（token 可由 `gh api -X POST orgs/cypressoai/actions/runners/remove-token --jq .token` 获取）。
  3. 删除 `/Users/for-konghai/actions-runner/lemon-imac` 与 `/Users/for-konghai/gha/li`。
- 变更时序：
  1. 通过 GitHub API 确认组织 `cypressoai` 下没有同名 `lemon-imac` runner。
  2. 从官方 `actions/runner` release 下载 `actions-runner-osx-arm64-2.335.1.tar.gz`。
  3. 用 release 公布的 SHA-256 `e1a9bc7a3661e06fa0b129d15c2064fe65dc81a431001d8958a9db1409b73769` 校验通过后解压。
  4. 执行 `config.sh --unattended` 注册 runner，指定 runner group `Default`、名称 `lemon-imac`、work folder `/Users/for-konghai/gha/li`。
  5. 执行 `svc.sh install` 与 `svc.sh start` 安装并启动 LaunchAgent。
- 验证：
  - `svc.sh status` 显示 `actions.runner.cypressoai.lemon-imac` 已启动。
  - 远端进程存在 `runsvc.sh` 与 `Runner.Listener run --startuptype service`。
  - runner 日志显示 `Connected to GitHub`、`Current runner version: '2.335.1'`、`Listening for Jobs`。
  - GitHub API 显示 `lemon-imac`：`status=online`、`busy=false`、`os=macos`、标签正确。
  - 当前 service PATH 为 `/usr/bin:/bin:/usr/sbin:/sbin`；`git`、`curl`、`tar`、`unzip`、`xcodebuild` 可用，`brew`、`node`、`npm`、`docker`、`dotnet`、`gpg` 暂不在 PATH。
- 后续：
  - 如需承接 frontend/backend Sonar 或构建任务，先补齐 Homebrew、Node/npm、GPG 等工具链，并更新 runner service 的 `.path`；验证后再加 `frontend-sonar-ci` / `backend-ci` 等共享标签。
  - 只有 workflow 用到 `container:`、`services:` 或 Docker 构建/运行时才需要安装 Docker；普通 shell、Node、Xcode、Go 等任务可以裸跑。

## 2026-07-07 22:43 CST - 接入 Tailscale iMac SSH 别名并安装公钥

- 服务器：`lemon-imac`（Tailscale `100.81.246.93`，设备名 `lemon-imac` / 主机名 `iMac.lan`）
- 操作人：`Codex`
- 原因：新增一台 iMac 作为后续 runner 机器，需要从本机通过 Tailscale 内网稳定 SSH 登录，并设置易记别名。
- 影响：
  - 本机 `~/.ssh/config` 新增 `Host lemon-imac`，指向 `100.81.246.93`，用户 `for-konghai`，使用 `~/.ssh/id_ed25519`。
  - 远端 `for-konghai` 用户的 `~/.ssh/authorized_keys` 加入本机公钥，后续可用 `ssh lemon-imac` 免密登录。
  - 未安装 runner，未启动或重启服务，未修改系统级 SSH 配置。
- 备份：
  - 本机 SSH 配置备份：`~/.ssh/config.bak.20260707-ssh-lemon-imac`。
  - 远端授权文件备份：`/Users/for-konghai/.ssh/authorized_keys.bak.20260707-ssh-lemon-imac`。
- 回滚方式：
  - 本机删除 `~/.ssh/config` 中 `Host lemon-imac` 配置块，或用备份文件恢复。
  - 远端从 `/Users/for-konghai/.ssh/authorized_keys` 删除本机公钥行，或恢复上述备份文件。
- 变更时序：
  1. 确认 Tailscale 中 `100.81.246.93` 在线；用户在图形界面开启 SSH 后，22 端口可用。
  2. 备份本机 SSH 配置并追加 `lemon-imac` 别名。
  3. 通过密码认证把本机 `id_ed25519.pub` 上传到远端临时目录。
  4. 远端创建/更新 `~/.ssh/authorized_keys`，设置 `~/.ssh` 为 `700`、`authorized_keys` 为 `600`，并清理临时公钥文件。
  5. 使用 `ssh lemon-imac` 验证公钥免密登录。
- 验证：
  - `ssh lemon-imac` 登录成功，返回用户 `for-konghai`。
  - 系统：macOS `26.5.1`（Build `25F80`），架构 `arm64`。
  - 当前可用基础工具：`git`、`curl`、`tar`、`unzip`、`xcodebuild`。
  - 暂未发现 GitHub Actions runner 目录或 runner 进程；`brew`、`node`、`npm`、`dotnet`、`docker` 暂不在当前 `PATH`。
