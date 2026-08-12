# umacbook-pro 运维操作时间线

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
