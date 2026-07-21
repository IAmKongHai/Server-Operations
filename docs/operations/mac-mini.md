# mac-mini 运维时间线

## 2026-07-21 10:55 CST - 临时停止 mac-mini-sonar-1..4（分流 CI 到 lemon/umac）

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：排查 lemon-imac / umacbook-pro 上是否同样有 Spotlight/`fseventsd` 问题；需让用户重跑的 Frontend Tests 落到那两台，避免继续被 mac-mini 抢走。
- 影响：本机 4 个 org runner 离线，不再领取 `frontend-tests-ci` / `frontend-quality-ci` / `backend-ci` / `mac-mini-sonar` 等 job；队列会落到 lemon-imac / umacbook-pro / mas-go-dev（按 label 匹配）。**未** `disable` LaunchAgent（仍为 enabled），仅 `svc.sh stop`。
- 备份：无配置改动；plist 与 runner 目录完整保留。
- 回滚方式：四 slot 分别 `cd ~/actions-runner/mac-mini-sonar-N && ./svc.sh start`（N=1..4），或登录会话内 `launchctl bootstrap gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-N.plist`。
- 做了什么：
  1. 确认无 `Runner.Worker` 后，对 `mac-mini-sonar-1..4` 依次执行 `./svc.sh stop`（均 Reported Stopped）。
  2. 本机 `ps` 无 Listener/Worker；`./svc.sh status` 均为 Stopped。
- 验证结果：本机服务已停。GitHub API 可能延迟数分钟才从 online→offline（stop 后立即查时部分 slot 仍显示 online）。
- 备注：lemon / umac 基线见同日 `docs/operations/lemon-imac.md` / `umacbook-pro.md`——两机 **Spotlight 仍为 Indexing enabled**，空闲/半忙时已有 `mds`/`mds_stores`/`mdworker` 占 CPU。

## 2026-07-21 10:44 CST - 只读：四 slot 全忙 Frontend Tests 时 fseventsd

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户要求再看一眼；本轮本机 4 个 `mac-mini-sonar-*` 全部 busy。
- 影响：无变更。
- 做了什么：进程快照 + 45s/2s 采样 load / fseventsd / mds / vitest forks；Worker 日志核对 Install 耗时。
- 当时状态（10:44–10:45 CST）：
  - **4 Worker** 同时跑 `Frontend Tests`：s1=3/4、s2=1/4、s3=2/4、s4=3/4（两 run 重叠可见双份 3/4）。
  - 均为 `vitest run --maxWorkers=2` → 合计 **4 vitest + 8 forks**；node 族 CPU 合计约 **770–890%**；load **9.5–11.2**（10 核满载）。
  - **fseventsd：45s 内几乎全程 0.0%**（偶见 0.2–0.6）；**mds 多数 0**，偶见 ~2%。
  - **npm ci**（本轮 4 路重叠安装，02:42:32–02:43:00 UTC）：s1 **17.6s**、s2 **16.2s**、s3 **16.7s**、s4 **9.2s**（并发写盘略慢于单路 7–12s，仍属热 cache）。
- 验证结果：即使 **4 shard 同机 Vitest 满载**，在已禁用 Spotlight 的前提下 **fseventsd 不再是 CPU 瓶颈**；瓶颈是 **node/vitest 本身**。昨天截图里 fseventsd ~98% 更可能是未关索引前或别的写盘洪峰场景，与当前配置下的稳态不同。
- 回滚方式：无。

## 2026-07-21 10:39 CST - 只读：用户重跑 job 后二次采样 fseventsd

- 服务器：`mac-mini`
- 操作人：`Grok`（只读）
- 原因：用户重启若干 CI job，要求再核对 fseventsd / npm ci / vitest。
- 影响：无变更。
- 做了什么：90s 间隔 3s 采样 load / Worker / node 合计 CPU / fseventsd / mds；读四 slot 最新 Worker 日志的 Install 耗时；对照 GitHub runner busy 与 `iCare-frontend-mas` 进行中的 Sonar run。
- 当时状态（10:39–10:41 CST）：
  - 本机仅 **`mac-mini-sonar-3` busy**，跑 `Frontend Tests 1/4`（PR CYP-1428 / run 侧 in_progress；同 run 其它 shard 落在共享池其它机器）。
  - 命令：`vitest run ... --maxWorkers=2 --shard=1/4`（run-once）。
  - **npm ci**：slot3 本轮 **7.06s** exit 0；slot1 重跑 **10.79s** 后 job **Canceled**；slot2 上一次为 Sonar 路径 Checkout 失败后 Install 异常（exit 127），**Failed**。
  - **90s 内 fseventsd 全程 ~0.0%**；mds 偶发尖峰 23% / 8.7% / 4.5%，多数采样 0。
  - load ~3.0–3.4；Vitest 两 worker 合计约 200–250% CPU 属正常。
- 验证结果：重跑后仍看不到「fseventsd 吃满」；热 `npm ci` 更短（7–11s）。本机此轮并发只有 1 个 frontend test job，**未形成多 slot 同时解压** 的最坏写盘窗口。
- 回滚方式：无。

## 2026-07-21 10:30 CST - 只读：CI 运行中核对 fseventsd/mds 与 npm ci / vitest

- 服务器：`mac-mini`
- 操作人：`Grok`（只读排查）
- 原因：用户已排除 Spotlight 整盘索引后 mds 基本消失，但仍关心 fseventsd；需在 runner 实际跑 job 时核对 prefer-offline 与 `vitest run` 是否生效。
- 影响：无变更（只读）。
- 做了什么：
  1. SSH 采样进程 / load / 内存 / 磁盘 / `~/.npm` / 四 slot workFolder。
  2. 从 `mac-mini-sonar-2/3` 当前 Worker 日志读 `Install Dependencies` 耗时。
  3. `mdutil -s` 确认索引状态；`mdfind` 在 `~/gha` 下无 node_modules 索引命中。
- 当时状态（约 10:30 CST）：
  - 主机 uptime ~1h37m（当日早些时候重启过）；load ~5.5–5.8（10 核）。
  - 4 个 Listener 在线；**仅 slot2 + slot3 有 Worker**（Frontend Tests `shard=1/4` 与 `3/4`）。
  - 实测命令：`vitest run ... --maxWorkers=2 --shard=N/4`（run-once，非 watch）。
  - **npm ci**：两 slot 均 `npm ci --prefer-offline --no-audit --fund=false`，elapsed **~12.0–12.3s**，exit 0 → 本机 `~/.npm` 热缓存生效。
  - **fseventsd / mds**：Vitest 阶段连续采样 **~0% CPU**（对比用户昨日截图 fseventsd ~98% 的峰值场景；本次未撞上双 slot 同时 `npm ci` 的写盘洪峰窗口，install 已在 10:25 结束）。
  - Spotlight：`mdutil` 显示 `/` 与 Data 卷 **Indexing and searching disabled**。
  - `~/.npm` **9.5G**（`_cacache` 8.2G）；各 slot `node_modules` ~777–783M；workdir `~/gha/s1..s4` 各约 2.3G。
  - Data 卷 1.8T 已用 1.3T / 可用 468G（75%）。
- 验证结果：与 frontend-mas 配置一致——prefer-offline 热路径约 12s；CI 为 `vitest run`；mds 已压住；**当前 Vitest 中 fseventsd 不占 CPU**。若仍见 fseventsd 飙高，更可能集中在 **多 slot 并发 `npm ci` 解压** 或 4 shard 同时写盘，而非 Vitest watch。
- 回滚方式：无（只读）。

## 2026-07-20 19:48 CST - CI 缓存基线：共享 GOMODCACHE + 修剪 per-slot go-build

- 服务器：`mac-mini`
- 操作人：`Grok`（ce-work U4）
- 原因：四 slot 各有一份 ~1.5G `GOMODCACHE` 重复；go-build 单 slot 已 21–28GB。
- 影响：
  - 种子 `~/gha/cache/go-mod`（自 slot1 rsync），四 slot `.env` 的 `GOMODCACHE` 统一指向该路径；`GOCACHE` 仍 per-slot。
  - 对四 slot 执行 `go clean -cache`（阈值 >20GB），go-build 清空后靠 job 回填。
  - 重启 `mac-mini-sonar-1..4`。
  - 清理 login 用户闲置 `~/Library/Caches/go-build`（~3.4G）。
- 备份：`~/actions-runner/mac-mini-sonar-*/.env.bak.*`
- 回滚：还原 `.env.bak`（旧 per-slot go-mod 目录可能仍在但权限杂乱，优先用共享路径）。
- 验证：四 slot `GOMODCACHE` 相同、`GOCACHE` 各异；LaunchAgent Started。
- 参考：`docs/plans/2026-07-20-001-ops-ci-runner-cache-baseline-plan.md`

## 2026-07-20 13:45 CST - CI 池：加入 frontend-quality-ci（重活仍钉 mac-mini-sonar）

- 服务器：`mac-mini`
- 操作人：`Grok`
- 原因：统一 PR 质量池与测试分片池；Coverage / 完整 Sonar 仍仅 32GB 本机。
- 影响：`mac-mini-sonar-1..4`（id 22–25）追加 `frontend-quality-ci`；保留 `frontend-tests-ci` / `backend-ci` / `mac-mini-sonar`。
- 回滚：`gh api -X DELETE orgs/cypressoai/actions/runners/{22..25}/labels/frontend-quality-ci`
- 参考：`docs/runbooks/ci-runner-pools.md`



## 2026-07-09 00:10 CST - 收敛 frontend-mas CI 队列吞吐到 mac-only 四 runner

- 原因：继续优化 `iCare-frontend-mas` `SonarQube Analysis` 的整体队列吞吐，指标改为同一配置下并发触发两条 PR run 后折算的 `SonarQube Analysis/hour`，重点优化 `Frontend Tests` 阶段而不是单条 run 的最短耗时。
- 影响：
  - `mac-mini` 最终保留 `mac-mini-sonar-1..4` 四个 GitHub Actions runner 在线。
  - `frontend-mas` 最终候选配置：`Frontend Tests` 4 shards，全部跑 `[mac-mini-sonar, frontend-tests-ci, macos, arm64]`，每 shard `VITEST_MAX_WORKERS=2`，即 mac-mini 总 Vitest workers=8。
  - `lemon-imac` / `lemon-imac-2` 不参与最终 `Frontend Tests` shard；保留其 runner 在线但不在最终 workflow 中引用。
  - 前端分支 `optimize/CYP-1246-frontend-ci-queue` / `optimize/CYP-1246-frontend-ci-queue-b` 均推送到最终 commit `122e7088`，用于 PR 双跑验证。
- 回滚方式：
  - 如需回到双 runner 四 worker方案：`launchctl disable gui/501/actions.runner.cypressoai.mac-mini-sonar-{3,4}` 后 `launchctl bootout gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-{3,4}.plist`，并把 workflow 的 `VITEST_MAX_WORKERS` 改回 `4`。
  - 如需恢复 lemon 混合实验：把 workflow 拆成 mac shards `1..4/6`（`VITEST_MAX_WORKERS=2`）和 lemon shards `5..6/6`（`VITEST_MAX_WORKERS=1`）。
- 做了什么：
  - 复测 mac-only 4 runner × 2 workers × 4 shards：run `28948596797` / `28948599595` 双绿，吞吐 `7.045/h`。
  - 测试 mac-only 4 runner × 2 workers × 8 shards：首次 run `28949983957` / `28949988495` 一绿一红；修复 `BenefitPlanCreateInnerIllnessLimitsDrawer.test.tsx` 高负载等待边界后，run `28951878491` / `28951882286` 双绿但吞吐仅 `6.44/h`，低于 4 shards。
  - 复测 mac-only 4 shards 最新状态：run `28953384903` / `28953388341` 双绿，吞吐 `6.723/h`。
  - 测试 mac + lemon 混合 6 shards：run `28954798224` / `28954802865` 双绿，吞吐 `6.642/h`；`lemon-imac` 的 `5/6` shard 两次约 12 分钟，形成长尾。
  - 最终回到 mac-only 4 shards 并验证：run `28956235734` / `28956241233` 双绿，批次窗口 1005 秒，吞吐 `7.164 SonarQube Analysis/hour`。
- 验证结果：
  - `mac-mini` `launchctl list` 显示 `actions.runner.cypressoai.mac-mini-sonar-1..4` 均在线；`launchctl print-disabled gui/501` 显示四个 service 均 enabled。
  - GitHub runner API 显示 `mac-mini-sonar-1..4`、`lemon-imac`、`lemon-imac-2` 均 online 且空闲。
  - 最终 workflow 校验 `npm run check:ci-workflows` 通过。
  - 最终结论：当前最高实测方案是 `mac-mini 4 runner × 每 shard 2 workers × 4 shards`。8 shards 单条 run 可更快，但 GitHub 调度会优先消化同一 run 的剩余 shards，B run 等待变长；lemon 混合池能让 B 更早起跑，但 8GB lemon shard 长尾抵消收益。

## 2026-07-08 21:58 CST - 验证 frontend-mas CI 双 runner 四 worker 吞吐

- 原因：用户希望以“60 分钟内完成多少个 `SonarQube Analysis`”作为 CI 配置优劣指标，并要求同一方案至少同时触发两条 `SonarQube Analysis`，验证真实队列吞吐；目标配置为 `mac-mini` 2 个 runner，每个 frontend test shard 使用 `maxWorkers=4`，总计 8 个 Vitest worker。
- 影响：
  - `mac-mini` 保持仅 `mac-mini-sonar-1`、`mac-mini-sonar-2` 在线，`mac-mini-sonar-3`、`mac-mini-sonar-4` 继续禁用。
  - `frontend-mas` 分支 `optimize/CYP-1246-frontend-ci-queue` 和 `optimize/CYP-1246-frontend-ci-queue-b` 均推送到 commit `48c4d457`，用于并发触发 PR CI。
  - workflow 目标状态为 4 个 frontend test shard 跑在 `[mac-mini-sonar, frontend-tests-ci, macos, arm64]`，`VITEST_MAX_WORKERS=4`。
- 回滚方式：
  - runner 侧如需恢复 4 runner 并发，执行 `launchctl enable gui/501/actions.runner.cypressoai.mac-mini-sonar-{3,4}`，再 `launchctl bootstrap gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-{3,4}.plist` 或 `launchctl kickstart -k`。
  - 仓库侧可把 `frontend-mas/.github/workflows/sonar.yml` 回滚到前一版 shard/worker 配置，或恢复到仅按 `[frontend-tests-ci, macos, arm64]` 调度。
- 做了什么：
  - 修复两处高负载下暴露的测试 flaky：LOA diagnosis drawer 延迟 open callback 清空草稿，以及 Inner/Illness Limits drawer 提交前 AntD Form/useWatch 状态尚未同步。
  - 本地验证 `BenefitPlanCreateInnerIllnessLimitsDrawer.test.tsx` 单文件 7 个测试通过；`VITEST_MAX_WORKERS=4 npm run test:ci -- --shard=2/4` 通过，247 个文件、1579 个测试通过。
  - 顺序推送两个 PR 分支，触发并发 run `28947113047` 和 `28947119750`。
- 验证结果：
  - `mac-mini` 本机 `launchctl list` 仅显示 `actions.runner.cypressoai.mac-mini-sonar-1`、`actions.runner.cypressoai.mac-mini-sonar-2`；`launchctl print-disabled gui/501` 显示 runner3/4 为 disabled。
  - run `28947113047` 成功：A run 创建于 `2026-07-08T13:39:47Z`，完成于 `13:49:57Z`。
  - run `28947119750` 成功：B run 创建于 `2026-07-08T13:39:54Z`，完成于 `13:57:21Z`。
  - 双 run 批次窗口 1055 秒，折算吞吐为 `6.825 SonarQube Analysis/hour`；8 个 frontend shard 全部成功，`frontend_test_step_sum_seconds=1436`，最大 frontend job 排队 864 秒。
  - 队列行为符合预期：A run 先占用两个 mac-mini frontend runner，A 释放 slot 后 B 的 shard 无缝接上；B 初期 queued 不是 runner 卡死，而是双 runner 容量限制下的正常排队。

## 2026-07-08 18:09 CST - 收敛 frontend-mas CI 到 mac-mini 双 runner

- 原因：排查 `iCare-frontend-mas` PR #1036 的 `Frontend Tests` flaky。失败 run 中 `frontend-tests-ci` 同时调度到 `lemon-imac`、`lemon-imac-2`、`mac-mini-sonar-1..2`，而 `lemon-imac` 只有 8GB 内存；在 `maxWorkers=4` 下 jsdom/AntD 测试明显变慢并触发默认 `waitFor/findBy` 1s 等待边界，出现断言/元素查找 flaky。
- 影响：
  - `mac-mini` 仅保留 `mac-mini-sonar-1`、`mac-mini-sonar-2` 两个 GitHub Actions runner 在线。
  - `mac-mini-sonar-3`、`mac-mini-sonar-4` 的 LaunchAgent 已 `disable` 并 `bootout`，不删除 runner 目录、不移除 GitHub runner 注册、不改 token。
  - `frontend-mas` 分支 `feature/CYP-1241-test-ci-maxworkers-6` 保留 PR frontend test 4 片，但让 shard 只匹配 `[mac-mini-sonar, frontend-tests-ci, macos, arm64]`，在两个在线 mac-mini runner 上分批执行，避免继续落到 `lemon-imac`；汇总 `Frontend Tests` job 改到 `mas-go-dev`，避免空 echo job 排队占 Mac runner。
- 备份：
  - 操作前 `launchctl print gui/501/actions.runner.cypressoai.mac-mini-sonar-{1,2,3,4}` 已读出当前 plist 路径、工作目录、stdout/stderr 路径和运行状态。
  - 操作前 GitHub API 显示 `mac-mini-sonar-1..4` 均为 `online` 且 `busy=false`，标签均包含 `mac-mini-sonar,macos,arm64,backend-ci,frontend-sonar-ci,frontend-tests-ci`。
- 回滚方式：
  - 重新启用 runner3/4：`launchctl enable gui/501/actions.runner.cypressoai.mac-mini-sonar-3`、`launchctl enable gui/501/actions.runner.cypressoai.mac-mini-sonar-4`。
  - 再拉起服务：`launchctl bootstrap gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-3.plist`、`launchctl bootstrap gui/501 ~/Library/LaunchAgents/actions.runner.cypressoai.mac-mini-sonar-4.plist`；如已加载但未运行，可用 `launchctl kickstart -k gui/501/actions.runner.cypressoai.mac-mini-sonar-3` 和 `-4`。
  - 仓库侧回滚：把 `frontend-mas/.github/workflows/sonar.yml` 的 frontend test runner 标签恢复为原 `[frontend-tests-ci, macos, arm64]`；如需恢复 4 个 mac-mini runner 同机并发，再启用 runner3/4。
- 做了什么：
  - 通过 GitHub run 日志确认失败 run `28932383075` 中 2/4 在 `mac-mini-sonar-2` 失败、4/4 在 `lemon-imac` 失败，失败点分别是 `BenefitPlanCreateInnerIllnessLimitsDrawer.test.tsx:246` 的 `saveMutate` 等待未满足、`SpecializationTemplatePage.test.tsx:220` 找不到 `Change` 按钮。
  - 本地在 `frontend-mas` 运行两个失败测试文件，`maxWorkers=4` 下 15 个测试全部通过；再运行 `npm run test:ci -- --shard=1/2`，489 个文件、3025 个测试通过。
  - 执行 `launchctl disable gui/501/actions.runner.cypressoai.mac-mini-sonar-{3,4}` 和对应 `launchctl bootout`，停用 runner3/4。
- 验证结果：
  - `mac-mini` 本机 `launchctl list` 仅剩 `actions.runner.cypressoai.mac-mini-sonar-1`、`actions.runner.cypressoai.mac-mini-sonar-2`。
  - `ps` 仅显示 runner1/2 的 `runsvc.sh` 与 `Runner.Listener`，无 runner3/4 进程。
  - `launchctl print-disabled gui/501` 显示 runner1/2 为 `enabled`，runner3/4 为 `disabled`。
  - GitHub API 显示 `mac-mini-sonar-1`、`mac-mini-sonar-2` 为 `online`，`mac-mini-sonar-3`、`mac-mini-sonar-4` 为 `offline`。
  - 最终验证 run `28935448141` 通过：`Frontend Tests 1/4..4/4`、`Typecheck`、`SonarQube Scan`、汇总 `Frontend Tests` 均为 `success`；实际测试 shard 使用 `--maxWorkers=4 --shard=N/4`，两个在线 mac-mini runner 分批执行。

## 2026-07-08 02:23 CST - 只读盘点 frontend-mas runner 本地缓存现状

- 原因：用户询问 frontend test runner 的缓存方案是在 workflow 侧还是 runner 侧配置，以及 `lemon-imac` 与 `mac-mini` 当前缓存现状。
- 影响：仅读取 workflow 配置和本机 runner 目录大小；未修改 runner、workflow、缓存目录或服务。
- 观察结果：
  - `frontend-mas/.github/workflows/sonar.yml` 未使用 `actions/cache`，`actions/setup-node` 未配置 `cache: npm`；依赖安装通过 `npm ci --prefer-offline --no-audit --fund=false` 使用本机 npm cache。
  - `mac-mini` 四个 runner slot 分别使用 `/Users/konghai/gha/s1..s4`，工作目录互相隔离。
  - 用户级 npm cache `/Users/konghai/.npm` 约 `9.5G`，由同一 macOS 用户下的四个 runner slot 共享。
  - 四个 slot 各自有独立 Node tool cache：`_tool/node/24.16.0/arm64`，每个 runner root 的 `_tool` 约 `730M`。
  - 四个 slot 的 `iCare-frontend-mas` workspace 各自保留 `.git` 约 `130-134M`；`s2..s4` 当前保留 `node_modules` 约 `755-765M`，`s1` 当前未见可统计的 `node_modules`。
- 结论：当前缓存主要是 self-hosted runner 的本机持久缓存，不是 GitHub 远端 cache；同机共享的是用户级 npm tarball cache，workspace / Node tool cache 仍按 runner slot 独立。

## 2026-07-08 01:22 CST - 为 mac-mini sonar runner 加入 frontend-tests-ci 共享测试池

- 原因：`frontend-mas` PR 的 `Frontend Tests` 是合并排队主要瓶颈。单纯把一个 PR 的测试拆到 `mac-mini` + `lemon-imac` 混合 6 片收益不稳定；新策略改为提升整体吞吐量：保留 4 片测试，但让 `mac-mini` 4 个 slot 与 `lemon-imac` 2 个 slot 共同接同一类 frontend test shard。
- 影响：
  - GitHub 组织 `cypressoai` 中 `mac-mini-sonar-1..4` 新增自定义标签 `frontend-tests-ci`。
  - `frontend-mas` PR 分支的 `sonar.yml` 已把 `Frontend Tests` shard job 和汇总 job 的 `runs-on` 改为 `[frontend-tests-ci, macos, arm64]`。
  - 未 SSH 登录 `mac-mini`，未修改本机 runner 文件，未重启 runner。
- 回滚方式：
  - 从 `mac-mini-sonar-1..4` 的 GitHub runner labels 中移除 `frontend-tests-ci`。
  - `frontend-mas/.github/workflows/sonar.yml` 恢复为 `[mac-mini-sonar, macos, arm64]`。
- 验证结果：
  - GitHub API 显示 `mac-mini-sonar-1..4` 均包含 `frontend-tests-ci`、`macos`、`arm64`。
  - `frontend-mas` workflow 校验通过：`npm run check:ci-workflows`、`actionlint -ignore 'label ".*" is unknown' .github/workflows/sonar.yml`、YAML parse。

## 2026-06-10 17:49 CST

- 原因：单 runner 串行化后 CI 队列大量积压，用户要求恢复 4 个 runner 并发以消化排队任务。
- 影响：`mac-mini-sonar-1..4` 全部重新在线，恢复同机最多 4 个 job 并发；重 CPU job 并发时会重新出现互相抢核的情况（见 17:05 审计）。`icare-sql-edge` 保持停止，本次未改动。
- 回滚方式：如需回到单 runner 串行化，分别在 `~/actions-runner/mac-mini-sonar-{2,3,4}` 执行 `./svc.sh stop`（停止前确认对应 slot 无 active `Runner.Worker`）。
- 做了什么：按 17:20 记录的回滚方式，在 `~/actions-runner/mac-mini-sonar-{2,3,4}` 依次执行 `./svc.sh start`，重新启动三个 launch agent；`mac-mini-sonar-1` 一直在线未动。
- 验证结果：`launchctl list` 显示 `actions.runner.cypressoai.mac-mini-sonar-1..4` 均为 Started（退出码 0）；`ps` 显示 4 个 `Runner.Listener` 全部运行，其中 runner1 已有 active `Runner.Worker` 在跑 job，2..4 listener 就绪等待领取排队任务。

## 2026-06-10 17:20 CST

- 原因：优化 `iCare-frontend-mas` PR CI 的 `Frontend Tests` 单 job 耗时。前一轮审计确认 4 个 `mac-mini-sonar-*` runner 可同机并发，重 CPU Vitest job 会互相抢核；用户决定牺牲少见的多 job 并发，优先让单 job 独占主机资源。同时用户确认 `icare-sql-edge` 已不重要，可以停止以释放内存。
- 影响：`mac-mini` 当前只保留 `mac-mini-sonar-1` 一个 GitHub Actions runner 在线；同一时间只会有一个匹配 `mac-mini-sonar` / `macos` / `arm64` 的 job 在该主机运行，其它 job 会排队。`icare-sql-edge` 容器已停止，且不会随 Docker Desktop / 主机重启自动拉起。未删除 runner 注册、runner 工作目录、tool cache、npm cache、容器或卷。
- 回滚方式：如需恢复 4 runner 并发，分别执行 `cd ~/actions-runner/mac-mini-sonar-2 && ./svc.sh start`、`cd ~/actions-runner/mac-mini-sonar-3 && ./svc.sh start`、`cd ~/actions-runner/mac-mini-sonar-4 && ./svc.sh start`。如需恢复 SQL Edge，执行 `docker update --restart=always icare-sql-edge && docker start icare-sql-edge`。
- 做了什么：预检时 `mac-mini-sonar-1` 正在跑一个既有 `iCare-frontend-mas` Vitest job，`mac-mini-sonar-2..4` 没有 active `Runner.Worker`；因此只停止 `2..4`，未打断正在 runner1 上执行的 job。
- 做了什么：在各 runner 目录执行 `./svc.sh stop`，停止 `mac-mini-sonar-2`、`mac-mini-sonar-3`、`mac-mini-sonar-4` 三个 launch agent。
- 做了什么：记录 `icare-sql-edge` 原状态为 `restart=always status=running`，执行 `docker update --restart=no icare-sql-edge` 后停止容器。
- 验证结果：`launchctl list` 仅显示 `actions.runner.cypressoai.mac-mini-sonar-1`；`ps` 仅显示 runner1 的 `Runner.Listener`，无 active `Runner.Worker` / `vitest` / `forks.js`；`docker inspect` 显示 `/icare-sql-edge restart=no status=exited`。停止后 `docker stats` 不再列出 `icare-sql-edge`，`sonarqube` 约占 `3.8GiB`；load average 从操作前约 `13.85 12.32 16.11` 逐步回落到约 `4.34 8.05 12.78`，swap 使用从约 `5290MiB` 小幅降到约 `5258MiB`。
- 后续建议：runner 侧已完成“单 runner 串行化”。前端仓的 `--maxWorkers` 是 `package.json` 中的脚本参数，不属于 runner 配置；建议前端项目侧先把 `test:ci` 从 `--maxWorkers=2` 提到 `8` 做 PR 验证，`10` 作为后续对照压测候选。若队列等待时间变得不可接受，再恢复 `2..4` 或改为专用 label 分流。

## 2026-06-10 17:05 CST

- 原因：评估 `iCare-frontend-mas` PR CI 中 `Frontend Tests` 耗时较长的问题，确认 self-hosted GitHub Actions runner 的并发模型和主机负载，以决定是否能安全提高 Vitest `--maxWorkers`。
- 影响：仅做只读 SSH 查询，未修改 runner、workflow、容器或系统配置；不影响正在运行的 CI。
- 回滚方式：无配置变更，无需回滚。如后续按建议调整 runner label / service，需要在执行前另行备份并确认。
- 做了什么：确认 `mac-mini` 当前只有 4 个 GitHub Actions runner service，分别为 `mac-mini-sonar-1..4`，均通过 `launchctl` 运行；对应 `workFolder` 分别为 `/Users/konghai/gha/s1..s4`。
- 做了什么：确认当前 4 个 runner slot 可并发执行 job。审计时 4 个 slot 同时在跑 `iCare-frontend-mas` 的 Vitest：每个 job 脚本为 `vitest run --reporter=dot --maxWorkers=2 --testTimeout=30000`，总计约 8 个 Vitest worker fork 同机并发。
- 做了什么：采样主机资源：`hw.ncpu=10`，其中性能核 4 个、能效核 6 个；审计时 load average 约 `32.49 25.26 18.97`，CPU `0.0% idle`，内存 `31G used`，swap 已使用约 `5.3G`。Docker Desktop VM 常驻运行，容器包括 `sonarqube`、`sonar-postgres`、`icare-sql-edge` 等，其中 `icare-sql-edge` 约占 `8.8GiB`，`sonarqube` 约占 `3.6GiB`。
- 验证结果：瓶颈不是 runner 空闲核心未被单 job 使用，而是 4 个独立 runner 允许同一台主机并发跑多个重 CPU 的 frontend test job。若不调整 runner / workflow 调度，安全的 `vitest --maxWorkers` 上限仍应保持 `2`；直接改为 `4` 会把最坏情况推到 `4 job × 4 workers = 16` 个 CPU 密集 worker，超过该机器实际可承受并发，容易让整体更慢或触发 Vitest watchdog。
- 后续建议：若目标是缩短单个 PR 的 `Frontend Tests` 延迟，应先做资源隔离，例如给 1 个 runner slot 增加专用 label（如 `mac-mini-frontend-test`）并让 frontend test job 只调度到该 label，再把 `--maxWorkers` 提到 `4`；其余 `mac-mini-sonar-*` slot 继续服务 SonarQube Scan / 轻量 job。若继续让 4 个 slot 都承接 frontend test job，则不建议提高 `--maxWorkers`。

## 2026-06-09 14:03 CST

- 原因：`backend` / `frontend-mas` pin 到含 SQSCANGHA-135 修复的 `SonarSource/sonarqube-scan-action` commit 后，Scanner CLI 8.1.0.6389 默认启用 GPG 签名校验。mac-mini 已安装 `/opt/homebrew/bin/gpg`，但 4 个 GitHub Actions runner service 的 `.path` 不包含 `/opt/homebrew/bin`，导致 CI 报 `GPG is not available`。修复 PATH 后又暴露出第二层问题：默认 `workFolder: _work` 生成的 `RUNNER_TEMP` 路径过深，Sonar action 的临时 `GNUPGHOME` 下 `S.gpg-agent` / `S.dirmngr` socket 接近 macOS 路径限制，导致 `File name too long` / `gpg-agent: IPC connect call failed`。
- 影响：两轮重启 `mac-mini-sonar-1..4` runner service。第一次修改 `.path` 时先重启空闲的 `1/2/4`，等待 `mac-mini-sonar-3` 的 `Runner.Worker` 退出后再重启 `3`；第二次确认无 `Runner.Worker` 后统一重启 4 个 runner。期间一个 frontend PR run 的 `Frontend Tests` 被 runner2 重启打断，已通过 GitHub `force-cancel` 结束，并重新触发 PR run。
- 回滚方式：把对应 runner 目录的 `.path.bak.20260609-140142` 复制回 `.path`，把 `.runner.bak.20260609-142350` 复制回 `.runner`，再执行该 runner 目录下的 `./svc.sh stop && ./svc.sh start`。
- 做了什么：备份并修改 4 个 runner 的 `.path`，在原 PATH 前追加 `/opt/homebrew/bin`。

```text
/opt/homebrew/bin:/Users/konghai/.cargo/bin:/Users/konghai/.volta/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

- 做了什么：备份并修改 4 个 runner 的 `.runner`，把 `workFolder` 改到短路径。

```text
mac-mini-sonar-1: /Users/konghai/gha/s1
mac-mini-sonar-2: /Users/konghai/gha/s2
mac-mini-sonar-3: /Users/konghai/gha/s3
mac-mini-sonar-4: /Users/konghai/gha/s4
```

- 验证结果：4 个 `Runner.Listener` 进程的实际 `PATH` 均包含 `/opt/homebrew/bin`；以各自进程 PATH 执行 `command -v gpg` 均返回 `/opt/homebrew/bin/gpg`，`gpg --version` 返回 `gpg (GnuPG) 2.5.18`；短路径下 `S.gpg-agent` 路径长度约 68；`launchctl list` 显示 `actions.runner.cypressoai.mac-mini-sonar-1..4` 均为 Started；`backend` PR SonarQube Scan 重跑成功；`frontend-mas` PR SonarQube PR Scan 重跑成功。后续抽样多个 PR run，4 个 slot 均已写入 `/Users/konghai/gha/s{1..4}/_tool/sonar-scanner-cli/8.1.0-build.6389/macosx-aarch64` 且有 `.complete` 标记；`mac-mini-sonar-1`、`2`、`4` 已在日志中出现 `Using cached Sonar Scanner CLI from:`，确认缓存命中；`mac-mini-sonar-3` 已完成冷下载和缓存写入，等待下一次同 slot Sonar job 观察二次命中。
