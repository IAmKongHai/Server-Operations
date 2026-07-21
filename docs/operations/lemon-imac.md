# lemon-imac 运维操作时间线

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
