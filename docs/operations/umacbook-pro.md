# umacbook-pro 运维操作时间线

## 2026-08-20 10:25 CST - 重启 ToDesk GUI，供用户进去跑屏幕共享 SRP 脚本

- 服务器：`umacbook-pro`
- 操作人：`Grok`
- 原因：直连 `vnc://100.113.23.49` 和本机隧道 `vnc://127.0.0.1:5901` 都过不了屏幕共享登录框（本机 `dscl -authonly` 已证明账号密码正确，疑为 `AllowSRPForNetworkNodes=false`）。用户要用 ToDesk 进去跑 `enable-screensharing-srp.sh`。
- 影响：只重启了 `for-konghai` 的 ToDesk GUI（新 pid 2832，监听 `127.0.0.1:37600`）。`ToDesk_Service` 仍是开机后的 pid 735（无 sudo 杀不掉）。未动 runner / Tailscale / 屏幕共享配置。
- 备份：无。
- 回滚：不必。
- 验证：GUI 10:25 新起；Service 仍 running。设备码沿用 **`254880455`**。
- 用户下一步：ToDesk 连上后执行 `sudo /Users/for-konghai/gha/scripts/enable-screensharing-srp.sh`。SSH 仍可用，也可在 `ssh umacbook-pro` 里跑同一条。

## 2026-08-20 10:13 CST - 屏幕共享已开；清掉一条卡住的 VNC 连接

- 服务器：`umacbook-pro`
- 操作人：`Grok`
- 原因：用户说屏幕共享连不上。
- 影响：只 `launchctl kickstart -k system/com.apple.screensharing`，清掉半开连接。未改防火墙、未改 ACL、未动 runner / Tailscale。
- 备份：无。
- 回滚：不必；服务本就该开着。
- 核实：
  - `screensharingd` 本来就是 running，`*.5900` LISTEN，防火墙关着
  - ACL 是 admin 组：`for-konghai`、`u` 都有权
  - 卡住的是 `100.113.23.49:5900 ← 100.92.181.15:60973` ESTABLISHED（用户 Air 的 Tailscale 地址），Recv-Q=12，新会话会被挡
  - kickstart 后新 pid 1350，旧连接变 FIN_WAIT_2，5900 仍在听
- 用户侧：先退出本机卡住的「屏幕共享」窗口，再连 `vnc://100.113.23.49`，账号用 `for-konghai`

## 2026-08-20 09:58 CST - Tailscale 已换成 brew LaunchDaemon，IP 仍是 100.113.23.49

- 服务器：`umacbook-pro`
- 操作人：`konghai`（卸 GUI、登录、把节点 IPv4 改回原地址）、`Grok`（预装 formula、写启动脚本、核对）
- 原因：GUI Standalone 绑登录会话；改成和 lemon-imac / mac-mini 一样的开源 `tailscaled` LaunchDaemon。
- 影响：
  - `/Applications/Tailscale.app` 已卸，无 `io.tailscale.ipn.macsys` 残留
  - `system/homebrew.mxcl.tailscale` running（pid 1668，`tailscaled` 1.102.2），`WantRunning=true`，`--hostname=umacbook-pro`，`--operator=for-konghai`，`CorpDNS=true`
  - 节点 IPv4 **仍是** `100.113.23.49`（用户在管理后台改回），MagicDNS `umacbook-pro.taila93443.ts.net` 指向同一地址
  - 本机 `~/.ssh/config` 的 `Host umacbook-pro` 不用改
- 备份：无（新登录，未搬 GUI 状态）。旧 GUI 已卸。
- 回滚：`sudo brew services stop tailscale` 后重装 GUI Standalone；不要两套同时跑。
- 验证：
  - `ssh umacbook-pro` → `SSH_OK`；`ping 100.113.23.49` / `ping umacbook-pro` 通
  - 本机 `tailscale status` 见 `umacbook-pro` active，直连
  - 重启后 runner LaunchDaemon 已自起：`umacbook-pro-1/2` Listener 09:52 起在听
- 备注：`brew services info` 非 root 会显示 Running false，以 `launchctl print system/homebrew.mxcl.tailscale` 为准。FileVault 冷启动仍要人在登录窗解锁。

## 2026-08-19 18:01 CST - runner 从 LaunchAgent 改为 LaunchDaemon；预装 brew tailscale 未启动

- 服务器：`umacbook-pro`
- 操作人：`Grok`（写脚本 / 预装 formula / 核对）、`konghai`（本机 `sudo` 安装 runner）
- 原因：和 lemon-imac 一样，注销图形用户后 runner 仍要接 job。控制台还有 `u` 的会话，`for-konghai` 注销后 LaunchAgent 会停。
- 影响：
  - `umacbook-pro-1/2` 现为 `system/actions.runner.cypressoai.umacbook-pro-N`，`KeepAlive` + `SessionCreate`，`HOME` / `GOCACHE` 写进 plist
  - 维护改成 Daemon：每日 03:20 / 周日 04:40，`MAX_GB=15`，`WORK_DIRS` 为 `u1 u2`
  - 原 crontab 两行 `gha-runner-maintenance` 已删（只剩空表），避免和 Daemon 双跑
  - 旧 Agent 停在 `~/Library/LaunchAgents.disabled-20260819/`
  - 已 `brew install tailscale` 1.102.2，**未** `brew services start`，GUI Standalone 仍在，IP 仍 `100.113.23.49`
- 选型：官方 `./svc.sh install` 只会装 LaunchAgent。安装脚本：`~/gha/scripts/install-umacbook-pro-runner-daemons.sh`
- 备份：disabled 目录里的原 plist
- 回滚：`sudo launchctl bootout system/actions.runner.cypressoai.umacbook-pro-{1,2}` 并删对应 `/Library/LaunchDaemons` plist；把 Agent 移回 `~/Library/LaunchAgents`；crontab 可从本条目拷回。不要再 `./svc.sh install`
- 验证：
  - `launchctl print`：`type = LaunchDaemon`、`state = running`、`username = for-konghai`
  - 两 slot 日志 **`Listening for Jobs`**（2.336.0）；GitHub `umacbook-pro-1/2` 均为 **online / busy=false**
  - 无 `tailscaled` 进程；`/Applications/Tailscale.app` 仍在
- 下一步：用户在 ToDesk 里卸 GUI Tailscale → 按提示重启 → 再连 ToDesk → `sudo ~/gha/scripts/start-umacbook-pro-tailscaled.sh` → 浏览器登录 → 把新 `100.x` 发回（也可在管理后台改回 `100.113.23.49`）
- 关联：`docs/runbooks/umacbook-pro-runner-start-stop.md`

## 2026-08-19 17:45 CST - 拉起 ToDesk GUI，供连上后改 runner / Tailscale Daemon

- 服务器：`umacbook-pro`
- 操作人：`Grok`
- 原因：要对这台做和 lemon-imac 一样的改造（runner + Tailscale 改 LaunchDaemon）。先让用户用 ToDesk 连上，因为卸 GUI Tailscale 后 `ssh umacbook-pro`（`100.113.23.49`）会断。
- 影响：仅 `open -a ToDesk --args -AutoRun YES`。未重启 `ToDesk_Service`、未动 runner、未动 Tailscale、无 sudo。
- 备份：无。
- 回滚：GUI 里退出即可。
- 验证：
  - 控制台用户是 `for-konghai`（Aqua `gui/502` 在），无需 sudo
  - 新 GUI pid 9545，监听 `127.0.0.1:37600`；Service 仍是 07-17 起的 pid 42202 / `35600`
  - 设备码 **`254880455`**（与 2026-07-21 记录一致）
  - `umacbook-pro-1/2` Listener 未受影响
- 备注：Service 已跑 33 天。若客户端连不上，再在本机 `sudo` 完整重启（lemon-imac 同款脚本）。

## 2026-08-13 10:49 CST - 定位 public frontend Sonar 首跑失败为 Tailscale DERP 瞬断

- 服务器/设备：`umacbook-pro`（self-hosted runner `umacbook-pro-1`）；对照 `mac-mini` SonarQube
- 操作人：`Codex`
- 原因：排查 [iCare-public-frontend attempt 1 Job 94327015274](https://github.com/cypressoai/iCare-public-frontend/actions/runs/31661331203/job/94327015274) 在 SonarQube Web 已恢复后仍报失败的原因。
- 影响：仅通过 GitHub API / Job 日志和 SSH 检查 DNS、路由、Tailscale/macOS 网络日志、SonarQube HTTP 与容器日志；未改 runner、Tailscale、Docker、SonarQube、workflow 或业务代码，未触发重跑。
- 备份：无（只读）。
- 回滚方式：无变更。
- 做了什么：
  1. 核对 attempt 1 的 Job 元数据和完整日志，确认 checkout、依赖安装、coverage 下载及 LCOV 校验均成功，唯一失败点是 ScannerCLI 查询 `SONAR_HOST_URL/api/v2/analysis/version`。
  2. 在 `umacbook-pro` 检查 `mac-mini` MagicDNS 解析、Tailscale 路由、当前 HTTP 连通性及 10:40 前后的 macOS/Tailscale 历史日志。
  3. 在 `mac-mini` 对照 SonarQube 容器健康、restart count、15 秒健康探针和访问日志。
  4. 核对同一 workflow attempt 2 的 [Job 94327302116](https://github.com/cypressoai/iCare-public-frontend/actions/runs/31661331203/job/94327302116) 及对应服务端访问记录。
- 验证结果：
  - attempt 1 于 `10:40:08` 从 Java 进程向 `100.108.64.126:9000` 发起 TCP 连接，路由正确走 `utun5`；5 秒内发出 6 个 SYN、未收到响应，ScannerCLI 因 `HTTP connect timed out` 退出。
  - Tailscale 同时记录 `open-conn-track: timeout opening ... online=yes, lastRecv=6h19m1s`；连接窗口内 home DERP 从 `derp-900` 切到 `derp-17`，目标 peer 路径尚未收敛。MagicDNS 能正常响应，排除短名解析故障。
  - `mac-mini` 上 `sonarqube` 全程 `healthy`、`RestartCount=0`；故障窗口内本地健康探针每 15 秒返回 HTTP 200，且 10:40 没有收到该 ScannerCLI 请求，排除 SonarQube Web、token、coverage 与业务代码错误。
  - attempt 2 于 `10:41:13` 已由外部重跑，仍落在同一台 `umacbook-pro-1`；Tailscale 于 `10:42:16–10:42:17` 为目标 peer 重建 `derp-900` 连接，Sonar 服务端随即收到 `/api/v2/analysis/version` 并返回 HTTP 200。最终 `10:50:00` Quality Gate `PASSED`、Scanner `EXECUTION SUCCESS`，workflow attempt 2 整体成功。
  - 当前从 `umacbook-pro` 访问同一 API 约 `0.39s` 返回 HTTP 401（未携带 token 的预期响应），证明 DNS、路由和 HTTP 链路均已自行恢复。结论：**首跑失败是 `umacbook-pro-1 → mac-mini` 的 Tailscale peer/DERP 瞬时不可达，不是昨晚 Docker Desktop 下线故障的延续，也不是 SonarQube 服务端故障。**

## 2026-08-12 13:28 CST - 定位 iCare Mobile Jest CI 超时为测试用例挂起

- 服务器/设备：`umacbook-pro`
- 操作人：`Codex`
- 原因：排查 `iCare-mobile-app` Actions run `31561202341` 的 `CI Quality` 为 runner 故障还是代码侧超时。
- 影响：以只读健康检查、runner `_diag` 日志检查为主；在当时空闲的 u2 checkout 上运行了带 20/45/90 秒硬超时的单文件 Jest 探针，并在取证后终止自建调试进程。未改 runner 配置、未重启服务、未删除业务文件。
- 备份：无（未改配置或持久状态）。
- 回滚方式：无持久变更；临时 Jest / Inspector 进程已清理。
- 做了什么：
  - 核对 attempt 1/2：分别落到 `umacbook-pro-1` / `umacbook-pro-2`，均完成 lint、type-check，随后 Jest 静默并撞上 workflow 的 `timeout-minutes: 25`。
  - 检查两份 `Worker_*.log`：runner 均在 GitHub 发来 timeout cancellation 后依次发送 SIGINT、SIGTERM、清理进程树并回传 job；未见 runner 断联、sleep、磁盘或服务异常。
  - 用各 slot 的 `jest --listTests` 顺序对照 CI 已 PASS suite，首个未完成文件均为 `src/features/reimbursements/wizard/provider-picker-screen.test.tsx`。
  - 单跑新增用例“搜索输入防抖 300ms，且切回 Near 后不沿用搜索 pending 骨架”会稳定挂住并由外层硬超时终止；排除该用例后，同文件其余 7 个测试在约 1.9 秒内通过。
- 验证结果：
  - `umacbook-pro-1/2` LaunchAgent 与 `Runner.Listener` 均保持 running，未重启；根分区使用率 17%，主机 uptime 184 天，无资源耗尽证据。
  - 同一 PR 此前还在 `mac-mini-sonar-{1,3,4}` 多次复现 25 分钟 timeout；相同的 `mac-mini-sonar-3` 跑 `develop` SHA `5624e22` 时 Jest 约 1 分 44 秒通过，进一步排除单机 runner 故障。
  - 结论：超时由 PR 新增 fake-timer/debounce 测试挂起触发，runner 只是在 25 分钟上限到达后执行取消与清理。

## 2026-08-07 13:21 CST - 只读扫描 Mini Shai-Hulud / keyv 供应链蠕虫 IoC

- 服务器/设备：`umacbook-pro`
- 操作人：`Grok`
- 原因：2026-08-04 npm keyv 家族供应链蠕虫（Mini Shai-Hulud）披露；对清单内主机做只读 IoC 体检。
- 影响：只读（find/rg/mdfind/ssh BatchMode）；未改配置、未重启、未删文件、未轮换凭证。
- 扫描 IoC：`setup.mjs` / `Math_Symbol.js` / `math_init.js`（对照 Aikido 已知 SHA-256）、`preinstall: node setup.mjs`、首批高危 lock 版本、`.claude/settings.json` / `.vscode/tasks.json`、`/tmp/bun-dl-*`。
- 结果：CLEAN（误报名碰撞）。gha u1/u2 work 下同上良性文件名碰撞；preinstall=0。
- 备份：无（只读）。
- 回滚：无变更。
- 备注：同批次不可达 `fnos-nas`（ssh 192.168.2.9:22 timeout）。全清单无已知恶意哈希命中。

## 2026-08-03 15:45 CST - CI 池加固：PNPM store + cron/launchd + go-build 修剪 + 双 slot 重启

- 服务器：`umacbook-pro`（8 核 / 8GB，Data **228G**）
- 操作人：`Grok`（iCare 自托管 runner 运维加固任务）
- 原因：双 slot go-build 各约 **15G**；无定时维护；需本机 pnpm store 减流量。
- 影响：
  - 双 slot `.env`：`PNPM_STORE_PATH=~/gha/cache/pnpm-store` + 既有 GOCACHE/GOMODCACHE
  - 脚本：`~/gha/scripts/{gha-runner-maintenance.sh,prune-gocache.sh}`
  - crontab 日 03:20 / 周日 04:40；另装 LaunchAgent 兜底
  - 即时：go-build **15G→3.1G** / **15G→2.0G**；u1 work 4.1G→1.5G；Data **62%→48% / Avail 72G→100G**
  - 双 slot `svc.sh` 重启加载 `.env`
- 备份：`~/actions-runner/umacbook-pro-N/.env.bak.*`
- 回滚：恢复 `.env.bak` + 重启；删 crontab `gha-runner-maintenance` 行；bootout LaunchAgent
- 验证：两 Listener Started；GitHub online
- 风险：个人本合盖/断网仍会掉线；非关键唯一路径
- 关联：`docs/runbooks/ci-runner-pools.md`

## 2026-07-24 17:38 CST - 只读：主机与双 runner 健康检查

- 服务器：`umacbook-pro`
- 操作人：`Grok`（只读）
- 原因：用户要求确认机器与 self-hosted runner 是否正常。
- 影响：无变更。
- 当时状态：
  - 主机：SSH 可达；macOS **15.7.2**；uptime **166 天**；Data 盘约 **103/228G（55%）、剩余 ~88G**；8 核 / 8GB，load **~14–19**（双 slot 跑 job 时正常偏高）。
  - LaunchAgent：`actions.runner.cypressoai.umacbook-pro-{1,2}` 均为 **Started**；`Runner.Listener` + `runsvc` 在跑；runner 版本本地 **2.336.0**。
  - 双 slot **Busy**：采样时 u1 先后 `SonarQube Scan` → `Lint`；u2 `SonarQube Scan`；job renew / 日志上传成功。
  - GitHub API（`orgs/cypressoai/actions/runners`）：两台最终均为 **online + busy**（中途 umacbook-pro-1 曾短暂显示 offline，属 broker 长连接取消后的瞬时态）。
  - Labels：`self-hosted,macos,arm64,macos-arm64,umacbook-pro,frontend-tests-ci,frontend-quality-ci,backend-ci`。
  - 网络：`github.com` ping 通、HTTPS 200；偶发 `BrokerServer` `SocketException/Operation canceled` 后自动 backoff 重连并继续接 job。
  - workFolder：`~/gha/u1` ~13G、`~/gha/u2` ~3.6G。
- 验证结果：**机器与 runner 正常**；高负载来自并发 CI（Sonar Java / go link / test），非故障。
- 回滚方式：无。

## 2026-07-23 19:05 CST - A+B：清空 go-build / orphan（CYP-1547）

- 服务器：`umacbook-pro`
- 操作人：`Grok`
- 原因：与 lemon 同类：per-slot go-build **41G+36G** + orphan `~/Library/Caches/go-build` **15G**；全池 A+B 治理。
- 影响：
  - 首轮清理时双 slot **Runner.Worker busy**，已等待 idle 后再清（不杀 job）
  - 删除 orphan + 清空两 slot `cache/go-build`（mtime 均 ≤2 天，按 >20GB 整目录清空）
  - Listener 保持 **Started**（未停池）
- 备份：无
- 回滚：cache 可再生
- 关联：**CYP-1547**；`scripts/prune-gocache.sh`；runbook 2 天策略
- 验证：见同轮 `disk-after` 摘要；listeners 仍 Started

## 2026-07-21 12:11 CST - 再次 open ToDesk 供用户复查 Spotlight 隐私

- 服务器：`umacbook-pro`
- 操作人：`Grok`
- 原因：重发 job 后 mds_stores 仍偏高；用户要 GUI 再检查 `/Users/for-konghai/` 隐私排除。
- 影响：`open -a ToDesk`；`for-konghai` 新 GUI pid；Session `myid=254880455` 已在。
- 回滚：用户查完可再退 GUI。

## 2026-07-21 12:08 CST - 只读：重发 Frontend Tests 运行中

- 服务器：`umacbook-pro`
- 操作人：`Grok`（只读）
- 原因：用户已在 GUI 排除 `/Users/for-konghai/`；重发 job 后对照。
- 影响：无变更。
- 当时状态：
  - 双 slot busy：`Frontend Tests 3/4`（u1 vitest 中）+ `1/4`（u2 刚起 Worker/Install）。
  - **fseventsd≈0**；**mds_stores 仍约 50%**、mds 数 %（mds 族合计 ~53），低于排除前双 slot 时 ~210%，但未像 lemon 一样归零。
  - node 合计 ~200%+；load ~6.9。
  - npm ci（u1）约 **9s**。
- 验证结果：有改善；若 mds_stores 持续偏高可再确认隐私列表是否含整个 `/Users/for-konghai/`、是否需等索引收敛。

## 2026-07-21 11:24 CST - 拉起 ToDesk 供 GUI 配置 Spotlight 隐私

- 服务器：`umacbook-pro`
- 操作人：`Grok`
- 原因：同 lemon；用户 GUI 将 `/Users/for-konghai/` 加入 Spotlight 搜索隐私。
- 影响：`open -a ToDesk`（GUI 已在跑，再 activate）。Session 采样 `myid=254880455`（`for-konghai`）。
- 回滚：无必要。
- 验证：ToDesk_Service + ToDesk / Session 进程存在。

## 2026-07-21 11:01 CST - 只读：双 slot Frontend Tests 运行中 Spotlight 争用

- 服务器：`umacbook-pro`
- 操作人：`Grok`（只读；mac-mini runner 仍 offline）
- 原因：用户重跑 job 后确认 umac 上 mds/`fseventsd` 与 CI 争用。
- 影响：无变更。
- 当时状态：
  - **双 slot busy**：`umacbook-pro-2` → Frontend Tests **1/4**（`~/gha/u2`）；`umacbook-pro-1` → **2/4**（`~/gha/u1`）。
  - 均为 `vitest run --maxWorkers=2`；load **~12.7 / 20 / 24**（8 核 / 8GB）。
  - **npm ci** 各约 **14.2s**（热 prefer-offline）。
  - **Spotlight 仍 Indexing enabled**；`mds_stores` **~35–38%**、`mds` **~18%**、多个 mdworker 合计更高；**fseventsd ~0%**。
  - CPU 合计约 node **~461%** vs mds 族 **~210%**——索引与测试并排抢核，比 lemon 采样时更显眼。
- 验证结果：确认 **mds 族是额外税**；关索引预期能把 ~1–2 核还给 Vitest（需用户确认后再改）。
- 回滚方式：无。

## 2026-07-21 10:55 CST - 只读：Spotlight 仍开启 + CI 时 mds 与 vitest 争用

- 服务器：`umacbook-pro`
- 操作人：`Grok`（只读基线；mac-mini runner 已临时停止以便分流 CI）
- 原因：同 lemon——对照 mac-mini 关 Spotlight 后的结论，核对本机是否同类问题。
- 影响：无变更。
- 做了什么：`mdutil -s`、top、runner/vitest 进程、内存磁盘。
- 当时状态：
  - **Spotlight：`/` 与 Data 均为 Indexing enabled**。
  - load ~**26–31**（8 核 / 8GB，up 162 天）。
  - 已有 job：`umacbook-pro-2` 跑 `vitest run --maxWorkers=2 --shard=2/4`（`~/gha/u2`）；同时 **mds ~20%+、mds_stores ~30%+、十余个 mdworker** 与 node 争 CPU。
  - `fseventsd` 当时 ~0–0.1%；瓶颈在 **mds 族 + vitest**。
  - runner 1/2 Listener 在线；`~/.npm` ~141M；Data 约 140/228G（74%）。
- 验证结果：**确认同类 Spotlight 问题**，且在 CI 运行时与测试抢核更明显。关索引需用户确认后操作。
- 回滚方式：无。

## 2026-07-20 20:01 CST - U5 npm 预热：frontend-mas lock 可 offline 装齐

- 服务器：`umacbook-pro`
- 操作人：`Grok`
- 原因：同 lemon R6/G4。
- 做了什么：全量 `npm ci` 回填后 `~/.npm` ≈ **149M**、content ≈ **866**；`npm ci --offline` **PASS**（8s）。
- 参考：`docs/plans/2026-07-20-001-ops-ci-runner-cache-baseline-plan.md`

## 2026-07-20 19:55 CST - 重启 umacbook-pro-1/2（缓存基线生效确认）

- 服务器：`umacbook-pro`
- 操作人：`Grok`（goal 收尾）
- 原因：计划要求本轮对 1/2 各做一次 stop/start，确认 per-slot `GOCACHE` / 共享 `GOMODCACHE` 由 service 重新加载。
- 影响：两 slot 短暂离线后重新上线；当时无 `Runner.Worker`，未取消 job。
- 回滚：无需；配置未改，仅 service 重启。
- 变更时序：idle 确认 → `./svc.sh stop && start` 于 `umacbook-pro-1` 再 `umacbook-pro-2`。
- 验证：两 LaunchAgent Started；两 `Runner.Listener` 运行；`.env` 仍为 per-slot GOCACHE + `GOMODCACHE=~/go/pkg/mod`。

## 2026-07-20 19:48 CST - CI 缓存基线：per-slot GOCACHE + 共享 GOMODCACHE

- 服务器：`umacbook-pro`
- 操作人：`Grok`（ce-work U3）
- 原因：与 lemon 同构；双 slot 原共享默认 go-build。
- 影响：`.env` per-slot `GOCACHE` + `GOMODCACHE=~/go/pkg/mod`；idle 后重启两 slot。
- 备份：`~/actions-runner/umacbook-pro-*/.env.bak.*`
- 回滚：还原 `.env.bak` 后重启 service。
- 验证：两 slot Listener online；GOCACHE 路径不同。
- 参考：`docs/plans/2026-07-20-001-ops-ci-runner-cache-baseline-plan.md`

## 2026-07-20 18:55 CST - backend-ci 基线：安装 gnupg + 暴露 Homebrew 到 runner PATH

- 服务器：`umacbook-pro`
- 操作人：`Grok`
- 原因：贴 `backend-ci` 后 Sonar Scanner 默认 GPG 校验失败。上线时已注明「跑 Sonar 需装 brew+gpg 并写 `.path`」，此前未完成。
- 影响：本机安装完整 `gnupg`（Homebrew 2.5.21，含 `dirmngr`）；`umacbook-pro-1/2` 的 `.path` 前置 `/opt/homebrew/bin` 并重启 service。
- 备份：
  - `~/actions-runner/umacbook-pro-1/.path.bak.<timestamp>`
  - `~/actions-runner/umacbook-pro-2/.path.bak.<timestamp>`
- 回滚方式：还原对应 `.path.bak.*` 后 `./svc.sh stop && ./svc.sh start`。
- 变更时序：
  1. `NONINTERACTIVE=1 brew install gnupg`
  2. 两 slot `.path` 改为 `/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin`（workFolder 已是短路径 `~/gha/u{1,2}`，未改）
  3. 先重启 idle 的 `umacbook-pro-2`；`umacbook-pro-1` 当时有 `Runner.Worker`，等 job 结束后再重启
- 验证：
  - `PATH=$(cat .path) command -v gpg` → `/opt/homebrew/bin/gpg`，`gpg (GnuPG) 2.5.21`
  - 两 slot Listener 在线
- 参考：`docs/runbooks/ci-runner-pools.md` 上线 checklist

## 2026-07-20 13:45 CST - CI 池：frontend-quality-ci + backend-ci

- 服务器：`umacbook-pro`
- 操作人：`Grok`
- 原因：PR 吞吐扩容；合盖掉线风险仍在，不当唯一路径。
- 影响：`umacbook-pro-1/2`（id 35/36）追加 `frontend-quality-ci`、`backend-ci`；保留 `frontend-tests-ci`。
- 回滚：DELETE 对应 labels。
- 参考：`docs/runbooks/ci-runner-pools.md`



## 2026-07-17 21:37 CST - 加入 frontend-tests-ci 共享池（方案 A）

- 服务器：`umacbook-pro`（Tailscale `100.113.23.49`）
- 操作人：`Grok`
- 原因：用户确认方案 A，让 `umacbook-pro-1/2` 与 mac-mini / lemon 一起承接 `Frontend Tests` shard。
- 影响：
  - 通过 GitHub API 给 runner id `35`、`36` 追加自定义 label `frontend-tests-ci`（不替换既有 labels）。
  - 当前 labels：`self-hosted`、`macos`、`arm64`、`macos-arm64`、`umacbook-pro`、`frontend-tests-ci`。
  - 匹配 `runs-on: [frontend-tests-ci, macos, arm64]` 的 job 现可调度到本机两个 slot。
  - **未**改 workflow；worker 数仍由 workflow/`VITEST_MAX_WORKERS` 控制（规划每 job 2 workers）。
  - 未重启 runner 服务（label 变更对 idle runner 即时生效）。
- 回滚方式：
  - `gh api -X DELETE orgs/cypressoai/actions/runners/{35,36}/labels/frontend-tests-ci` 移除该 label；或 PUT 全量 labels 覆盖为不含 `frontend-tests-ci` 的集合。
- 验证：
  - GitHub API：`umacbook-pro-1` / `umacbook-pro-2` 均为 `online`，labels 含 `frontend-tests-ci`。
  - 同池当前 online 成员：`mac-mini-sonar-1..4`、`lemon-imac-1/2`、`umacbook-pro-1/2`（共 8 slot）。
- 后续观察：
  - 关注 8GB 机双 slot 并发 + `VITEST_MAX_WORKERS=2` 是否 flaky / 长尾。
  - 若压力过大，可先撤 `frontend-tests-ci` 或只保留单 slot 在池内。

## 2026-07-17 20:37 CST - 安装 org 级 2 个 GitHub Actions runner slot

- 服务器：`umacbook-pro`（Tailscale `100.113.23.49`，主机名 `UdeMacBook-Pro.local`）
- 操作人：`Grok`
- 原因：用户确认 org `cypressoai`，机器名 `umacbook-pro`，2 个 slot，每个 runner 按 2 workers 规划；labels 待统筹，先上线不进共享 job 池。
- 影响：
  - 新增 self-hosted runner：`umacbook-pro-1`、`umacbook-pro-2`（agentId 35 / 36）。
  - LaunchAgent 开机自启：
    - `actions.runner.cypressoai.umacbook-pro-1`
    - `actions.runner.cypressoai.umacbook-pro-2`
  - 目录约定：
    - runner 程序：`~/actions-runner/umacbook-pro-{1,2}/`
    - 短路径 workFolder：`~/gha/u1`、`~/gha/u2`（规避 macOS GNUPGHOME 路径过长问题）
  - 当前 labels（两 slot 相同）：`self-hosted`、`macos`、`arm64`、`macos-arm64`、`umacbook-pro`
  - **未**打 `frontend-tests-ci` / `frontend-sonar-ci` / `backend-ci` / `mac-mini-sonar`，因此**不会**领取现有 frontend/backend/sonar 队列 job。
  - runner 版本：`2.335.1`（osx-arm64）。
  - 机器侧：8GB 内存 / Apple M1 / 8 逻辑核；未装 Homebrew / Node（job 内由 `actions/setup-node` 等按需安装）。
  - `.path` 当前仅为 `/usr/bin:/bin:/usr/sbin:/sbin`（无 `/opt/homebrew/bin`）。
- 关于「每个 runner 两个 workers」：
  - GitHub runner 本身不配置 Vitest worker 数；`VITEST_MAX_WORKERS=2` 在 **workflow / package.json** 侧生效。
  - 两 slot 同时跑 frontend test 时，理论峰值 2 job × 2 workers = 4 Vitest workers，与 `lemon-imac`（同为 8GB）压力量级接近。
- 备份：无（全新安装，无旧配置可备份）。
- 回滚方式：
  1. `cd ~/actions-runner/umacbook-pro-{1,2} && ./svc.sh stop && ./svc.sh uninstall`
  2. `gh api -X POST orgs/cypressoai/actions/runners/remove-token --jq .token` 取 token 后 `./config.sh remove --token <token>`
  3. 可选删除目录 `~/actions-runner/umacbook-pro-{1,2}`、`~/gha/u{1,2}`
- 变更时序：
  1. 下载 runner `v2.335.1` 到两份 slot 目录。
  2. `gh api -X POST orgs/cypressoai/actions/runners/registration-token` 取注册 token（未落盘、未写文档）。
  3. `./config.sh --unattended` 注册到 org，labels 见上，workFolder 短路径。
  4. `./svc.sh install && ./svc.sh start` 装 LaunchAgent 并启动。
  5. 清理 `~/actions-runner/_stage`。
- 验证：
  - `launchctl list`：两服务 Started（exit 0）。
  - `ps`：两个 `Runner.Listener` 以 `service` 模式运行。
  - GitHub API：`umacbook-pro-1` / `umacbook-pro-2` 均为 `status=online`、`busy=false`，labels 与注册一致。
- 后续（labels 统筹，待决策后再改）：
  - 方案 A：加入 `frontend-tests-ci` 共享池（与 mac-mini / lemon 一起抢 Frontend Tests shard）。
  - 方案 B：独立池，workflow `runs-on` 显式含 `umacbook-pro`（可单独设 `VITEST_MAX_WORKERS=2`）。
  - 方案 C：先只接轻量 job（如 typecheck），再观察 8GB 下双 slot 稳定性。
  - 若要跑 Sonar Scanner：可能需装 Homebrew + gpg，并把 `/opt/homebrew/bin` 写入各 slot `.path` 后重启服务。

## 2026-07-17 20:16 CST - 纳管新机：SSH 密钥登录 + 快捷别名

- 服务器：`umacbook-pro`（Tailscale `100.113.23.49`，主机名 `UdeMacBook-Pro.local`）
- 操作人：`Grok`
- 原因：Tailscale 网内新机，计划用于跑 GitHub Actions self-hosted runner；先完成纳管与免密登录。
- 影响：
  - 本机 `~/.ssh/config` 新增 `Host umacbook-pro` 快捷别名（`User for-konghai`，密钥 `~/.ssh/id_ed25519`）。
  - 远端 `~/.ssh/authorized_keys` 写入本机公钥（`konghai@konghai.me` ed25519）。
  - **未**改 SSH 服务配置、未禁用密码登录、未装 runner。
- 机器现状（只读探测）：
  - OS：macOS 15.7.2 / arm64（Apple M1）
  - 内存：8 GB
  - 根盘：228G 总量，约 114G 可用（14% 使用）
  - 登录用户：`for-konghai`（uid 502，属 admin 组，可 sudo）
  - 家目录：`/Users/for-konghai`
  - 已开机约 159 天
- 备份：
  - 本机 SSH config：`~/.ssh/config.bak.<timestamp>`（执行前复制）
- 回滚方式：
  - 删除本机 `~/.ssh/config` 中 `Host umacbook-pro` 段，或从对应 `.bak` 还原。
  - 远端：从 `~/.ssh/authorized_keys` 移除本次写入的公钥行。
- 变更时序：
  1. 确认 Tailscale 可达：`ping 100.113.23.49`、`nc` 探 22 端口。
  2. 用一次性密码经 `ssh-copy-id` 安装公钥到 `for-konghai@100.113.23.49`。
  3. 本机 `~/.ssh/config` 追加 `umacbook-pro` Host 块（风格对齐 `lemon-imac` / `mac-mini`）。
  4. `ssh -o BatchMode=yes umacbook-pro` 验证公钥免密登录。
- 验证：
  - `ssh umacbook-pro 'whoami'` → `for-konghai`
  - `BatchMode=yes` 成功（无密码交互）
  - `~/.ssh/authorized_keys` 权限 `600`，属主 `for-konghai`
- 后续：
  - 安装 / 注册 GitHub Actions runner（待用户确认组织、labels、并发数量）
  - 密码仅用于首次密钥安装，文档不落盘；如不再需要密码登录可再评估加固
